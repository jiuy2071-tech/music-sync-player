package com.example.android_app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_sync_player/storage",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getAvailableBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_path", "Storage path is required.", null)
                return@setMethodCallHandler
            }

            try {
                result.success(StatFs(path).availableBytes)
            } catch (error: Exception) {
                result.error("storage_check_failed", error.message, null)
            }
        }
    }
}
