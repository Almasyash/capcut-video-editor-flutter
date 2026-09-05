package com.example.capcut_video_editor

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
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

    class VideoPlayerHolder(
        val player: MediaPlayer,
        val entry: TextureRegistry.SurfaceTextureEntry,
        val surface: Surface,
        var isSeeking: Boolean = false,
        var pendingSeekMs: Long? = null,
        var pendingPlay: Boolean = false,
        var pendingSeekResult: MethodChannel.Result? = null
    )

    class AudioPlayerHolder(
        var player: MediaPlayer? = null,
        var isSeeking: Boolean = false,
        var pendingSeekMs: Long? = null,
        var pendingPlay: Boolean = false,
        var pendingSeekResult: MethodChannel.Result? = null
    )

    private val videoPlayers = mutableMapOf<Long, VideoPlayerHolder>()
    private val audioHolder = AudioPlayerHolder()

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

    override fun onPause() {
        pauseAllPlayback()
        super.onPause()
    }

    override fun onStop() {
        pauseAllPlayback()
        super.onStop()
    }

    private fun pauseAllPlayback() {
        for ((_, holder) in videoPlayers) {
            try {
                holder.pendingPlay = false
                if (holder.player.isPlaying) {
                    holder.player.pause()
                }
            } catch (e: Exception) {}
        }
        try {
            audioHolder.pendingPlay = false
            if (audioHolder.player?.isPlaying == true) {
                audioHolder.player?.pause()
            }
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        for ((_, holder) in videoPlayers) {
            try {
                holder.pendingPlay = false
                holder.isSeeking = false
                holder.pendingSeekMs = null
                holder.pendingSeekResult?.success(true)
                holder.pendingSeekResult = null
                if (holder.player.isPlaying) {
                    holder.player.stop()
                }
                holder.player.release()
                holder.surface.release()
                holder.entry.release()
            } catch (e: Exception) {}
        }
        videoPlayers.clear()

        try {
            audioHolder.pendingPlay = false
            audioHolder.isSeeking = false
            audioHolder.pendingSeekMs = null
            audioHolder.pendingSeekResult?.success(true)
            audioHolder.pendingSeekResult = null
            if (audioHolder.player?.isPlaying == true) {
                audioHolder.player?.stop()
            }
            audioHolder.player?.release()
            audioHolder.player = null
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
                        val holder = VideoPlayerHolder(player, entry, surface)
                        videoPlayers[textureId] = holder

                        player.setOnPreparedListener { mp ->
                            android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] ON_PREPARED (video textureId=$textureId, duration=${mp.duration}ms)")
                            result.success(mapOf(
                                "textureId" to textureId,
                                "durationMs" to mp.duration,
                                "width" to mp.videoWidth,
                                "height" to mp.videoHeight
                            ))
                        }

                        player.setOnSeekCompleteListener { mp ->
                            android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Video seek complete at ${mp.currentPosition}ms (pendingSeek=${holder.pendingSeekMs}, pendingPlay=${holder.pendingPlay})")
                            val nextSeek = holder.pendingSeekMs
                            if (nextSeek != null) {
                                holder.pendingSeekMs = null
                                try {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        mp.seekTo(nextSeek, MediaPlayer.SEEK_CLOSEST)
                                    } else {
                                        mp.seekTo(nextSeek.toInt())
                                    }
                                } catch (e: Exception) {
                                    holder.isSeeking = false
                                    holder.pendingSeekResult?.success(true)
                                    holder.pendingSeekResult = null
                                }
                            } else {
                                holder.isSeeking = false
                                if (holder.pendingPlay) {
                                    holder.pendingPlay = false
                                    try {
                                        mp.start()
                                        android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Video started after seek at ${mp.currentPosition}ms")
                                    } catch (e: Exception) {}
                                }
                                holder.pendingSeekResult?.success(true)
                                holder.pendingSeekResult = null
                            }
                        }

                        player.setOnCompletionListener { mp ->
                            android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Video MediaPlayer onCompletion (textureId=$textureId, isLooping=${mp.isLooping})")
                            holder.pendingPlay = false
                            holder.isSeeking = false
                            holder.pendingSeekMs = null
                        }

                        player.setOnErrorListener { _, what, extra ->
                            try {
                                holder.pendingSeekResult?.error("SEEK_ERROR", "Seek error $what $extra", null)
                                holder.pendingSeekResult = null
                                player.release()
                                surface.release()
                                entry.release()
                                videoPlayers.remove(textureId)
                            } catch (e: Exception) {}
                            false
                        }
                        player.isLooping = false
                        player.prepareAsync()
                    } catch (e: Exception) {
                        result.error("PLAYER_INIT_ERROR", e.message, null)
                    }
                }
                "play" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong()
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] MEDIA_PLAYER_START (video textureId=$textureId, pos=$positionMs, isSeeking=${holder.isSeeking})")
                            if (positionMs != null) {
                                val current = try { holder.player.currentPosition.toLong() } catch (e: Exception) { 0L }
                                if (holder.isSeeking) {
                                    holder.pendingSeekMs = positionMs
                                    holder.pendingPlay = true
                                } else if (Math.abs(current - positionMs) > 80L) {
                                    holder.isSeeking = true
                                    holder.pendingPlay = true
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        holder.player.seekTo(positionMs, MediaPlayer.SEEK_CLOSEST)
                                    } else {
                                        holder.player.seekTo(positionMs.toInt())
                                    }
                                } else {
                                    holder.pendingPlay = false
                                    holder.player.start()
                                }
                            } else {
                                if (holder.isSeeking) {
                                    holder.pendingPlay = true
                                } else {
                                    holder.pendingPlay = false
                                    holder.player.start()
                                }
                            }
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
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PLAYER_PAUSED (video textureId=$textureId)")
                            holder.pendingPlay = false
                            holder.pendingSeekMs = null
                            if (holder.player.isPlaying) {
                                holder.player.pause()
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
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            if (holder.isSeeking) {
                                holder.pendingSeekMs = positionMs
                                holder.pendingSeekResult?.success(true)
                                holder.pendingSeekResult = result
                            } else {
                                holder.isSeeking = true
                                holder.pendingSeekResult = result
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    holder.player.seekTo(positionMs, MediaPlayer.SEEK_CLOSEST)
                                } else {
                                    holder.player.seekTo(positionMs.toInt())
                                }
                            }
                        } catch (e: Exception) {
                            holder.isSeeking = false
                            result.error("SEEK_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Player not found for textureId $textureId", null)
                    }
                }
                "setVolume" -> {
                    val textureId = (call.argument<Number>("textureId"))?.toLong() ?: -1L
                    val volume = (call.argument<Number>("volume"))?.toFloat() ?: 1.0f
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            val clampedVol = volume.coerceIn(0.0f, 1.0f)
                            holder.player.setVolume(clampedVol, clampedVol)
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
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val player = holder.player
                                val wasPlaying = player.isPlaying
                                val params = player.playbackParams
                                params.speed = speed.coerceIn(0.25f, 4.0f)
                                player.playbackParams = params
                                android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] SET_SPEED (video textureId=$textureId, speed=$speed, wasPlaying=$wasPlaying)")
                                if (!wasPlaying && player.isPlaying) {
                                    player.pause()
                                    android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PAUSED AFTER SET_SPEED (video textureId=$textureId)")
                                }
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
                    val holder = videoPlayers[textureId]
                    if (holder != null) {
                        try {
                            holder.player.isLooping = looping
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
                    android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PLAYER_DISPOSED (video textureId=$textureId)")
                    val holder = videoPlayers.remove(textureId)
                    if (holder != null) {
                        try {
                            holder.pendingPlay = false
                            holder.isSeeking = false
                            holder.pendingSeekMs = null
                            holder.pendingSeekResult?.success(true)
                            holder.pendingSeekResult = null
                            if (holder.player.isPlaying) {
                                holder.player.stop()
                            }
                            holder.player.release()
                            holder.surface.release()
                            holder.entry.release()
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
                        audioHolder.pendingPlay = false
                        audioHolder.isSeeking = false
                        audioHolder.pendingSeekMs = null
                        audioHolder.pendingSeekResult?.success(true)
                        audioHolder.pendingSeekResult = null
                        audioHolder.player?.release()

                        val player = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .build()
                            )
                            setDataSource(file.absolutePath)
                            setOnPreparedListener { mp ->
                                android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] ON_PREPARED (audio duration=${mp.duration}ms)")
                                result.success(mapOf(
                                    "durationMs" to mp.duration
                                ))
                            }
                            setOnSeekCompleteListener { mp ->
                                android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Audio seek complete at ${mp.currentPosition}ms (pendingSeek=${audioHolder.pendingSeekMs}, pendingPlay=${audioHolder.pendingPlay})")
                                val nextSeek = audioHolder.pendingSeekMs
                                if (nextSeek != null) {
                                    audioHolder.pendingSeekMs = null
                                    try {
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                            mp.seekTo(nextSeek, MediaPlayer.SEEK_CLOSEST)
                                        } else {
                                            mp.seekTo(nextSeek.toInt())
                                        }
                                    } catch (e: Exception) {
                                        audioHolder.isSeeking = false
                                        audioHolder.pendingSeekResult?.success(true)
                                        audioHolder.pendingSeekResult = null
                                    }
                                } else {
                                    audioHolder.isSeeking = false
                                    if (audioHolder.pendingPlay) {
                                        audioHolder.pendingPlay = false
                                        try {
                                            mp.start()
                                            android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Audio started after seek at ${mp.currentPosition}ms")
                                        } catch (e: Exception) {}
                                    }
                                    audioHolder.pendingSeekResult?.success(true)
                                    audioHolder.pendingSeekResult = null
                                }
                            }
                            setOnCompletionListener { mp ->
                                android.util.Log.d("SYNC_TRACE", "[SYNC_TRACE] Audio MediaPlayer onCompletion (isLooping=${mp.isLooping})")
                                audioHolder.pendingPlay = false
                                audioHolder.isSeeking = false
                                audioHolder.pendingSeekMs = null
                            }
                            setOnErrorListener { _, _, _ ->
                                audioHolder.pendingSeekResult?.error("SEEK_ERROR", "Audio error", null)
                                audioHolder.pendingSeekResult = null
                                audioHolder.player?.release()
                                audioHolder.player = null
                                false
                            }
                            isLooping = false
                            prepareAsync()
                        }
                        audioHolder.player = player
                    } catch (e: Exception) {
                        result.error("AUDIO_INIT_ERROR", e.message, null)
                    }
                }
                "play" -> {
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong()
                    val player = audioHolder.player
                    if (player != null) {
                        try {
                            android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] MEDIA_PLAYER_START (audio, pos=$positionMs, isSeeking=${audioHolder.isSeeking})")
                            if (positionMs != null) {
                                val current = try { player.currentPosition.toLong() } catch (e: Exception) { 0L }
                                if (audioHolder.isSeeking) {
                                    audioHolder.pendingSeekMs = positionMs
                                    audioHolder.pendingPlay = true
                                } else if (Math.abs(current - positionMs) > 80L) {
                                    audioHolder.isSeeking = true
                                    audioHolder.pendingPlay = true
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        player.seekTo(positionMs, MediaPlayer.SEEK_CLOSEST)
                                    } else {
                                        player.seekTo(positionMs.toInt())
                                    }
                                } else {
                                    audioHolder.pendingPlay = false
                                    player.start()
                                }
                            } else {
                                if (audioHolder.isSeeking) {
                                    audioHolder.pendingPlay = true
                                } else {
                                    audioHolder.pendingPlay = false
                                    player.start()
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Audio player not initialized", null)
                    }
                }
                "pause" -> {
                    try {
                        android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PLAYER_PAUSED (audio)")
                        audioHolder.pendingPlay = false
                        audioHolder.pendingSeekMs = null
                        if (audioHolder.player?.isPlaying == true) {
                            audioHolder.player?.pause()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PAUSE_ERROR", e.message, null)
                    }
                }
                "seekTo" -> {
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val player = audioHolder.player
                    if (player != null) {
                        try {
                            if (audioHolder.isSeeking) {
                                audioHolder.pendingSeekMs = positionMs
                                audioHolder.pendingSeekResult?.success(true)
                                audioHolder.pendingSeekResult = result
                            } else {
                                audioHolder.isSeeking = true
                                audioHolder.pendingSeekResult = result
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    player.seekTo(positionMs, MediaPlayer.SEEK_CLOSEST)
                                } else {
                                    player.seekTo(positionMs.toInt())
                                }
                            }
                        } catch (e: Exception) {
                            audioHolder.isSeeking = false
                            result.error("SEEK_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "Audio player not initialized", null)
                    }
                }
                "setVolume" -> {
                    val volume = (call.argument<Number>("volume"))?.toFloat() ?: 1.0f
                    try {
                        audioHolder.player?.setVolume(volume, volume)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "setSpeed" -> {
                    val speed = (call.argument<Number>("speed"))?.toFloat() ?: 1.0f
                    try {
                        val player = audioHolder.player
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && player != null) {
                            val wasPlaying = player.isPlaying
                            val params = player.playbackParams
                            params.speed = speed.coerceIn(0.25f, 4.0f)
                            player.playbackParams = params
                            android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] SET_SPEED (audio speed=$speed, wasPlaying=$wasPlaying)")
                            if (!wasPlaying && player.isPlaying) {
                                player.pause()
                                android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PAUSED AFTER SET_SPEED (audio)")
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SPEED_ERROR", e.message, null)
                    }
                }
                "dispose" -> {
                    try {
                        android.util.Log.d("AUTO_PLAY_TRACE", "[AUTO_PLAY_TRACE] PLAYER_DISPOSED (audio)")
                        audioHolder.pendingPlay = false
                        audioHolder.isSeeking = false
                        audioHolder.pendingSeekMs = null
                        audioHolder.pendingSeekResult?.success(true)
                        audioHolder.pendingSeekResult = null
                        if (audioHolder.player?.isPlaying == true) {
                            audioHolder.player?.stop()
                        }
                        audioHolder.player?.release()
                        audioHolder.player = null
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
                "saveVideoToGallery" -> {
                    val path = call.argument<String>("path") ?: ""
                    val customName = call.argument<String>("fileName")
                    handleSaveVideoToGallery(path, customName, result)
                }
                "extractAudioFromVideo" -> {
                    val path = call.argument<String>("path") ?: ""
                    val customName = call.argument<String>("outputName")
                    handleExtractAudioFromVideo(path, customName, result)
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

    private fun handleSaveVideoToGallery(path: String, customName: String?, result: MethodChannel.Result) {
        val sourceFile = File(path)
        if (!sourceFile.exists() || sourceFile.length() == 0L) {
            result.error("FILE_NOT_FOUND", "Exported video file does not exist or is empty at $path", null)
            return
        }

        try {
            val displayName = if (!customName.isNullOrBlank()) {
                if (customName.endsWith(".mp4")) customName else "$customName.mp4"
            } else {
                "MAHMAS_${System.currentTimeMillis()}.mp4"
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val contentValues = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                    put(MediaStore.Video.Media.TITLE, displayName.removeSuffix(".mp4"))
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/MahmasStudio")
                    put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
                    put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }

                val resolver = contentResolver
                val videoUri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
                if (videoUri == null) {
                    result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                    return
                }

                resolver.openOutputStream(videoUri)?.use { outputStream ->
                    sourceFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }

                contentValues.clear()
                contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(videoUri, contentValues, null, null)

                result.success(mapOf(
                    "success" to true,
                    "uri" to videoUri.toString(),
                    "displayName" to displayName
                ))
            } else {
                val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                val targetDir = File(moviesDir, "MahmasStudio").apply { if (!exists()) mkdirs() }
                val targetFile = File(targetDir, displayName)

                sourceFile.inputStream().use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                MediaScannerConnection.scanFile(
                    this,
                    arrayOf(targetFile.absolutePath),
                    arrayOf("video/mp4")
                ) { scannedPath, uri ->
                    runOnUiThread {
                        result.success(mapOf(
                            "success" to true,
                            "path" to (scannedPath ?: targetFile.absolutePath),
                            "uri" to (uri?.toString() ?: ""),
                            "displayName" to displayName
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            result.error("GALLERY_EXPORT_ERROR", "Failed saving video to media gallery: ${e.message}", null)
        }
    }

    private fun handleExtractAudioFromVideo(videoPath: String, customName: String?, result: MethodChannel.Result) {
        if (videoPath.isBlank()) {
            result.error("INVALID_PATH", "Video file path cannot be empty", null)
            return
        }

        val videoFile = File(videoPath)
        if (!videoFile.exists() || videoFile.length() == 0L) {
            result.error("FILE_NOT_FOUND", "Video file does not exist or is empty at $videoPath", null)
            return
        }

        Thread {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(videoFile.absolutePath)
                val trackCount = extractor.trackCount
                var audioTrackIndex = -1
                var audioFormat: MediaFormat? = null

                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        audioFormat = format
                        break
                    }
                }

                if (audioTrackIndex == -1 || audioFormat == null) {
                    extractor.release()
                    runOnUiThread {
                        result.error("NO_AUDIO_TRACK", "This video has no audio track to extract.", null)
                    }
                    return@Thread
                }

                val outputDir = File(filesDir, "extracted_audio").apply { if (!exists()) mkdirs() }
                val sanitizedName = if (!customName.isNullOrBlank()) {
                    val clean = customName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    if (clean.endsWith(".m4a")) clean else "$clean.m4a"
                } else {
                    "extracted_${System.currentTimeMillis()}.m4a"
                }
                val outputFile = File(outputDir, sanitizedName)
                if (outputFile.exists()) {
                    outputFile.delete()
                }

                val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                extractor.selectTrack(audioTrackIndex)
                val muxerTrackIndex = muxer.addTrack(audioFormat)
                muxer.start()

                val maxBufferSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                } else {
                    256 * 1024
                }
                val buffer = ByteBuffer.allocate(maxBufferSize)
                val bufferInfo = MediaCodec.BufferInfo()

                while (true) {
                    bufferInfo.offset = 0
                    bufferInfo.size = extractor.readSampleData(buffer, 0)
                    if (bufferInfo.size < 0) {
                        bufferInfo.size = 0
                        break
                    }
                    bufferInfo.presentationTimeUs = extractor.sampleTime
                    bufferInfo.flags = extractor.sampleFlags
                    muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
                    extractor.advance()
                }

                try {
                    muxer.stop()
                } catch (stopEx: Exception) {
                    android.util.Log.w("AudioExtraction", "Muxer stop warning: ${stopEx.message}")
                }
                muxer.release()
                extractor.release()

                if (!outputFile.exists() || outputFile.length() == 0L) {
                    runOnUiThread {
                        result.error("EXTRACTION_FAILED", "Extracted audio output file was empty or not created", null)
                    }
                    return@Thread
                }

                var durationMs: Long = 0L
                if (audioFormat.containsKey(MediaFormat.KEY_DURATION)) {
                    durationMs = audioFormat.getLong(MediaFormat.KEY_DURATION) / 1000L
                }
                if (durationMs <= 0L) {
                    try {
                        val retriever = MediaMetadataRetriever()
                        retriever.setDataSource(outputFile.absolutePath)
                        val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        durationMs = durStr?.toLongOrNull() ?: 0L
                        retriever.release()
                    } catch (e: Exception) {}
                }

                val responseMap = mapOf(
                    "success" to true,
                    "path" to outputFile.absolutePath,
                    "name" to outputFile.name,
                    "size" to outputFile.length(),
                    "durationMs" to durationMs
                )

                runOnUiThread {
                    result.success(responseMap)
                }
            } catch (e: Exception) {
                try {
                    extractor.release()
                } catch (_: Exception) {}
                runOnUiThread {
                    result.error("EXTRACTION_ERROR", "Failed extracting audio: ${e.message}", null)
                }
            }
        }.start()
    }
}
