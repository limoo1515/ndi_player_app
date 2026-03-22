import Flutter
import UIKit

class NDIViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return NDIView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger)
    }
}

class NDIView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var imageView: UIImageView
    private var displayTimer: DisplayLinkTimer?
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        
        imageView = UIImageView(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _view.addSubview(imageView)
        
        super.init()
        
        // Start pulling frames
        displayTimer = DisplayLinkTimer { [weak self] in
            self?.updateFrame()
        }
    }

    func view() -> UIView {
        return _view
    }

    private func updateFrame() {
        guard let frame = NDIManager.shared.receiveNextFrame() else { return }
        
        // Convert NDI frame to UIImage
        // NDIlib_recv_color_format_BGRX_BGRA is used here
        // The frame contains a pointer to the raw pixels (p_data)
        
        let width = Int(frame.xres)
        let height = Int(frame.yres)
        let lineStride = Int(frame.line_stride_in_bytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        let context = CGContext(
            data: frame.p_data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: lineStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )

        if let cgImage = context?.makeImage() {
            DispatchQueue.main.async {
                self.imageView.image = UIImage(cgImage: cgImage)
            }
        }
        
        // Free the frame back to NDI
        var mutFrame = frame
        NDIManager.shared.freeVideoFrame(&mutFrame)
    }
    
    deinit {
        displayTimer?.stop()
    }
}

// Simple wrapper for CADisplayLink
class DisplayLinkTimer {
    private var displayLink: CADisplayLink?
    private var callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        self.displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        self.displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func onDisplayLink() {
        callback()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
