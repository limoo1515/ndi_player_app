import Foundation
import UIKit
import Metal

// Note: Ensure NDI SDK is linked to the project for this to compile.
// Header imports will be handled via the Bridging Header.

class NDIManager: NSObject {
    static let shared = NDIManager()
    
    // NDI state
    private var findInstance: NDIlib_find_instance_t?
    private var recvInstance: NDIlib_recv_instance_t?
    private var connectedSource: String?
    
    // UI/Metal rendering support
    private var renderer: NDIFrameRenderer?
    
    override init() {
        super.init()
        // Initialize NDI library
        if !NDIlib_initialize() {
            print("Failed to initialize NDI library")
            return
        }
        
        // Create finder instance
        let findCreate = NDIlib_find_create_t(show_local_sources: true, groups: nil, extra_ips: nil)
        findInstance = NDIlib_find_create_v2(&findCreate)
    }
    
    deinit {
        stopAll()
        NDIlib_destroy()
    }
    
    func stopAll() {
        if let recv = recvInstance {
            NDIlib_recv_destroy(recv)
            recvInstance = nil
        }
        if let find = findInstance {
            NDIlib_find_destroy(find)
            findInstance = nil
        }
    }
    
    func getSources() -> [String] {
        guard let find = findInstance else { return [] }
        
        // Wait for sources to update (non-blocking in this context but SDK requires wait)
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
    
    func connect(to sourceName: String) {
        // Find the source object from the list
        guard let find = findInstance else { return }
        
        var noSources: UInt32 = 0
        let currentSources = NDIlib_find_get_current_sources(find, &noSources)
        
        var targetSource: NDIlib_source_t?
        if noSources > 0, let sources = currentSources {
            for i in 0..<Int(noSources) {
                let name = String(cString: sources[i].p_ndi_name)
                if name == sourceName {
                    targetSource = sources[i]
                    break
                }
            }
        }
        
        guard let source = targetSource else {
            print("Source not found: \(sourceName)")
            return
        }
        
        // Cleanup existing receiver
        if let existing = recvInstance {
            NDIlib_recv_destroy(existing)
        }
        
        // Create receiver instance
        var recvCreate = NDIlib_recv_create_v3_t()
        recvCreate.source_to_connect_to = source
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        recvCreate.bandwidth = NDIlib_recv_bandwidth_highest
        recvCreate.allow_video_fields = false
        
        recvInstance = NDIlib_recv_create_v3(&recvCreate)
        connectedSource = sourceName
        
        print("Connected to NDI source: \(sourceName)")
    }
    
    // This function will be called by the NDIView to pull frames
    func receiveNextFrame() -> NDIlib_video_frame_v2_t? {
        guard let recv = recvInstance else { return nil }
        
        var videoFrame = NDIlib_video_frame_v2_t()
        var audioFrame = NDIlib_audio_frame_v2_t()
        var metadataFrame = NDIlib_metadata_frame_t()
        
        let res = NDIlib_recv_capture_v2(recv, &videoFrame, &audioFrame, &metadataFrame, 33)
        
        switch res {
        case NDIlib_frame_type_video:
            return videoFrame
        case NDIlib_frame_type_audio:
            // Release audio immediately for now
            NDIlib_recv_free_audio_v2(recv, &audioFrame)
        case NDIlib_frame_type_metadata:
            NDIlib_recv_free_metadata(recv, &metadataFrame)
        default:
            break
        }
        
        return nil
    }
    
    func freeVideoFrame(_ frame: inout NDIlib_video_frame_v2_t) {
        if let recv = recvInstance {
            NDIlib_recv_free_video_v2(recv, &frame)
        }
    }
}
