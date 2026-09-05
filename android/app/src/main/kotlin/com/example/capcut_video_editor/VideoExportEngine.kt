package com.example.capcut_video_editor

import android.content.ContentValues
import android.content.Context
import android.graphics.*
import android.media.*
import android.net.Uri
import android.opengl.*
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.view.Surface
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min

/**
 * Data structures for video export payload passed from Flutter
 */
data class ExportClip(
    val id: String,
    val path: String?,
    val isPhoto: Boolean,
    val color: Int,
    val title: String,
    val originalDurationMs: Long,
    val trimStartMs: Long,
    val trimEndMs: Long,
    val speed: Double,
    val volume: Double,
    val rotationDegrees: Int,
    val flipHorizontal: Boolean,
    val flipVertical: Boolean
) {
    val activeDurationMs: Long
        get() {
            val trimmed = (trimEndMs - trimStartMs).coerceAtLeast(0L)
            val sp = if (speed > 0.0) speed else 1.0
            return (trimmed / sp).toLong()
        }
}

data class ExportTransition(
    val leftClipId: String,
    val rightClipId: String,
    val type: String,
    val durationMs: Long,
    val enabled: Boolean
)

data class ExportAudioTrack(
    val path: String,
    val startTimeMs: Long,
    val trimStartMs: Long,
    val trimEndMs: Long,
    val volume: Double
)

/**
 * High-performance hardware video export engine using Android MediaCodec,
 * EGL / OpenGL ES 2.0 InputSurface, and Canvas-based 12-type visual transition compositing.
 */
class VideoExportEngine(private val context: Context) {
    companion object {
        private const val TAG = "VideoExportEngine"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC // H.264
        private const val IFRAME_INTERVAL = 1 // 1 second keyframes
        private const val EGL_RECORDABLE_ANDROID = 0x3142
    }

    interface ProgressCallback {
        fun onProgress(progress: Double)
    }

    /**
     * EGL InputSurface wrapper for MediaCodec encoder
     */
    private class CodecInputSurface(val surface: Surface, val width: Int, val height: Int) {
        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        private var program = 0
        private var aPositionLoc = 0
        private var aTextureCoordLoc = 0
        private var sTextureLoc = 0
        private var textureId = 0
        private val vertexBuffer: FloatBuffer

        // Quad covering [-1, 1] with texture coords mapped to Bitmap coordinates (top-left 0,0)
        private val quadData = floatArrayOf(
            // X, Y, U, V
            -1.0f, -1.0f, 0.0f, 1.0f,
             1.0f, -1.0f, 1.0f, 1.0f,
            -1.0f,  1.0f, 0.0f, 0.0f,
             1.0f,  1.0f, 1.0f, 0.0f
        )

        init {
            vertexBuffer = ByteBuffer.allocateDirect(quadData.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(quadData)
            vertexBuffer.position(0)

            eglSetup()
            makeCurrent()
            glSetup()
        }

        private fun eglSetup() {
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
                throw RuntimeException("unable to get EGL14 display")
            }
            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
                throw RuntimeException("unable to initialize EGL14")
            }

            val attribList = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL_RECORDABLE_ANDROID, 1,
                EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, configs.size, numConfigs, 0)
            if (numConfigs[0] <= 0 || configs[0] == null) {
                throw RuntimeException("unable to find suitable EGLConfig")
            }

            val contextAttribs = intArrayOf(
                EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
                EGL14.EGL_NONE
            )
            eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
            if (eglContext == EGL14.EGL_NO_CONTEXT) {
                throw RuntimeException("unable to create EGL context")
            }

