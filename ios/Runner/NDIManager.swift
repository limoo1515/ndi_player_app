import Foundation
import UIKit
import AVFoundation

class NDIManager: NSObject {
    static let shared = NDIManager()
    
    // NDI Receive state
    private var findInstance: NDIlib_find_instance_t?
    private var recvInstance: NDIlib_recv_instance_t?
    private var connectedSource: String?
    
    // NDI Send state
    private var sendInstance: NDIlib_send_instance_t?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sendQueue = DispatchQueue(label: "ndi.send.queue")
    
    override init() {
        super.init()
        if !NDIlib_initialize() {
            print("❌ Failed to initialize NDI library")
            return
        }
        var findCreate = NDIlib_find_create_t(show_local_sources: true, p_groups: nil, p_extra_ips: nil)
        findInstance = NDIlib_find_create_v2(&findCreate)
        print("✅ NDI initialized")
    }
    
    deinit {
        stopAll()
        NDIlib_destroy()
    }
    
    func stopAll() {
        stopReceive()
        stopSend()
    }
    
    // ─────────────────────────────
    // RECEIVE
    // ─────────────────────────────
    func stopReceive() {
        if let recv = recvInstance {
            NDIlib_recv_destroy(recv)
            recvInstance = nil
        }
    }
    
    func getSources() -> [String] {
        guard let find = findInstance else { return [] }
        NDIlib_find_wait_for_sources(find, 1000)
        var noSources: UInt32 = 0
        let sources = NDIlib_find_get_current_sources(find, &noSources)
        var sourceNames = [String]()
        if noSources > 0, let sources = sources {
            for i in 0..<Int(noSources) {
                let name = String(cString: sources[i].p_ndi_name)
                sourceNames.append(name)
            }
        }
        return sourceNames
    }
    
    func connect(to sourceName: String, bandwidth: Int = 100) {
        guard let find = findInstance else { return }
        var noSources: UInt32 = 0
        let currentSources = NDIlib_find_get_current_sources(find, &noSources)
        var targetSource: NDIlib_source_t?
        if noSources > 0, let sources = currentSources {
            for i in 0..<Int(noSources) {
                let name = String(cString: sources[i].p_ndi_name)
                if name == sourceName { targetSource = sources[i]; break }
            }
        }
        guard let source = targetSource else {
            print("Source not found: \(sourceName)"); return
        }
        stopReceive()
        
        var recvCreate = NDIlib_recv_create_v3_t()
        recvCreate.source_to_connect_to = source
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        recvCreate.bandwidth = bandwidth >= 100 ? NDIlib_recv_bandwidth_highest : NDIlib_recv_bandwidth_lowest
        recvCreate.allow_video_fields = false
        recvInstance = NDIlib_recv_create_v3(&recvCreate)
        connectedSource = sourceName
        print("✅ Connected to NDI source: \(sourceName)")
    }
    
    func receiveNextFrame() -> NDIlib_video_frame_v2_t? {
        guard let recv = recvInstance else { return nil }
        var videoFrame = NDIlib_video_frame_v2_t()
        var audioFrame = NDIlib_audio_frame_v2_t()
        var metadataFrame = NDIlib_metadata_frame_t()
        let res = NDIlib_recv_capture_v2(recv, &videoFrame, &audioFrame, &metadataFrame, 0)
        switch res {
        case NDIlib_frame_type_video: return videoFrame
        case NDIlib_frame_type_audio: NDIlib_recv_free_audio_v2(recv, &audioFrame)
        case NDIlib_frame_type_metadata: NDIlib_recv_free_metadata(recv, &metadataFrame)
        default: break
        }
        return nil
    }
    
    func freeVideoFrame(_ frame: inout NDIlib_video_frame_v2_t) {
        if let recv = recvInstance { NDIlib_recv_free_video_v2(recv, &frame) }
    }
    
    // ─────────────────────────────
    // SEND (Caméra → NDI)
    // ─────────────────────────────
    func startSend(sourceName: String) {
        // Créer l'instance NDI Send
        let nameBytes = sourceName.utf8CString
        var sendCreate = NDIlib_send_create_t()
        nameBytes.withUnsafeBufferPointer { ptr in
            sendCreate.p_ndi_name = ptr.baseAddress
            sendInstance = NDIlib_send_create(&sendCreate)
        }
        guard sendInstance != nil else {
            print("❌ Failed to create NDI Send instance"); return
        }
        print("✅ NDI Send created: \(sourceName)")
        
        // Configurer la capture caméra
        setupCamera()
    }
    
    func stopSend() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        if let send = sendInstance {
            NDIlib_send_destroy(send)
            sendInstance = nil
        }
        print("⏹ NDI Send stopped")
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Camera not available"); return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sendQueue)
        output.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(output) { session.addOutput(output) }
        
        captureSession = session
        videoOutput = output
        
        sendQueue.async {
            session.startRunning()
            print("📷 Camera capture started")
        }
    }
}

// ─────────────────────────────
// Delegate pour recevoir les frames caméra et les envoyer en NDI
// ─────────────────────────────
extension NDIManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let send = sendInstance else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        var videoFrame = NDIlib_video_frame_v2_t()
        videoFrame.xres = Int32(width)
        videoFrame.yres = Int32(height)
        videoFrame.FourCC = NDIlib_FourCC_type_BGRA
        videoFrame.frame_rate_N = 30000
        videoFrame.frame_rate_D = 1001
        videoFrame.picture_aspect_ratio = Float(width) / Float(height)
        videoFrame.frame_format_type = NDIlib_frame_format_type_progressive
        videoFrame.line_stride_in_bytes = Int32(stride)
        videoFrame.p_data = data?.bindMemory(to: UInt8.self, capacity: stride * height)
        
        NDIlib_send_send_video_v2(send, &videoFrame)
    }
}
