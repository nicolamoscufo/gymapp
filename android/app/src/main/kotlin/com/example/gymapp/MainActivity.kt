package com.example.gymapp

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val AI_MODEL_DEVICE_CHANNEL = "gymapp/ai_model_device"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AI_MODEL_DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceProfile" -> result.success(buildAiModelDeviceProfile())
                else -> result.notImplemented()
            }
        }
    }

    private fun buildAiModelDeviceProfile(): Map<String, Any?> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
        val statFs = StatFs(filesDir.absolutePath)

        return mapOf(
            "platform" to "android",
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidSdk" to Build.VERSION.SDK_INT,
            "availableStorageBytes" to statFs.availableBytes,
            "totalMemoryBytes" to memoryInfo.totalMem,
            "lowRamDevice" to activityManager.isLowRamDevice,
            "abis" to Build.SUPPORTED_ABIS.toList(),
        )
    }
}
