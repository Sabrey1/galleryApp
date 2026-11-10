package com.example.gallery_image

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var downloadId: Long = -1L
    private var originalCutoutMode: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gallery_image/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                    "setStatusBarVisible" -> {
                        val visible = call.argument<Boolean>("visible") ?: true
                        setStatusBarVisible(visible)
                        result.success(null)
                    }
                    "setNavigationBarVisible" -> {
                        val visible = call.argument<Boolean>("visible") ?: true
                        setNavigationBarVisible(visible)
                        result.success(null)
                    }
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

    private fun setStatusBarVisible(visible: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val attributes = window.attributes
            if (visible) {
                originalCutoutMode?.let { attributes.layoutInDisplayCutoutMode = it }
                originalCutoutMode = null
            } else {
                if (originalCutoutMode == null) {
                    originalCutoutMode = attributes.layoutInDisplayCutoutMode
                }
                attributes.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            window.attributes = attributes
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (visible) {
                controller.show(WindowInsets.Type.statusBars())
            } else {
                controller.hide(WindowInsets.Type.statusBars())
            }
        } else {
            @Suppress("DEPRECATION")
            if (visible) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            } else {
                window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            }
        }
    }

    private fun setNavigationBarVisible(visible: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (visible) {
                controller.show(WindowInsets.Type.navigationBars())
            } else {
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            val flags = window.decorView.systemUiVisibility
            window.decorView.systemUiVisibility = if (visible) {
                flags and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION.inv()
            } else {
                flags or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
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
