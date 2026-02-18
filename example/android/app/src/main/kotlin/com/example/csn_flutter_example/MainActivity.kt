package com.example.csn_flutter_example

import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val mediaProjectionChannel = "csn_flutter/media_projection"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaProjectionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        val serviceIntent =
                            Intent(this, CsnMediaProjectionForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        val serviceIntent =
                            Intent(this, CsnMediaProjectionForegroundService::class.java)
                        stopService(serviceIntent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
