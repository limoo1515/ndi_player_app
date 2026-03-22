package com.antigravity.ndi_player_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.antigravity/ndi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the View Factory for Android NDI View
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "ndi-view", NdiViewFactory()
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSources" -> {
                    // Call the native NDI scanner (from LibNDI)
                    val sources = getNativeSources()
                    result.success(sources)
                }
                "connectToSource" -> {
                    val name = call.argument<String>("name")
                    if (name != null) {
                        connectToNativeSource(name)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARG", "Source name is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // These would call the JNI bridge to the NDI SDK
    private fun getNativeSources(): List<String> {
        // Mocking for now, but LibNDI.getSources() would go here
        return listOf("Scan result: No official SDK JNI linked yet")
    }

    private fun connectToNativeSource(name: String) {
        // LibNDI.connect(name)
    }
}
