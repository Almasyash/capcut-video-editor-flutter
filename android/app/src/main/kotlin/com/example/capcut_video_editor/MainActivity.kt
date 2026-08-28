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
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "com.mahmas.studio/file_picker"
    private val TTS_CHANNEL = "com.mahmas.studio/tts"
    private val VIDEO_PLAYER_CHANNEL = "com.mahmas.studio/video_player"
    private val AUDIO_PLAYER_CHANNEL = "com.mahmas.studio/audio_player"
    private val PERMISSION_REQUEST_CODE = 1001
    private val FILE_PICKER_REQUEST_CODE = 1002

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var tts: TextToSpeech? = null
    private val videoPlayers = mutableMapOf<Long, Triple<MediaPlayer, TextureRegistry.SurfaceTextureEntry, Surface>>()
    private var audioPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            tts = TextToSpeech(this, this)
        } catch (e: Exception) {
            // TTS init fallback
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            try {
                tts?.language = Locale.US
            } catch (e: Exception) {}
        }
    }

    override fun onDestroy() {
        for ((_, playerTriple) in videoPlayers) {
            try {
                if (playerTriple.first.isPlaying) {
                    playerTriple.first.stop()
                }
                playerTriple.first.release()
                playerTriple.third.release()
                playerTriple.second.release()
            } catch (e: Exception) {}
        }
        videoPlayers.clear()

        try {
            if (audioPlayer?.isPlaying == true) {
                audioPlayer?.stop()
            }
            audioPlayer?.release()
            audioPlayer = null
        } catch (e: Exception) {}

        try {
            tts?.stop()
            tts?.shutdown()
        } catch (e: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "tts_${System.currentTimeMillis()}")
                    } catch (e: Exception) {}
                    result.success(true)
                }
                "stop" -> {
                    try {
                        tts?.stop()
                    } catch (e: Exception) {}
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    if (!file.exists() || file.length() == 0L) {
                        result.error("FILE_NOT_FOUND", "Video file does not exist at $path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val entry: TextureRegistry.SurfaceTextureEntry = flutterEngine.renderer.createSurfaceTexture()
                        val surfaceTexture: android.graphics.SurfaceTexture = entry.surfaceTexture()
                        val surface = Surface(surfaceTexture)
                        val player = MediaPlayer()
                        player.setSurface(surface)
                        player.setAudioAttributes(
                            AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .build()
                        )
                        player.setDataSource(file.absolutePath)
                        val textureId = entry.id()
                        videoPlayers[textureId] = Triple(player, entry, surface)

                        player.setOnPreparedListener { mp ->
                            result.success(mapOf(
                                "textureId" to textureId,
                                "durationMs" to mp.duration,
                                "width" to mp.videoWidth,
                                "height" to mp.videoHeight
                            ))
                        }
                        player.setOnErrorListener { _, what, extra ->
                            try {
                                player.release()
                                surface.release()
                                entry.release()
                                videoPlayers.remove(textureId)
                            } catch (e: Exception) {}
                            false
                        }
                        player.prepareAsync()
                    } catch (e: Exception) {
                        result.error("PLAYER_INIT_ERROR", e.message, null)
                    }
                }
                "play" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            playerTriple.first.start()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "pause" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            if (playerTriple.first.isPlaying) {
                                playerTriple.first.pause()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PAUSE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "seekTo" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val positionMs = (call.argument<Number>("positionMs"))?.toInt() ?: 0
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                playerTriple.first.seekTo(positionMs.toLong(), MediaPlayer.SEEK_CLOSEST)
                            } else {
                                playerTriple.first.seekTo(positionMs)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SEEK_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "setVolume" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val volume = (call.argument<Number>("volume"))?.toFloat() ?: 1.0f
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            val clampedVol = volume.coerceIn(0.0f, 1.0f)
                            playerTriple.first.setVolume(clampedVol, clampedVol)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("VOLUME_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "setSpeed" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val speed = (call.argument<Number>("speed"))?.toFloat() ?: 1.0f
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val params = playerTriple.first.playbackParams
                                params.speed = speed.coerceIn(0.25f, 4.0f)
                                playerTriple.first.playbackParams = params
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SPEED_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "setLooping" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val looping = call.argument<Boolean>("looping") ?: false
                    val playerTriple = videoPlayers[textureId]
                    if (playerTriple != null) {
                        try {
                            playerTriple.first.isLooping = looping
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOOP_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "dispose" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val playerTriple = videoPlayers.remove(textureId)
                    if (playerTriple != null) {
                        try {
                            if (playerTriple.first.isPlaying) {
                                playerTriple.first.stop()
                            }
                            playerTriple.first.release()
                            playerTriple.third.release()
                            playerTriple.second.release()
                        } catch (e: Exception) {}
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    if (!file.exists() || file.length() == 0L) {
                        result.error("FILE_NOT_FOUND", "Audio file not found at $path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        audioPlayer?.release()
                        audioPlayer = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .build()
                            )
                            setDataSource(file.absolutePath)
                            setOnPreparedListener { mp ->
                                result.success(mapOf(
                                    "durationMs" to mp.duration
                                ))
                            }
                            setOnErrorListener { _, _, _ ->
                                audioPlayer?.release()
                                audioPlayer = null
                                false
                            }
                            prepareAsync()
                        }
                    } catch (e: Exception) {
                        result.error("AUDIO_INIT_ERROR", e.message, null)
                    }
                }
                "play" -> {
                    try {
                        audioPlayer?.start()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.message, null)
                    }
                }
                "pause" -> {
                    try {
                        if (audioPlayer?.isPlaying == true) {
                            audioPlayer?.pause()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PAUSE_ERROR", e.message, null)
                    }
                }
                "seekTo" -> {
                    val positionMs = (call.argument<Number>("positionMs"))?.toInt() ?: 0
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            audioPlayer?.seekTo(positionMs.toLong(), MediaPlayer.SEEK_CLOSEST)
                        } else {
                            audioPlayer?.seekTo(positionMs)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SEEK_ERROR", e.message, null)
                    }
                }
                "setVolume" -> {
                    val volume = (call.argument<Number>("volume"))?.toFloat() ?: 1.0f
                    try {
                        audioPlayer?.setVolume(volume, volume)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "setSpeed" -> {
                    val speed = (call.argument<Number>("speed"))?.toFloat() ?: 1.0f
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioPlayer != null) {
                            val params = audioPlayer!!.playbackParams
                            params.speed = speed.coerceIn(0.25f, 4.0f)
                            audioPlayer!!.playbackParams = params
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SPEED_ERROR", e.message, null)
                    }
                }
                "dispose" -> {
                    try {
                        if (audioPlayer?.isPlaying == true) {
                            audioPlayer?.stop()
                        }
                        audioPlayer?.release()
                        audioPlayer = null
                    } catch (e: Exception) {}
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

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
                "getAppFilesDir" -> {
                    result.success(filesDir.absolutePath)
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
                var durationMs: Long? = null
                var thumbnailPath: String? = null

                try {
                    val sanitizedName = displayName.replace("[^a-zA-Z0-9._-]".toRegex(), "_")
                    val mediaDir = File(filesDir, "media").apply { if (!exists()) mkdirs() }
                    val targetFile = File(mediaDir, sanitizedName)
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

                            // Extract metadata using MediaMetadataRetriever
                            try {
                                val isVideo = mimeType.startsWith("video") || displayName.endsWith(".mp4") || displayName.endsWith(".mov") || displayName.endsWith(".mkv")
                                val isAudio = mimeType.startsWith("audio") || displayName.endsWith(".mp3") || displayName.endsWith(".wav") || displayName.endsWith(".aac")

                                if (isVideo || isAudio) {
                                    val retriever = MediaMetadataRetriever()
                                    retriever.setDataSource(targetFile.absolutePath)
                                    val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                                    if (durationStr != null) {
                                        durationMs = durationStr.toLongOrNull()
                                    }
                                    if (isVideo) {
                                        val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                        if (frame != null) {
                                            val thumbFile = File(mediaDir, "${sanitizedName}_thumb.jpg")
                                            val thumbOut = FileOutputStream(thumbFile)
                                            thumbOut.use { out ->
                                                frame.compress(Bitmap.CompressFormat.JPEG, 85, out)
                                            }
                                            if (thumbFile.exists() && thumbFile.length() > 0) {
                                                thumbnailPath = thumbFile.absolutePath
                                            }
                                        }
                                    }
                                    retriever.release()
                                }
                            } catch (metaEx: Exception) {
                                // Metadata extraction failure is non-fatal
                            }
                        }
                    }
                } catch (e: Exception) {
                    // fallback to content URI
                }

                val responseMap = mutableMapOf<String, Any?>(
                    "uri" to uri.toString(),
                    "path" to localFilePath,
                    "name" to displayName,
                    "size" to fileSize,
                    "mimeType" to mimeType
                )
                if (durationMs != null && durationMs > 0) {
                    responseMap["durationMs"] = durationMs
                }
                if (thumbnailPath != null) {
                    responseMap["thumbnailPath"] = thumbnailPath
                }

                pendingResult?.success(responseMap)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
