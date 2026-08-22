package com.example.capcut_video_editor

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mahmas.studio/file_picker"
    private val PERMISSION_REQUEST_CODE = 1001
    private val FILE_PICKER_REQUEST_CODE = 1002

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    handleRequestPermissions(result)
                }
                "pickMediaFile" -> {
                    val mediaType = call.argument<String>("type") ?: "media"
                    handlePickMedia(mediaType, result)
                }
                "pickAudioFile" -> {
                    handlePickAudio(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_VIDEO)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_AUDIO)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }

        if (permissions.isEmpty()) {
            result.success(true)
        } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    private fun handlePickMedia(type: String, result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            when (type) {
                "video" -> {
                    this.type = "video/*"
                }
                "image", "photo" -> {
                    this.type = "image/*"
                }
                else -> {
                    this.type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "image/*"))
                }
            }
        }
        try {
            startActivityForResult(Intent.createChooser(intent, "Select Video or Photo"), FILE_PICKER_REQUEST_CODE)
        } catch (e: Exception) {
            result.error("PICKER_ERROR", e.message, null)
            pendingResult = null
        }
    }

    private fun handlePickAudio(result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = "audio/*"
        }
        try {
            startActivityForResult(Intent.createChooser(intent, "Select Audio File"), FILE_PICKER_REQUEST_CODE)
        } catch (e: Exception) {
            result.error("PICKER_ERROR", e.message, null)
            pendingResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_PICKER_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                var displayName = "Imported_Media"
                var fileSize: Long = 0

                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (cursor.moveToFirst()) {
                        if (nameIndex != -1) {
                            displayName = cursor.getString(nameIndex) ?: displayName
                        }
                        if (sizeIndex != -1) {
                            fileSize = cursor.getLong(sizeIndex)
                        }
                    }
                }

                val mimeType = contentResolver.getType(uri) ?: ""

                // Cache file to local app storage for direct filesystem and image loading
                var localFilePath = uri.toString()
                try {
                    val sanitizedName = displayName.replace("[^a-zA-Z0-9._-]".toRegex(), "_")
                    val targetFile = File(cacheDir, sanitizedName)
                    val inputStream: InputStream? = contentResolver.openInputStream(uri)
                    if (inputStream != null) {
                        val outputStream = FileOutputStream(targetFile)
                        inputStream.use { input ->
                            outputStream.use { output ->
                                input.copyTo(output)
                            }
                        }
                        if (targetFile.exists() && targetFile.length() > 0) {
                            localFilePath = targetFile.absolutePath
                        }
                    }
                } catch (e: Exception) {
                    // fallback to content URI
                }

                val responseMap = mapOf(
                    "uri" to uri.toString(),
                    "path" to localFilePath,
                    "name" to displayName,
                    "size" to fileSize,
                    "mimeType" to mimeType
                )
                pendingResult?.success(responseMap)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
