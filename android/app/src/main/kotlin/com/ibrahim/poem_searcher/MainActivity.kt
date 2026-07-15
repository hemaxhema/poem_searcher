package com.ibrahim.poem_searcher

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "poem_searcher/asset_copy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyAsset" -> {
                        val assetKey = call.argument<String>("assetKey")
                        val targetPath = call.argument<String>("targetPath")
                        if (assetKey == null || targetPath == null) {
                            result.error("ARG", "assetKey and targetPath are required", null)
                        } else {
                            copyAssetToFile(assetKey, targetPath, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Streams the bundled Flutter asset [assetKey] to [targetPath] in small
     * buffers on a background thread, so the ~835 MB database is never held in
     * memory all at once (unlike rootBundle.load, which would OOM). The result
     * is posted back on the main thread. A partial copy is deleted on failure
     * so the version-marker logic in database_preparer.dart re-copies next run.
     */
    private fun copyAssetToFile(
        assetKey: String,
        targetPath: String,
        result: MethodChannel.Result,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            try {
                val target = File(targetPath)
                target.parentFile?.mkdirs()
                // Flutter bundles declared assets under `flutter_assets/`.
                assets.open("flutter_assets/$assetKey").use { input ->
                    FileOutputStream(target).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var read: Int
                        while (input.read(buffer).also { read = it } != -1) {
                            output.write(buffer, 0, read)
                        }
                        output.flush()
                        output.fd.sync()
                    }
                }
                mainHandler.post { result.success(null) }
            } catch (e: Throwable) {
                try {
                    File(targetPath).delete()
                } catch (_: Throwable) {
                    // Best-effort cleanup; ignore.
                }
                mainHandler.post { result.error("COPY_FAILED", e.message, null) }
            }
        }.start()
    }
}
