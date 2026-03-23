import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let ndiChannel = FlutterMethodChannel(name: "com.antigravity/ndi",
                                              binaryMessenger: controller.binaryMessenger)
        
        ndiChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if call.method == "getSources" {
                let sources = NDIManager.shared.getSources()
                result(sources)
            } else if call.method == "connectToSource" {
                if let args = call.arguments as? [String: Any],
                   let name = args["name"] as? String {
                    NDIManager.shared.connect(to: name)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARG", message: "Source name missing", details: nil))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        })
        
        // Register NDI Native View
        let registrar = self.registrar(forPlugin: "NDIPlugin")
        let factory = NDIViewFactory(messenger: controller.binaryMessenger)
        registrar?.register(factory, withId: "ndi-view")
        
        // GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
