package com.example.gallery_image

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var downloadId: Long = -1L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gallery_image/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadApk" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("BAD_URL", "Missing apk url", null)
                            return@setMethodCallHandler
                        }
                        val fileName = call.argument<String>("fileName")
                            ?: "gallery-update.apk"
                        downloadId = enqueueDownload(url, fileName)
                        result.success(downloadId)
                    }

                    "getProgress" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: downloadId
                        val state = queryProgress(id)
                        if (state == null) {
                            result.error("NOT_FOUND", "Download not found", null)
                        } else {
                            result.success(state)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // Enqueues the APK on the system DownloadManager. DownloadManager runs
    // in the system's download provider, so no storage or install
    // permission is needed here: REQUEST_INSTALL_PACKAGES must never be
    // declared (Google Play Protect blocks such apps as droppers).
    // The completed-download notification opens Android's installer when
    // the user taps it.
    private fun enqueueDownload(url: String, fileName: String): Long {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("Gallery update")
            .setDescription("Downloading the new version")
            .setMimeType("application/vnd.android.package-archive")
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
        return manager.enqueue(request)
    }

    private fun queryProgress(id: Long): Map<String, Any?>? {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(id)
        manager.query(query)?.use { cursor ->
            if (!cursor.moveToFirst()) return null

            val status = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            )
            val received = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            )
            val total = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            )
            return mapOf(
                "status" to statusName(status),
                "received" to received,
                "total" to total
            )
        }
        return null
    }

    private fun statusName(status: Int): String = when (status) {
        DownloadManager.STATUS_SUCCESSFUL -> "successful"
        DownloadManager.STATUS_FAILED -> "failed"
        DownloadManager.STATUS_PAUSED -> "paused"
        DownloadManager.STATUS_RUNNING -> "running"
        else -> "pending"
    }
}
