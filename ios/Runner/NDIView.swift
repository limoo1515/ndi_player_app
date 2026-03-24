import Flutter
import UIKit
import CoreImage

class NDIViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { return FlutterStandardMessageCodec.sharedInstance() }

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return NDIView(frame: frame, viewIdentifier: viewId, arguments: args, binaryMessenger: messenger)
    }
}

class NDIView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var imageView: UIImageView
    private var isRunning = true
    
    // NDI Receiver
    private var recvInstance: NDIlib_recv_instance_t?
    private let receiveQueue = DispatchQueue(label: "ndi.receive.queue", qos: .userInteractive)
    
    // UI Throttling
    private var lastFrameTime: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 30.0
    
    // CoreImage Context pour rendu GPU (Metal)
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger?) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _view.addSubview(imageView)
        
        super.init()
        
        if let params = args as? [String: Any], let name = params["name"] as? String {
            let quality = params["quality"] as? String ?? "Lowest" // ✅ Support Low Bandwidth Proxy
            self.startReceive(sourceName: name, quality: quality)
        }

        startCaptureLoop()
    }

    func view() -> UIView { return _view }

    private func startReceive(sourceName: String, quality: String) {
        var recvCreate = NDIlib_recv_create_v3_t()
        
        guard let find = NDIManager.shared.findInstance else { return }
        var noSources: UInt32 = 0
        let currentSources = NDIlib_find_get_current_sources(find, &noSources)
        var targetSource: NDIlib_source_t?
        
        if noSources > 0, let sources = currentSources {
            for i in 0..<Int(noSources) {
                if String(cString: sources[i].p_ndi_name) == sourceName {
                    targetSource = sources[i]; break
                }
            }
        }
        
        guard let source = targetSource else { return }
        recvCreate.source_to_connect_to = source
        
        // --- OPTIMISATION RÉSEAU FAIBLE ---
        // On force le mode BGRX (plus simple pour le GPU iOS) 
        // ou Fastest (pourrait être UYVY)
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        
        // Forcer Lowest Bandwidth si le réseau rame
        if quality == "Lowest" || quality == "Medium" {
            recvCreate.bandwidth = NDIlib_recv_bandwidth_lowest
        } else {
            recvCreate.bandwidth = NDIlib_recv_bandwidth_highest
        }
        
        recvCreate.allow_video_fields = true // 50i Fix

        recvInstance = NDIlib_recv_create_v3(&recvCreate)
        print("✅ NDI connected [\(quality)] to \(sourceName)")
    }

    private func startCaptureLoop() {
        receiveQueue.async { [weak self] in
            while self?.isRunning == true {
                guard let recv = self?.recvInstance else {
                    usleep(10000); continue
                }

                var v = NDIlib_video_frame_v2_t()
                var a = NDIlib_audio_frame_v2_t()
                var m = NDIlib_metadata_frame_t()
                
                // --- STRATÉGIE "DROP FRAMES" AGRESSIVE ---
                // On vide COMPLÈTEMENT le tampon réseau pour ne garder que la frame la plus récente.
                // Cela élimine l'effet d'image qui "marche lentement" (rattrapage de retard).
                var latestFrame: NDIlib_video_frame_v2_t?
                while true {
                    let type = NDIlib_recv_capture_v2(recv, &v, &a, &m, 0) // Timeout 0 = Instant
                    if type == NDIlib_frame_type_video {
                        if var old = latestFrame { NDIlib_recv_free_video_v2(recv, &old) }
                        latestFrame = v
                    } else if type == NDIlib_frame_type_audio {
                        NDIlib_recv_free_audio_v2(recv, &a)
                    } else if type == NDIlib_frame_type_metadata {
                        NDIlib_recv_free_metadata(recv, &m)
                    } else {
                        break
                    }
                }
                
                if let video = latestFrame {
                    let now = CACurrentMediaTime()
                    // Throttling à 30fps pour ne pas saturer le thread principal
                    if now - (self?.lastFrameTime ?? 0) >= (self?.frameInterval ?? 0) {
                        self?.lastFrameTime = now
                        self?.renderWithMetal(video)
                    }
                    var mutVideo = video
                    NDIlib_recv_free_video_v2(recv, &mutVideo)
                } else {
                    usleep(2000) // Un peu de repos CPU
                }
            }
        }
    }

    // --- RENDU ACCÉLÉRÉ METAL (VIA CoreImage) ---
    private func renderWithMetal(_ frame: NDIlib_video_frame_v2_t) {
        let width = Int(frame.xres)
        let height = Int(frame.yres)
        let stride = Int(frame.line_stride_in_bytes)
        
        guard let p_data = frame.p_data else { return }
        
        // Création d'une CIImage sans copie mémoire (directement depuis le pointeur)
        let ciImage = CIImage(
            bitmapData: Data(bytesNoCopy: p_data, count: stride * height, deallocator: .none),
            bytesPerRow: stride,
            size: CGSize(width: width, height: height),
            format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        // Rendu GPU vers CGImage (Beaucoup plus rapide que CGContext CPU)
        if let cgImg = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImg)
            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = uiImage
            }
        }
    }

    deinit {
        isRunning = false
        if let recv = recvInstance { NDIlib_recv_destroy(recv) }
    }
}
