package com.agdevelops.ainotescanner

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import android.media.MediaScannerConnection
import android.content.pm.PackageManager
import android.Manifest

class MainActivity : FlutterActivity() {
    private val galleryChannel = "vyro/gallery"
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingLegacySave: Triple<ByteArray, String, String>? = null
    private var pendingLegacyResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("fileName") ?: "vyro_${System.currentTimeMillis()}.jpg"
                val mime = call.argument<String>("mimeType") ?: "image/jpeg"
                if (bytes == null || bytes.isEmpty()) {
                    result.error("empty_image", "Image data is empty", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(bytes, name, mime, result)
                } else if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
                    saveLegacy(bytes, name, mime, result)
                } else {
                    if (pendingLegacyResult != null) {
                        result.error("save_in_progress", "Another gallery save is in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingLegacySave = Triple(bytes, name, mime)
                    pendingLegacyResult = result
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7314)
                }
            }
    }

    private fun saveWithMediaStore(bytes: ByteArray, name: String, mime: String, result: MethodChannel.Result) {
        ioExecutor.execute {
            var uri: android.net.Uri? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, mime)
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/VYRO")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Could not create gallery image")
                contentResolver.openOutputStream(uri!!)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not open gallery image")
                val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                contentResolver.update(uri!!, done, null, null)
                runOnUiThread { result.success(uri.toString()) }
            } catch (error: Exception) {
                uri?.let { contentResolver.delete(it, null, null) }
                runOnUiThread { result.error("gallery_save_failed", error.message, null) }
            }
        }
    }

    private fun saveLegacy(bytes: ByteArray, name: String, mime: String, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                val folder = File(pictures, "VYRO")
                if (!folder.exists() && !folder.mkdirs()) throw IllegalStateException("Cannot create Pictures/VYRO")
                val file = File(folder, name)
                FileOutputStream(file).use { it.write(bytes) }
                MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
                runOnUiThread { result.success(file.absolutePath) }
            } catch (error: Exception) {
                runOnUiThread { result.error("gallery_save_failed", error.message, null) }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7314) return
        val pending = pendingLegacySave
        val result = pendingLegacyResult
        pendingLegacySave = null
        pendingLegacyResult = null
        if (pending == null || result == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            saveLegacy(pending.first, pending.second, pending.third, result)
        } else {
            result.error("permission_denied", "Storage permission is required to save to the gallery", null)
        }
    }
}