            val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
            eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surface, surfaceAttribs, 0)
            if (eglSurface == EGL14.EGL_NO_SURFACE) {
                throw RuntimeException("unable to create EGL window surface")
            }
        }

        private fun glSetup() {
            val vShader = """
                attribute vec4 aPosition;
                attribute vec2 aTextureCoord;
                varying vec2 vTextureCoord;
                void main() {
                    gl_Position = aPosition;
                    vTextureCoord = aTextureCoord;
                }
            """.trimIndent()

            val fShader = """
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform sampler2D sTexture;
                void main() {
                    gl_FragColor = texture2D(sTexture, vTextureCoord);
                }
            """.trimIndent()

            val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vShader)
            val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fShader)

            program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vertexShader)
            GLES20.glAttachShader(program, fragmentShader)
            GLES20.glLinkProgram(program)

            aPositionLoc = GLES20.glGetAttribLocation(program, "aPosition")
            aTextureCoordLoc = GLES20.glGetAttribLocation(program, "aTextureCoord")
            sTextureLoc = GLES20.glGetUniformLocation(program, "sTexture")

            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            textureId = textures[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

            GLES20.glViewport(0, 0, width, height)
        }

        private fun loadShader(type: Int, shaderCode: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, shaderCode)
            GLES20.glCompileShader(shader)
            return shader
        }

        fun makeCurrent() {
            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                throw RuntimeException("eglMakeCurrent failed")
            }
        }

        fun drawBitmap(bitmap: Bitmap) {
            GLES20.glUseProgram(program)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            GLES20.glUniform1i(sTextureLoc, 0)

            vertexBuffer.position(0)
            GLES20.glVertexAttribPointer(aPositionLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, vertexBuffer)
            GLES20.glEnableVertexAttribArray(aPositionLoc)

            vertexBuffer.position(2)
            GLES20.glVertexAttribPointer(aTextureCoordLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, vertexBuffer)
            GLES20.glEnableVertexAttribArray(aTextureCoordLoc)

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }

        fun setPresentationTime(nsecs: Long) {
            EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, nsecs)
        }

        fun swapBuffers(): Boolean {
            return EGL14.eglSwapBuffers(eglDisplay, eglSurface)
        }

        fun release() {
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglDestroySurface(eglDisplay, eglSurface)
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(eglDisplay)
            }
            surface.release()
            eglDisplay = EGL14.EGL_NO_DISPLAY
            eglContext = EGL14.EGL_NO_CONTEXT
            eglSurface = EGL14.EGL_NO_SURFACE
        }
    }

    /**
     * Executes the full video export pipeline with real frame extraction,
     * transition compositing (all 12 types), hardware encoding, and gallery registration.
     */
    fun exportVideo(
        clips: List<ExportClip>,
        transitions: List<ExportTransition>,
        audioTracks: List<ExportAudioTrack>,
        targetWidth: Int,
        targetHeight: Int,
        targetFps: Int,
        targetBitrate: Int,
        customOutputName: String?,
        progressCallback: ProgressCallback?
    ): Map<String, Any> {
        require(clips.isNotEmpty()) { "Cannot export video with empty clips" }

        // Align dimensions to multiples of 16 for H.264 encoder compatibility
        val width = (targetWidth / 16) * 16
        val height = (targetHeight / 16) * 16
        val fps = if (targetFps in 15..60) targetFps else 30
        val bitrate = if (targetBitrate > 500_000) targetBitrate else 4_000_000

        // Calculate timeline boundaries and total duration
        var totalDurationMs = 0L
        val clipStartTimes = LongArray(clips.size)
        for (i in clips.indices) {
            clipStartTimes[i] = totalDurationMs
            totalDurationMs += clips[i].activeDurationMs
        }

        if (totalDurationMs <= 0L) {
            totalDurationMs = 1000L // minimum 1 second safety
        }

        val totalFrames = ((totalDurationMs / 1000.0) * fps).toInt().coerceAtLeast(1)
        Log.i(TAG, "Export starting: ${width}x${height} @ ${fps}fps, totalDuration=${totalDurationMs}ms, frames=$totalFrames")

        // Prepare temporary output file
        val tempDir = File(context.cacheDir, "export_tmp").apply { if (!exists()) mkdirs() }
        val tempOutputFile = File(tempDir, "export_${System.currentTimeMillis()}.mp4")
        if (tempOutputFile.exists()) tempOutputFile.delete()

        // Prepare MediaMetadataRetrievers for video clips & Bitmap cache for photos
        val videoRetrievers = mutableMapOf<String, MediaMetadataRetriever>()
        val photoBitmaps = mutableMapOf<String, Bitmap>()

        for (clip in clips) {
            val p = clip.path
            if (!p.isNullOrBlank() && File(p).exists()) {
                if (clip.isPhoto || p.endsWith(".jpg", true) || p.endsWith(".png", true) || p.endsWith(".jpeg", true)) {
                    if (!photoBitmaps.containsKey(p)) {
                        try {
                            val bmp = BitmapFactory.decodeFile(p)
                            if (bmp != null) photoBitmaps[p] = bmp
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed decoding photo at $p: ${e.message}")
                        }
                    }
                } else {
                    if (!videoRetrievers.containsKey(p)) {
                        try {
                            val r = MediaMetadataRetriever()
                            r.setDataSource(p)
                            videoRetrievers[p] = r
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed setting data source for $p: ${e.message}")
                        }
                    }
                }
            }
        }

        // Configure MediaCodec Encoder
        val videoFormat = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, IFRAME_INTERVAL)
        }

        val encoder = MediaCodec.createEncoderByType(MIME_TYPE)
        encoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurfaceRaw = encoder.createInputSurface()
        val inputSurface = CodecInputSurface(inputSurfaceRaw, width, height)
        encoder.start()

        val muxer = MediaMuxer(tempOutputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerStarted = false
        var videoTrackIndex = -1

        // Check for audio track source
        var audioExtractor: MediaExtractor? = null
        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null

        val primaryAudioSource = audioTracks.firstOrNull { it.path.isNotBlank() && File(it.path).exists() }?.path
            ?: clips.firstOrNull { it.path != null && File(it.path).exists() && !it.isPhoto }?.path

        if (primaryAudioSource != null) {
            try {
                val extractor = MediaExtractor()
                extractor.setDataSource(primaryAudioSource)
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        extractor.selectTrack(i)
                        audioFormat = format
                        audioExtractor = extractor
                        break
                    }
                }
                if (audioFormat == null) {
                    extractor.release()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Audio track setup skipped: ${e.message}")
            }
        }

        // Compositing Bitmaps and Canvas
        val targetBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val targetCanvas = Canvas(targetBitmap)

        val outgoingBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val outgoingCanvas = Canvas(outgoingBitmap)

        val incomingBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val incomingCanvas = Canvas(incomingBitmap)

        val bufferInfo = MediaCodec.BufferInfo()

        fun drainEncoder(endOfStream: Boolean) {
            val timeoutUs = if (endOfStream) 10000L else 0L
            while (true) {
                val encoderStatus = encoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                if (encoderStatus == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (!endOfStream) break
                    else break
                } else if (encoderStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (muxerStarted) {
                        throw RuntimeException("format changed twice")
                    }
                    val newFormat = encoder.outputFormat
                    videoTrackIndex = muxer.addTrack(newFormat)
                    if (audioFormat != null) {
                        audioTrackIndex = muxer.addTrack(audioFormat)
                    }
                    muxer.start()
                    muxerStarted = true
                } else if (encoderStatus >= 0) {
                    val encodedData = encoder.getOutputBuffer(encoderStatus)
                        ?: throw RuntimeException("encoderOutputBuffer $encoderStatus was null")

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        bufferInfo.size = 0
                    }

                    if (bufferInfo.size != 0) {
                        if (!muxerStarted) {
                            throw RuntimeException("muxer hasn't started")
                        }
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(videoTrackIndex, encodedData, bufferInfo)
                    }

                    encoder.releaseOutputBuffer(encoderStatus, false)

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }
        }

        try {
            val frameDurationMs = 1000.0 / fps
            for (frameIndex in 0 until totalFrames) {
                val currentTimeMs = (frameIndex * frameDurationMs).toLong()

                // 1. Identify which clip is active or whether we are in a transition window
                var activeTransition: ExportTransition? = null
                var leftClipIndex = -1
                var rightClipIndex = -1
                var transitionProgress = 0.0

                for (i in 0 until clips.size - 1) {
                    val left = clips[i]
                    val right = clips[i + 1]
                    val boundaryTimeMs = clipStartTimes[i] + left.activeDurationMs

                    val trans = transitions.firstOrNull {
                        it.enabled && it.leftClipId == left.id && it.rightClipId == right.id && it.type != "none"
                    }
                    if (trans != null && trans.durationMs > 0) {
                        val halfDurationMs = trans.durationMs / 2
                        val transitionStartMs = boundaryTimeMs - halfDurationMs
                        val transitionEndMs = boundaryTimeMs + halfDurationMs

                        if (currentTimeMs in transitionStartMs..transitionEndMs) {
                            activeTransition = trans
                            leftClipIndex = i
                            rightClipIndex = i + 1
                            transitionProgress = ((currentTimeMs - transitionStartMs).toDouble() / trans.durationMs)
                                .coerceIn(0.0, 1.0)
                            break
                        }
                    }
                }

                // 2. Render Frame
                targetCanvas.drawColor(Color.BLACK)

                if (activeTransition != null && leftClipIndex != -1 && rightClipIndex != -1) {
                    // Transition Compositing
                    val leftClip = clips[leftClipIndex]
                    val rightClip = clips[rightClipIndex]

                    val leftLocalMs = ((currentTimeMs - clipStartTimes[leftClipIndex]) * leftClip.speed + leftClip.trimStartMs).toLong()
                    val rightLocalMs = ((currentTimeMs - clipStartTimes[rightClipIndex]) * rightClip.speed + rightClip.trimStartMs).toLong().coerceAtLeast(rightClip.trimStartMs)

                    val leftFrame = getClipBitmap(leftClip, leftLocalMs, videoRetrievers, photoBitmaps)
                    val rightFrame = getClipBitmap(rightClip, rightLocalMs, videoRetrievers, photoBitmaps)

                    outgoingCanvas.drawColor(Color.BLACK)
                    drawClipToCanvas(outgoingCanvas, leftClip, leftFrame, width, height)

                    incomingCanvas.drawColor(Color.BLACK)
                    drawClipToCanvas(incomingCanvas, rightClip, rightFrame, width, height)

                    compositeTransition(
                        targetCanvas,
                        outgoingBitmap,
                        incomingBitmap,
                        activeTransition.type,
                        transitionProgress.toFloat(),
                        width,
                        height
                    )
                } else {
                    // Single Clip Frame
                    var activeClipIndex = 0
                    for (i in clips.indices) {
                        val clipStart = clipStartTimes[i]
                        val clipEnd = clipStart + clips[i].activeDurationMs
                        if (currentTimeMs in clipStart until clipEnd) {
                            activeClipIndex = i
                            break
                        }
                    }
                    val clip = clips[activeClipIndex]
                    val localMs = ((currentTimeMs - clipStartTimes[activeClipIndex]) * clip.speed + clip.trimStartMs).toLong()
                    val frame = getClipBitmap(clip, localMs, videoRetrievers, photoBitmaps)
                    drawClipToCanvas(targetCanvas, clip, frame, width, height)
                }

                // 3. Submit Frame to EGL surface & MediaCodec
                inputSurface.makeCurrent()
                inputSurface.drawBitmap(targetBitmap)
                val ptsNs = (frameIndex * (1_000_000_000L / fps))
                inputSurface.setPresentationTime(ptsNs)
                inputSurface.swapBuffers()

                drainEncoder(false)

                // Report progress
                if (frameIndex % max(1, totalFrames / 20) == 0 || frameIndex == totalFrames - 1) {
                    val p = (frameIndex.toDouble() / totalFrames) * 0.90
                    progressCallback?.onProgress(p)
                }
            }

            // Signal End of Video Stream
            encoder.signalEndOfInputStream()
            drainEncoder(true)

            // 4. Remux Audio Track if available
            if (audioExtractor != null && audioTrackIndex != -1 && muxerStarted) {
                try {
                    val maxBufferSize = if (audioFormat?.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE) == true) {
                        audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                    } else {
                        256 * 1024
                    }
                    val audioBuffer = ByteBuffer.allocate(maxBufferSize)
                    val audioBufferInfo = MediaCodec.BufferInfo()

                    while (true) {
                        audioBufferInfo.offset = 0
                        audioBufferInfo.size = audioExtractor.readSampleData(audioBuffer, 0)
                        if (audioBufferInfo.size < 0) {
                            break
                        }
                        audioBufferInfo.presentationTimeUs = audioExtractor.sampleTime
                        if (audioBufferInfo.presentationTimeUs > totalDurationMs * 1000L) {
                            break // Reached timeline end
                        }
                        audioBufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(audioTrackIndex, audioBuffer, audioBufferInfo)
                        audioExtractor.advance()
                    }
                } catch (audioEx: Exception) {
                    Log.w(TAG, "Audio sample remuxing error: ${audioEx.message}")
                }
            }

            progressCallback?.onProgress(0.95)

        } finally {
            // Clean up encoder and surfaces
            try {
                if (muxerStarted) {
                    muxer.stop()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Muxer stop exception: ${e.message}")
            }
            try { muxer.release() } catch (e: Exception) {}
            try { encoder.stop() } catch (e: Exception) {}
            try { encoder.release() } catch (e: Exception) {}
            try { inputSurface.release() } catch (e: Exception) {}
            try { audioExtractor?.release() } catch (e: Exception) {}
            videoRetrievers.values.forEach { try { it.release() } catch (e: Exception) {} }
            photoBitmaps.values.forEach { try { it.recycle() } catch (e: Exception) {} }
            targetBitmap.recycle()
            outgoingBitmap.recycle()
            incomingBitmap.recycle()
        }

        if (!tempOutputFile.exists() || tempOutputFile.length() == 0L) {
            throw RuntimeException("Export failed: Output file was empty or not generated.")
        }

        // 5. Register video into MediaStore Gallery
        val galleryResult = registerToMediaStore(tempOutputFile, customOutputName)
        progressCallback?.onProgress(1.0)

        return mapOf(
            "success" to true,
            "path" to tempOutputFile.absolutePath,
            "uri" to (galleryResult["uri"] ?: ""),
            "displayName" to (galleryResult["displayName"] ?: tempOutputFile.name),
            "sizeBytes" to tempOutputFile.length(),
            "durationMs" to totalDurationMs
        )
    }

    private fun getClipBitmap(
        clip: ExportClip,
        timeMs: Long,
        videoRetrievers: Map<String, MediaMetadataRetriever>,
        photoBitmaps: Map<String, Bitmap>
    ): Bitmap? {
        val path = clip.path ?: return null
        if (photoBitmaps.containsKey(path)) {
            return photoBitmaps[path]
        }
        val retriever = videoRetrievers[path] ?: return null
        return try {
            val timeUs = (timeMs * 1000L).coerceAtLeast(0L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 1280, 720)
                    ?: retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
            } else {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun drawClipToCanvas(
        canvas: Canvas,
        clip: ExportClip,
        frame: Bitmap?,
        width: Int,
        height: Int
    ) {
        if (frame != null && !frame.isRecycled) {
            val srcRect = Rect(0, 0, frame.width, frame.height)
            val frameRatio = frame.width.toFloat() / frame.height.toFloat()
            val targetRatio = width.toFloat() / height.toFloat()

            val dstRect: Rect
            if (frameRatio > targetRatio) {
                val drawH = (width / frameRatio).toInt()
                val top = (height - drawH) / 2
                dstRect = Rect(0, top, width, top + drawH)
            } else {
                val drawW = (height * frameRatio).toInt()
                val left = (width - drawW) / 2
                dstRect = Rect(left, 0, left + drawW, height)
            }

            canvas.save()
            if (clip.rotationDegrees != 0 || clip.flipHorizontal || clip.flipVertical) {
                canvas.rotate(clip.rotationDegrees.toFloat(), width / 2f, height / 2f)
                canvas.scale(
                    if (clip.flipHorizontal) -1f else 1f,
                    if (clip.flipVertical) -1f else 1f,
                    width / 2f,
                    height / 2f
                )
            }
            canvas.drawBitmap(frame, srcRect, dstRect, null)
            canvas.restore()
        } else {
            // Draw placeholder vibrant graphic
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                clip.color,
                0xFF1A1A2E.toInt(),
                Shader.TileMode.CLAMP
            )
            paint.shader = shader
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

            paint.shader = null
            paint.color = Color.WHITE
            paint.textSize = (height * 0.05f).coerceAtLeast(24f)
            paint.textAlign = Paint.Align.CENTER
            canvas.drawText(clip.title, width / 2f, height / 2f, paint)
        }
    }

    /**
     * Composites outgoing and incoming frames for all 12 transition types
     */
    private fun compositeTransition(
        canvas: Canvas,
        outgoing: Bitmap,
        incoming: Bitmap,
        type: String,
        progress: Float,
        width: Int,
        height: Int
    ) {
        val p = progress.coerceIn(0.0f, 1.0f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        when (type) {
            "fade" -> {
                paint.alpha = ((1.0f - p) * 255).toInt()
                canvas.drawBitmap(outgoing, 0f, 0f, paint)
                paint.alpha = (p * 255).toInt()
                canvas.drawBitmap(incoming, 0f, 0f, paint)
            }
            "dissolve" -> {
                val smooth = p * p * (3.0f - 2.0f * p)
                paint.alpha = ((1.0f - smooth) * 255).toInt()
                canvas.drawBitmap(outgoing, 0f, 0f, paint)
                paint.alpha = (smooth * 255).toInt()
                canvas.drawBitmap(incoming, 0f, 0f, paint)
            }
            "blackFade" -> {
                canvas.drawColor(Color.BLACK)
                if (p < 0.5f) {
                    val outAlpha = (1.0f - p * 2.0f).coerceIn(0.0f, 1.0f)
                    paint.alpha = (outAlpha * 255).toInt()
                    canvas.drawBitmap(outgoing, 0f, 0f, paint)
                } else {
                    val inAlpha = ((p - 0.5f) * 2.0f).coerceIn(0.0f, 1.0f)
                    paint.alpha = (inAlpha * 255).toInt()
                    canvas.drawBitmap(incoming, 0f, 0f, paint)
                }
            }
            "whiteFade" -> {
                canvas.drawColor(Color.WHITE)
                if (p < 0.5f) {
                    val outAlpha = (1.0f - p * 2.0f).coerceIn(0.0f, 1.0f)
                    paint.alpha = (outAlpha * 255).toInt()
                    canvas.drawBitmap(outgoing, 0f, 0f, paint)
                } else {
                    val inAlpha = ((p - 0.5f) * 2.0f).coerceIn(0.0f, 1.0f)
                    paint.alpha = (inAlpha * 255).toInt()
                    canvas.drawBitmap(incoming, 0f, 0f, paint)
                }
            }
            "slideLeft" -> {
                canvas.save()
                canvas.translate(-p * width, 0f)
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                canvas.restore()

                canvas.save()
                canvas.translate((1.0f - p) * width, 0f)
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "slideRight" -> {
                canvas.save()
                canvas.translate(p * width, 0f)
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                canvas.restore()

                canvas.save()
                canvas.translate((p - 1.0f) * width, 0f)
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "slideUp" -> {
                canvas.save()
                canvas.translate(0f, -p * height)
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                canvas.restore()

                canvas.save()
                canvas.translate(0f, (1.0f - p) * height)
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "slideDown" -> {
                canvas.save()
                canvas.translate(0f, p * height)
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                canvas.restore()

                canvas.save()
                canvas.translate(0f, (p - 1.0f) * height)
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "wipeLeft" -> {
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                val clipLeft = width * (1.0f - p)
                canvas.save()
                canvas.clipRect(clipLeft, 0f, width.toFloat(), height.toFloat())
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "wipeRight" -> {
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                val clipRight = width * p
                canvas.save()
                canvas.clipRect(0f, 0f, clipRight, height.toFloat())
                canvas.drawBitmap(incoming, 0f, 0f, null)
                canvas.restore()
            }
            "zoomIn" -> {
                canvas.drawBitmap(outgoing, 0f, 0f, null)
                val s = p.coerceIn(0.01f, 1.0f)
                canvas.save()
                canvas.scale(s, s, width / 2f, height / 2f)
                paint.alpha = (p * 255).toInt()
                canvas.drawBitmap(incoming, 0f, 0f, paint)
                canvas.restore()
            }
            "zoomOut" -> {
                canvas.drawBitmap(incoming, 0f, 0f, null)
                val s = (1.0f - p).coerceIn(0.01f, 1.0f)
                canvas.save()
                canvas.scale(s, s, width / 2f, height / 2f)
                paint.alpha = ((1.0f - p) * 255).toInt()
                canvas.drawBitmap(outgoing, 0f, 0f, paint)
                canvas.restore()
            }
            else -> {
                if (p < 0.5f) {
                    canvas.drawBitmap(outgoing, 0f, 0f, null)
                } else {
                    canvas.drawBitmap(incoming, 0f, 0f, null)
                }
            }
        }
    }

    private fun registerToMediaStore(sourceFile: File, customName: String?): Map<String, String> {
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

            val resolver = context.contentResolver
            val videoUri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
                ?: return mapOf("path" to sourceFile.absolutePath, "displayName" to displayName)

            resolver.openOutputStream(videoUri)?.use { outputStream ->
                sourceFile.inputStream().use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            contentValues.clear()
            contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(videoUri, contentValues, null, null)

            return mapOf(
                "uri" to videoUri.toString(),
                "path" to sourceFile.absolutePath,
                "displayName" to displayName
            )
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
                context,
                arrayOf(targetFile.absolutePath),
                arrayOf("video/mp4"),
                null
            )

            return mapOf(
                "path" to targetFile.absolutePath,
                "uri" to Uri.fromFile(targetFile).toString(),
                "displayName" to displayName
            )
        }
    }
}
