package com.example.gymapp

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

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
                "inspectModelArtifact" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing model artifact path", null)
                    } else {
                        inspectModelArtifact(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun inspectModelArtifact(path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path)
                if (!file.exists() || !file.isFile) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "exists" to false,
                                "sizeBytes" to null,
                                "sha256" to "",
                            ),
                        )
                    }
                    return@Thread
                }

                val digest = MessageDigest.getInstance("SHA-256")
                FileInputStream(file).buffered(1024 * 1024).use { input ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        digest.update(buffer, 0, read)
                    }
                }
                val sha256 = digest.digest().joinToString("") { "%02x".format(it) }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "exists" to true,
                            "sizeBytes" to file.length(),
                            "sha256" to sha256,
                        ),
                    )
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.success(
                        mapOf(
                            "exists" to false,
                            "sizeBytes" to null,
                            "sha256" to "",
                            "error" to (error.message ?: error.javaClass.simpleName),
                        ),
                    )
                }
            }
        }.start()
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
