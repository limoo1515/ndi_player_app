import Flutter
import UIKit

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
    
    // RECEPTION & DÉCODAGE IN BACKGROUND
    private var recvInstance: NDIlib_recv_instance_t?
    private let receiveQueue = DispatchQueue(label: "ndi.receive.queue", qos: .userInteractive)
    
    // FPS THROTTLING : Limite l'UI à 30fps pour libérer le thread principal pour les clics
    private var lastFrameTime: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 30.0

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger?) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _view.addSubview(imageView)
        
        super.init()
        
        if let params = args as? [String: Any], let name = params["name"] as? String {
            let quality = params["quality"] as? String ?? "Highest"
            self.startReceive(sourceName: name, quality: quality)
        }

        // Lancement immédiat de la boucle de capture
        startCaptureLoop()
    }

    func view() -> UIView { return _view }

    private func startReceive(sourceName: String, quality: String) {
        // En v3 avec source_to_connect_to pour connexion instantanée
        var recvCreate = NDIlib_recv_create_v3_t()
        
        // On récupère la source via le manager (Finder partagé)
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
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        recvCreate.bandwidth = (quality == "Lowest") ? NDIlib_recv_bandwidth_lowest : NDIlib_recv_bandwidth_highest
        recvCreate.allow_video_fields = true // ✅ Fix TriCaster 50i

        recvInstance = NDIlib_recv_create_v3(&recvCreate)
        print("✅ NDI Receiver created: \(sourceName)")
    }

    private func startCaptureLoop() {
        receiveQueue.async { [weak self] in
            while self?.isRunning == true {
                guard let recv = self?.recvInstance else {
                    usleep(10000) // 10ms d'attente
                    continue
                }

                var v = NDIlib_video_frame_v2_t()
                var a = NDIlib_audio_frame_v2_t()
                var m = NDIlib_metadata_frame_t()
                
                // --- DISCARD LOGIC (Zero-Delay) ---
                // On vide le buffer rapidement pour ne garder que la dernière frame
                var lastVideo: NDIlib_video_frame_v2_t?
                while true {
                    let type = NDIlib_recv_capture_v2(recv, &v, &a, &m, 0)
                    if type == NDIlib_frame_type_video {
                        if var old = lastVideo { NDIlib_recv_free_video_v2(recv, &old) }
                        lastVideo = v
                    } else if type == NDIlib_frame_type_audio {
                        NDIlib_recv_free_audio_v2(recv, &a)
                    } else if type == NDIlib_frame_type_metadata {
                        NDIlib_recv_free_metadata(recv, &m)
                    } else {
                        break
                    }
                }
                
                // Si on a une nouvelle frame vidéo
                if let latestV = lastVideo {
                    let now = CACurrentMediaTime()
                    // ✅ THROTTLING ANTI-LAG : On limite l'affichage à 30fps
                    // pour ne pas saturer le thread principal de Flutter.
                    if now - (self?.lastFrameTime ?? 0) >= (self?.frameInterval ?? 0) {
                        self?.lastFrameTime = now
                        self?.renderAndDisplay(latestV)
                    }
                    var mutLatest = latestV
                    NDIlib_recv_free_video_v2(recv, &mutLatest)
                } else {
                    usleep(1000) // Réduit la charge CPU
                }
            }
        }
    }

    private func renderAndDisplay(_ frame: NDIlib_video_frame_v2_t) {
        let width = Int(frame.xres)
        let height = Int(frame.yres)
        let stride = Int(frame.line_stride_in_bytes)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: frame.p_data,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: stride,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let cgImg = context.makeImage() else { return }
        
        let uiImage = UIImage(cgImage: cgImg)
        
        // Mise à jour finale sur l'UI Thread
        DispatchQueue.main.async { [weak self] in
            // Si la frame est déjà obsolète par rapport à l'UI, on ne l'affiche pas
            self?.imageView.image = uiImage
        }
    }

    deinit {
        isRunning = false
        if let recv = recvInstance { NDIlib_recv_destroy(recv) }
    }
}
