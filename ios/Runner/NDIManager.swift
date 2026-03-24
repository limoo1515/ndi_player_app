import Foundation
import UIKit
import AVFoundation

class NDIManager: NSObject {
    static let shared = NDIManager()
    
    // Discovery (Finder) - SHARED
    var findInstance: NDIlib_find_instance_t?
    
    // NDI Send state (Camera) - SHARED
    private var sendInstance: NDIlib_send_instance_t?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sendQueue = DispatchQueue(label: "ndi.send.queue", qos: .userInitiated)
    
    override init() {
        super.init()
        if !NDIlib_initialize() {
            print("❌ Failed to initialize NDI library")
            return
        }
        
        // Use v2 for better discovery
        var findCreate = NDIlib_find_create_v2_t(show_local_sources: true, p_groups: nil, p_extra_ips: nil)
        findInstance = NDIlib_find_create_v2(&findCreate)
        
        if findInstance == nil {
            print("❌ Failed to create NDI find instance, retrying with default...")
            findInstance = NDIlib_find_create_v2(nil)
        }
        
        print("✅ NDI discovery initialized")
    }
    
    func getSources() -> [String] {
        guard let find = findInstance else { 
            print("⚠️ Find instance is nil")
            return [] 
        }
        
        // Wait multiple times to ensure the cache is populated
        // 1000ms might be short on some networks
        for _ in 0..<2 {
            NDIlib_find_wait_for_sources(find, 1000)
        }
        
        var noSources: UInt32 = 0
        let sources = NDIlib_find_get_current_sources(find, &noSources)
        
        var sourceNames = [String]()
        if noSources > 0, let sources = sources {
            for i in 0..<Int(noSources) {
                let name = String(cString: sources[i].p_ndi_name)
                // Filter out empty names
                if !name.isEmpty {
                    sourceNames.append(name)
                }
            }
        }
        
        print("🔍 Found \(sourceNames.count) NDI sources")
        return sourceNames
    }
    
    // ─────────────────────────────
    // SEND (Camera → NDI)
    // ─────────────────────────────
    func startSend(sourceName: String) {
        if sendInstance != nil { stopSend() }
        
        let nameBytes = sourceName.utf8CString
        var sendCreate = NDIlib_send_create_t()
        nameBytes.withUnsafeBufferPointer { ptr in
            sendCreate.p_ndi_name = ptr.baseAddress
            sendInstance = NDIlib_send_create(&sendCreate)
        }
        guard sendInstance != nil else { return }
        print("✅ NDI Send started: \(sourceName)")
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
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: sendQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        captureSession = session
        videoOutput = output
        sendQueue.async { session.startRunning() }
    }
}

extension NDIManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let send = sendInstance else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        var videoFrame = NDIlib_video_frame_v2_t()
        videoFrame.xres = Int32(width); videoFrame.yres = Int32(height)
        videoFrame.FourCC = NDIlib_FourCC_type_BGRA
        videoFrame.frame_rate_N = 30000; videoFrame.frame_rate_D = 1001
        videoFrame.picture_aspect_ratio = Float(width) / Float(height)
        videoFrame.frame_format_type = NDIlib_frame_format_type_progressive
        videoFrame.line_stride_in_bytes = Int32(stride)
        videoFrame.p_data = data?.bindMemory(to: UInt8.self, capacity: stride * height)
        NDIlib_send_send_video_v2(send, &videoFrame)
    }
}
