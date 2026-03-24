import Flutter
import UIKit
import CoreImage
import AVFoundation

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
    
    // Video Throttling
    private var lastFrameTime: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 30.0
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    
    // --- SYSTÈME AUDIO (MIMO_NDI Audio Player) ---
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger?) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _view.addSubview(imageView)
        
        super.init()
        
        setupAudioEngine()
        
        if let params = args as? [String: Any], let name = params["name"] as? String {
            let quality = params["quality"] as? String ?? "Highest"
            self.startReceive(sourceName: name, quality: quality)
        }

        startCaptureLoop()
    }

    func view() -> UIView { return _view }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let node = playerNode else { return }
        
        engine.attach(node)
        // Format standard NDI (48kHz, Stereo, Float Planar)
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
        
        if let format = audioFormat {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            node.play()
            print("🔊 Audio Engine Started")
        } catch {
            print("❌ Error starting audio engine: \(error)")
        }
    }

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
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        recvCreate.bandwidth = (quality == "Lowest" || quality == "Medium") ? NDIlib_recv_bandwidth_lowest : NDIlib_recv_bandwidth_highest
        recvCreate.allow_video_fields = true

        recvInstance = NDIlib_recv_create_v3(&recvCreate)
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
                
                // Aggressive Drop Frames Strategy
                var latestVideo: NDIlib_video_frame_v2_t?
                
                while true {
                    let type = NDIlib_recv_capture_v2(recv, &v, &a, &m, 0)
                    if type == NDIlib_frame_type_video {
                        if var old = latestVideo { NDIlib_recv_free_video_v2(recv, &old) }
                        latestVideo = v
                    } else if type == NDIlib_frame_type_audio {
                        // --- LECTURE AUDIO ---
                        self?.playAudio(a)
                        var mutA = a
                        NDIlib_recv_free_audio_v2(recv, &mutA)
                    } else if type == NDIlib_frame_type_metadata {
                        NDIlib_recv_free_metadata(recv, &m)
                    } else {
                        break
                    }
                }
                
                if let video = latestVideo {
                    let now = CACurrentMediaTime()
                    if now - (self?.lastFrameTime ?? 0) >= (self?.frameInterval ?? 0) {
                        self?.lastFrameTime = now
                        self?.renderWithMetal(video)
                    }
                    var mutVideo = video
                    NDIlib_recv_free_video_v2(recv, &mutVideo)
                } else {
                    usleep(2000)
                }
            }
        }
    }

    private func playAudio(_ frame: NDIlib_audio_frame_v2_t) {
        let noSamples = Int(frame.no_samples)
        let noChannels = Int(frame.no_channels)
        
        guard let data = frame.p_data, noSamples > 0, noChannels >= 1 else { return }
        guard let player = playerNode, let format = audioFormat else { return }
        
        // On crée un buffer PCM compatible Apple
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(noSamples)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(noSamples)
        
        // NDI est Planar Float32. pcmBuffer.floatChannelData est aussi UnsafePointer<UnsafeMutablePointer<Float>>
        let channels = pcmBuffer.floatChannelData
        let stride = Int(frame.channel_stride_in_bytes) / 4 // conversion offset bytes -> float samples
        
        for ch in 0..<min(noChannels, 2) {
            let channelPointer = data.advanced(by: ch * stride)
            let bufferPointer = channels?[ch]
            if let dest = bufferPointer {
                memcpy(dest, channelPointer, noSamples * 4)
            }
        }
        
        // On envoie le buffer au player
        player.scheduleBuffer(pcmBuffer, at: nil, options: .interrupts)
    }

    private func renderWithMetal(_ frame: NDIlib_video_frame_v2_t) {
        let width = Int(frame.xres)
        let height = Int(frame.yres)
        let stride = Int(frame.line_stride_in_bytes)
        guard let p_data = frame.p_data else { return }
        
        let ciImage = CIImage(
            bitmapData: Data(bytesNoCopy: p_data, count: stride * height, deallocator: .none),
            bytesPerRow: stride,
            size: CGSize(width: width, height: height),
            format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        if let cgImg = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImg)
            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = uiImage
            }
        }
    }

    deinit {
        isRunning = false
        playerNode?.stop()
        audioEngine?.stop()
        if let recv = recvInstance { NDIlib_recv_destroy(recv) }
    }
}
