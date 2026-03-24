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
    private var displayTimer: CADisplayLink?
    
    // CHAQUE VUE A SON PROPRE RÉCEPTEUR (Indispensable pour Multiview 4)
    private var recvInstance: NDIlib_recv_instance_t?
    private var sourceName: String?

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger?) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _view.addSubview(imageView)
        
        super.init()
        
        if let params = args as? [String: Any], let name = params["name"] as? String {
            self.sourceName = name
            let quality = params["quality"] as? String ?? "Highest"
            self.startReceive(sourceName: name, quality: quality)
        }

        displayTimer = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayTimer?.add(to: .main, forMode: .common)
    }

    func view() -> UIView { return _view }

    private func startReceive(sourceName: String, quality: String) {
        guard let find = NDIManager.shared.findInstance else { return }
        
        var noSources: UInt32 = 0
        let currentSources = NDIlib_find_get_current_sources(find, &noSources)
        var targetSource: NDIlib_source_t?
        
        if noSources > 0, let sources = currentSources {
            for i in 0..<Int(noSources) {
                let name = String(cString: sources[i].p_ndi_name)
                if name == sourceName { targetSource = sources[i]; break }
            }
        }
        
        guard let source = targetSource else { return }
        
        // --- CONFIGURATION CHIRURGICALE (Zero-Delay / Switch 100Mbps) ---
        var recvCreate = NDIlib_recv_create_t()
        
        // 1. Gestion du switch 100Mbps (Lowest = 480p / 20ms latency)
        if quality == "Lowest" {
            recvCreate.bandwidth = NDIlib_recv_bandwidth_lowest
        } else {
            recvCreate.bandwidth = NDIlib_recv_bandwidth_highest
        }
        
        // 2. Format de couleur optimisé (Fastest pour le CPU)
        // Note: BGRX est utilisé pour l'affichage direct sur iOS
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        
        // 3. Fix pour ton TriCaster 1080i50 (Désentrelacement hardware)
        recvCreate.allow_video_fields = true 

        // Création du récepteur v3 comme recommandé
        recvInstance = NDIlib_recv_create_v3(&recvCreate)
        
        // Connexion explicite
        var mutSource = source
        NDIlib_recv_connect(recvInstance, &mutSource)
        
        print("✅ NDI connected to \(sourceName) [\(quality)]")
    }

    @objc private func updateFrame() {
        guard let recv = recvInstance else { return }
        
        // --- LOGIQUE DE "DISCARD" : Suppression des 500ms de retard accumulé ---
        var lastVideoFrame: NDIlib_video_frame_v2_t?
        
        while true {
            var v = NDIlib_video_frame_v2_t()
            var a = NDIlib_audio_frame_v2_t()
            var m = NDIlib_metadata_frame_t()
            
            // Timeout à 0 = Instantané (ne bloque pas le thread UI)
            let res = NDIlib_recv_capture_v2(recv, &v, &a, &m, 0)
            
            if res == NDIlib_frame_type_video {
                if var old = lastVideoFrame {
                    NDIlib_recv_free_video_v2(recv, &old)
                }
                lastVideoFrame = v
            } else if res == NDIlib_frame_type_audio {
                NDIlib_recv_free_audio_v2(recv, &a)
            } else if res == NDIlib_frame_type_metadata {
                NDIlib_recv_free_metadata(recv, &m)
            } else {
                break
            }
        }
        
        guard let videoFrame = lastVideoFrame else { return }
        
        // Conversion vers UIImage
        let width = Int(videoFrame.xres)
        let height = Int(videoFrame.yres)
        let lineStride = Int(videoFrame.line_stride_in_bytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        if let context = CGContext(
            data: videoFrame.p_data,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: lineStride,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let cgImage = context.makeImage() {
            self.imageView.image = UIImage(cgImage: cgImage)
        }
        
        var mutFrame = videoFrame
        NDIlib_recv_free_video_v2(recv, &mutFrame)
    }
    
    deinit {
        displayTimer?.invalidate()
        if let recv = recvInstance { NDIlib_recv_destroy(recv) }
    }
}
