package com.example.capcut_video_editor

import android.content.ContentValues
import android.content.Context
import android.graphics.*
import android.media.*
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
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
import java.util.concurrent.CountDownLatch
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
    val flipVertical: Boolean,
    val xPos: Double = 0.0,
    val yPos: Double = 0.0,
    val scale: Double = 1.0,
    val rotationAngle: Double = 0.0
) {
    val activeDurationMs: Long
        get() {
            val trimmed = (trimEndMs - trimStartMs).coerceAtLeast(0L)
            val sp = if (speed > 0.0) speed else 1.0
            return (trimmed / sp).toLong()
        }

    val safeScale: Double
        get() = if (!scale.isFinite() || scale <= 0.0) 1.0 else scale.coerceIn(0.05, 20.0)

    val safeXPos: Double
        get() = if (!xPos.isFinite()) 0.0 else xPos

    val safeYPos: Double
        get() = if (!yPos.isFinite()) 0.0 else yPos

    val safeRotationAngle: Double
        get() = if (!rotationAngle.isFinite()) 0.0 else rotationAngle
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
 * High-performance hardware video export engine using Android MediaExtractor,
 * MediaCodec hardware decoders, SurfaceTexture (GL_TEXTURE_EXTERNAL_OES),
 * EGL / OpenGL ES 2.0 InputSurface, hardware transition shaders, and zero-CPU-copy compositing.
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
     * Sequential Hardware Video Decoder using MediaExtractor + MediaCodec + SurfaceTexture
     */
    class HardwareVideoDecoder(val filePath: String) {
        private var extractor: MediaExtractor? = null
        private var decoder: MediaCodec? = null
        private var surfaceTexture: SurfaceTexture? = null
        private var surface: Surface? = null
        var textureId: Int = 0
            private set
        var videoWidth: Int = 0
            private set
        var videoHeight: Int = 0
            private set
        var videoRotation: Int = 0
            private set
        val stMatrix = FloatArray(16)
        private var isEos = false
        private var currentPtsUs: Long = -1L
        private val bufferInfo = MediaCodec.BufferInfo()
        var isInitialized = false
            private set

        var totalInputWaitNs: Long = 0L
            private set
        var totalOutputWaitNs: Long = 0L
            private set
        var totalSurfaceWaitNs: Long = 0L
            private set

        fun feedInputBuffers() {
            val dec = decoder ?: return
            val ext = extractor ?: return
            if (isEos) return
            val t0 = System.nanoTime()
            try {
                while (!isEos) {
                    val inIdx = try { dec.dequeueInputBuffer(0L) } catch (e: Exception) { -1 }
                    if (inIdx < 0) break
                    val inBuf = dec.getInputBuffer(inIdx) ?: break
                    val size = ext.readSampleData(inBuf, 0)
                    if (size < 0) {
                        dec.queueInputBuffer(inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        isEos = true
                        break
                    } else {
                        val pts = ext.sampleTime
                        dec.queueInputBuffer(inIdx, 0, size, pts, 0)
                        ext.advance()
                    }
                }
            } finally {
                totalInputWaitNs += (System.nanoTime() - t0)
            }
        }

        init {
            try {
                // 1. Generate OES Texture
                val textures = IntArray(1)
                GLES20.glGenTextures(1, textures, 0)
                textureId = textures[0]
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

                surfaceTexture = SurfaceTexture(textureId)
                surface = Surface(surfaceTexture)
                Matrix.setIdentityM(stMatrix, 0)

                // 2. Setup Extractor & MediaCodec Decoder
                val ext = MediaExtractor()
                ext.setDataSource(filePath)
                extractor = ext

                var videoTrack = -1
                var videoFormat: MediaFormat? = null
                for (i in 0 until ext.trackCount) {
                    val format = ext.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/")) {
                        videoTrack = i
                        videoFormat = format
                        ext.selectTrack(i)
                        break
                    }
                }

                if (videoTrack != -1 && videoFormat != null) {
                    videoWidth = if (videoFormat.containsKey(MediaFormat.KEY_WIDTH)) videoFormat.getInteger(MediaFormat.KEY_WIDTH) else 1920
                    videoHeight = if (videoFormat.containsKey(MediaFormat.KEY_HEIGHT)) videoFormat.getInteger(MediaFormat.KEY_HEIGHT) else 1080
                    if (videoFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                        videoRotation = videoFormat.getInteger(MediaFormat.KEY_ROTATION)
                    }

                    val mime = videoFormat.getString(MediaFormat.KEY_MIME) ?: MediaFormat.MIMETYPE_VIDEO_AVC
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        videoFormat.setInteger(MediaFormat.KEY_PRIORITY, 0)
                        videoFormat.setFloat(MediaFormat.KEY_OPERATING_RATE, Float.MAX_VALUE)
                    }
                    val dec = MediaCodec.createDecoderByType(mime)
                    dec.configure(videoFormat, surface, null, 0)
                    dec.start()
                    decoder = dec
                    isInitialized = true
                    feedInputBuffers()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Hardware decoder initialization failed for $filePath: ${e.message}")
                release()
                isInitialized = false
            }
        }

        fun seekTo(timeUs: Long) {
            if (!isInitialized) return
            try {
                extractor?.seekTo(timeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                decoder?.flush()
                currentPtsUs = -1L
                isEos = false
                feedInputBuffers()
            } catch (e: Exception) {
                Log.w(TAG, "Hardware decoder seek error: ${e.message}")
            }
        }

        fun advanceTo(targetTimeUs: Long): Boolean {
            if (!isInitialized || decoder == null || extractor == null) return false
            if (currentPtsUs >= targetTimeUs && currentPtsUs != -1L) {
                return true
            }

            var loops = 0
            val maxLoops = 100

            while (loops++ < maxLoops) {
                // Keep decoder input buffers filled so decoding continues concurrently
                feedInputBuffers()

                // Dequeue decoded output buffer (short timeout 1000us)
                val tOut = System.nanoTime()
                val outIdx = decoder!!.dequeueOutputBuffer(bufferInfo, 1000L)
                totalOutputWaitNs += (System.nanoTime() - tOut)

                if (outIdx >= 0) {
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        decoder!!.releaseOutputBuffer(outIdx, false)
                        break
                    }
                    currentPtsUs = bufferInfo.presentationTimeUs
                    val shouldRender = currentPtsUs >= targetTimeUs

                    val tSurf = System.nanoTime()
                    decoder!!.releaseOutputBuffer(outIdx, shouldRender)
                    if (shouldRender) {
                        surfaceTexture?.updateTexImage()
                        surfaceTexture?.getTransformMatrix(stMatrix)
                        totalSurfaceWaitNs += (System.nanoTime() - tSurf)

                        // Immediately pipeline next frame decode into hardware while GPU renders
                        feedInputBuffers()
                        return true
                    }
                    totalSurfaceWaitNs += (System.nanoTime() - tSurf)
                } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (isEos) break
                }
            }
            return currentPtsUs != -1L
        }

        fun release() {
            try { decoder?.stop() } catch (e: Exception) {}
            try { decoder?.release() } catch (e: Exception) {}
            decoder = null
            try { extractor?.release() } catch (e: Exception) {}
            extractor = null
            try { surface?.release() } catch (e: Exception) {}
            surface = null
            try { surfaceTexture?.release() } catch (e: Exception) {}
            surfaceTexture = null
            if (textureId != 0) {
                val textures = intArrayOf(textureId)
                GLES20.glDeleteTextures(1, textures, 0)
                textureId = 0
            }
            isInitialized = false
        }
    }

    /**
     * Offscreen Framebuffer for hardware transition compositing
     */
    class Framebuffer(val width: Int, val height: Int) {
        var framebufferId = 0
            private set
        var textureId = 0
            private set

        init {
            val fbos = IntArray(1)
            GLES20.glGenFramebuffers(1, fbos, 0)
            framebufferId = fbos[0]

            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            textureId = textures[0]

            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA,
                width, height, 0,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null
            )
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebufferId)
            GLES20.glFramebufferTexture2D(
                GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D, textureId, 0
            )

            val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
            if (status != GLES20.GL_FRAMEBUFFER_COMPLETE) {
                Log.e(TAG, "FBO initialization incomplete: $status")
            }
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        }

        fun bind() {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebufferId)
            GLES20.glViewport(0, 0, width, height)
        }

        fun release() {
            if (framebufferId != 0) {
                GLES20.glDeleteFramebuffers(1, intArrayOf(framebufferId), 0)
                framebufferId = 0
            }
            if (textureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
                textureId = 0
            }
        }
    }

    /**
     * EGL InputSurface wrapper for MediaCodec encoder and OpenGL ES 2.0 rendering
     */
    private class CodecInputSurface(val surface: Surface, val width: Int, val height: Int) {
        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        // Shader programs
        private var oesProgram = 0
        private var oesPosLoc = 0
        private var oesTexCoordLoc = 0
        private var oesMVPLoc = 0
        private var oesSTLoc = 0

        private var tex2DProgram = 0
        private var tex2DPosLoc = 0
        private var tex2DTexCoordLoc = 0
        private var tex2DMVPLoc = 0
        private var tex2DSTLoc = 0

        private var solidProgram = 0
        private var solidPosLoc = 0
        private var solidMVPLoc = 0
        private var solidColorLoc = 0

        private var transProgram = 0
        private var transPosLoc = 0
        private var transTexCoordLoc = 0
        private var transOutTexLoc = 0
        private var transInTexLoc = 0
        private var transProgressLoc = 0
        private var transTypeLoc = 0

        val projMatrix = FloatArray(16)
        val identityMatrix = FloatArray(16)
        val tex2DSTMatrix = FloatArray(16)

        var totalGlDrawNs: Long = 0L
            private set

        val reusableModelMatrix = FloatArray(16)
        val reusableMvpMatrix = FloatArray(16)
        val reusableQuadBuffer: FloatBuffer
        val fullQuadBuffer: FloatBuffer

        // Quad for full screen FBO blitting
        private val fboQuadBuffer: FloatBuffer

        init {
            eglSetup()
            makeCurrent()
            glSetup()

            Matrix.orthoM(projMatrix, 0, 0f, width.toFloat(), height.toFloat(), 0f, -1f, 1f)
            Matrix.setIdentityM(identityMatrix, 0)
            Matrix.setIdentityM(tex2DSTMatrix, 0)
            Matrix.translateM(tex2DSTMatrix, 0, 0f, 1f, 0f)
            Matrix.scaleM(tex2DSTMatrix, 0, 1f, -1f, 1f)

            reusableQuadBuffer = ByteBuffer.allocateDirect(16 * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()

            val fullQuad = floatArrayOf(
                0f,              0f,               0.0f, 0.0f,
                0f,              height.toFloat(), 0.0f, 1.0f,
                width.toFloat(), 0f,               1.0f, 0.0f,
                width.toFloat(), height.toFloat(), 1.0f, 1.0f
            )
            fullQuadBuffer = ByteBuffer.allocateDirect(fullQuad.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(fullQuad)
            fullQuadBuffer.position(0)

            // FBO Quad: maps [-1, 1] NDC with UVs where top-left is (0, 1) and bottom-left is (0, 0)
            val fboQuad = floatArrayOf(
                -1.0f,  1.0f, 0.0f, 1.0f, // top-left
                -1.0f, -1.0f, 0.0f, 0.0f, // bottom-left
                 1.0f,  1.0f, 1.0f, 1.0f, // top-right
                 1.0f, -1.0f, 1.0f, 0.0f  // bottom-right
            )
            fboQuadBuffer = ByteBuffer.allocateDirect(fboQuad.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(fboQuad)
            fboQuadBuffer.position(0)
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
            // 1. OES Program
            val oesVS = """
                attribute vec4 aPosition;
                attribute vec2 aTextureCoord;
                uniform mat4 uMVPMatrix;
                uniform mat4 uSTMatrix;
                varying vec2 vTextureCoord;
                void main() {
                    gl_Position = uMVPMatrix * aPosition;
                    vTextureCoord = (uSTMatrix * vec4(aTextureCoord, 0.0, 1.0)).xy;
                }
            """.trimIndent()

            val oesFS = """
                #extension GL_OES_EGL_image_external : require
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform samplerExternalOES sTexture;
                void main() {
                    gl_FragColor = texture2D(sTexture, vTextureCoord);
                }
            """.trimIndent()

            oesProgram = createProgram(oesVS, oesFS)
            oesPosLoc = GLES20.glGetAttribLocation(oesProgram, "aPosition")
            oesTexCoordLoc = GLES20.glGetAttribLocation(oesProgram, "aTextureCoord")
            oesMVPLoc = GLES20.glGetUniformLocation(oesProgram, "uMVPMatrix")
            oesSTLoc = GLES20.glGetUniformLocation(oesProgram, "uSTMatrix")

            // 2. Texture2D Program
            val tex2DVS = """
                attribute vec4 aPosition;
                attribute vec2 aTextureCoord;
                uniform mat4 uMVPMatrix;
                uniform mat4 uSTMatrix;
                varying vec2 vTextureCoord;
                void main() {
                    gl_Position = uMVPMatrix * aPosition;
                    vTextureCoord = (uSTMatrix * vec4(aTextureCoord, 0.0, 1.0)).xy;
                }
            """.trimIndent()

            val tex2DFS = """
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform sampler2D sTexture;
                void main() {
                    gl_FragColor = texture2D(sTexture, vTextureCoord);
                }
            """.trimIndent()

            tex2DProgram = createProgram(tex2DVS, tex2DFS)
            tex2DPosLoc = GLES20.glGetAttribLocation(tex2DProgram, "aPosition")
            tex2DTexCoordLoc = GLES20.glGetAttribLocation(tex2DProgram, "aTextureCoord")
            tex2DMVPLoc = GLES20.glGetUniformLocation(tex2DProgram, "uMVPMatrix")
            tex2DSTLoc = GLES20.glGetUniformLocation(tex2DProgram, "uSTMatrix")

            // 3. Solid Color Program
            val solidVS = """
                attribute vec4 aPosition;
                uniform mat4 uMVPMatrix;
                void main() {
                    gl_Position = uMVPMatrix * aPosition;
                }
            """.trimIndent()

            val solidFS = """
                precision mediump float;
                uniform vec4 uColor;
                void main() {
                    gl_FragColor = uColor;
                }
            """.trimIndent()

            solidProgram = createProgram(solidVS, solidFS)
            solidPosLoc = GLES20.glGetAttribLocation(solidProgram, "aPosition")
            solidMVPLoc = GLES20.glGetUniformLocation(solidProgram, "uMVPMatrix")
            solidColorLoc = GLES20.glGetUniformLocation(solidProgram, "uColor")

            // 4. Transition Program
            val transVS = """
                attribute vec4 aPosition;
                attribute vec2 aTextureCoord;
                varying vec2 vTextureCoord;
                void main() {
                    gl_Position = aPosition;
                    vTextureCoord = aTextureCoord;
                }
            """.trimIndent()

            val transFS = """
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform sampler2D uOutgoingTex;
                uniform sampler2D uIncomingTex;
                uniform float uProgress;
                uniform int uType;

                void main() {
                    float p = clamp(uProgress, 0.0, 1.0);
                    vec4 cOut = texture2D(uOutgoingTex, vTextureCoord);
                    vec4 cIn = texture2D(uIncomingTex, vTextureCoord);

                    if (uType == 0) { // fade
                        gl_FragColor = mix(cOut, cIn, p);
                    } else if (uType == 1) { // dissolve
                        float s = p * p * (3.0 - 2.0 * p);
                        gl_FragColor = mix(cOut, cIn, s);
                    } else if (uType == 2) { // blackFade
                        if (p < 0.5) {
                            float a = clamp(1.0 - p * 2.0, 0.0, 1.0);
                            gl_FragColor = vec4(cOut.rgb * a, 1.0);
                        } else {
                            float a = clamp((p - 0.5) * 2.0, 0.0, 1.0);
                            gl_FragColor = vec4(cIn.rgb * a, 1.0);
                        }
                    } else if (uType == 3) { // whiteFade
                        if (p < 0.5) {
                            float t = clamp(p * 2.0, 0.0, 1.0);
                            gl_FragColor = vec4(mix(cOut.rgb, vec3(1.0), t), 1.0);
                        } else {
                            float t = clamp((p - 0.5) * 2.0, 0.0, 1.0);
                            gl_FragColor = vec4(mix(vec3(1.0), cIn.rgb, t), 1.0);
                        }
                    } else if (uType == 4) { // slideLeft
                        if (vTextureCoord.x < (1.0 - p)) {
                            gl_FragColor = texture2D(uOutgoingTex, vTextureCoord + vec2(p, 0.0));
                        } else {
                            gl_FragColor = texture2D(uIncomingTex, vTextureCoord - vec2(1.0 - p, 0.0));
                        }
                    } else if (uType == 5) { // slideRight
                        if (vTextureCoord.x > p) {
                            gl_FragColor = texture2D(uOutgoingTex, vTextureCoord - vec2(p, 0.0));
                        } else {
                            gl_FragColor = texture2D(uIncomingTex, vTextureCoord + vec2(1.0 - p, 0.0));
                        }
                    } else if (uType == 6) { // slideUp
                        if (vTextureCoord.y < (1.0 - p)) {
                            gl_FragColor = texture2D(uOutgoingTex, vTextureCoord + vec2(0.0, p));
                        } else {
                            gl_FragColor = texture2D(uIncomingTex, vTextureCoord - vec2(0.0, 1.0 - p));
                        }
                    } else if (uType == 7) { // slideDown
                        if (vTextureCoord.y > p) {
                            gl_FragColor = texture2D(uOutgoingTex, vTextureCoord - vec2(0.0, p));
                        } else {
                            gl_FragColor = texture2D(uIncomingTex, vTextureCoord + vec2(0.0, 1.0 - p));
                        }
                    } else if (uType == 8) { // wipeLeft
                        if (vTextureCoord.x < (1.0 - p)) {
                            gl_FragColor = cOut;
                        } else {
                            gl_FragColor = cIn;
                        }
                    } else if (uType == 9) { // wipeRight
                        if (vTextureCoord.x > p) {
                            gl_FragColor = cOut;
                        } else {
                            gl_FragColor = cIn;
                        }
                    } else if (uType == 10) { // zoomIn
                        vec2 centeredIn = (vTextureCoord - 0.5) / max(p, 0.001) + 0.5;
                        if (centeredIn.x >= 0.0 && centeredIn.x <= 1.0 && centeredIn.y >= 0.0 && centeredIn.y <= 1.0) {
                            vec4 inC = texture2D(uIncomingTex, centeredIn);
                            gl_FragColor = mix(cOut, inC, p);
                        } else {
                            gl_FragColor = cOut;
                        }
                    } else if (uType == 11) { // zoomOut
                        float s = max(1.0 - p, 0.001);
                        vec2 centeredOut = (vTextureCoord - 0.5) / s + 0.5;
                        if (centeredOut.x >= 0.0 && centeredOut.x <= 1.0 && centeredOut.y >= 0.0 && centeredOut.y <= 1.0) {
                            vec4 outC = texture2D(uOutgoingTex, centeredOut);
                            gl_FragColor = mix(cIn, outC, 1.0 - p);
                        } else {
                            gl_FragColor = cIn;
                        }
                    } else {
                        gl_FragColor = p < 0.5 ? cOut : cIn;
                    }
                }
            """.trimIndent()

            transProgram = createProgram(transVS, transFS)
            transPosLoc = GLES20.glGetAttribLocation(transProgram, "aPosition")
            transTexCoordLoc = GLES20.glGetAttribLocation(transProgram, "aTextureCoord")
            transOutTexLoc = GLES20.glGetUniformLocation(transProgram, "uOutgoingTex")
            transInTexLoc = GLES20.glGetUniformLocation(transProgram, "uIncomingTex")
            transProgressLoc = GLES20.glGetUniformLocation(transProgram, "uProgress")
            transTypeLoc = GLES20.glGetUniformLocation(transProgram, "uType")

            GLES20.glViewport(0, 0, width, height)
        }

        private fun createProgram(vShaderCode: String, fShaderCode: String): Int {
            val vShader = loadShader(GLES20.GL_VERTEX_SHADER, vShaderCode)
            val fShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fShaderCode)
            val prog = GLES20.glCreateProgram()
            GLES20.glAttachShader(prog, vShader)
            GLES20.glAttachShader(prog, fShader)
            GLES20.glLinkProgram(prog)
            return prog
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

        fun renderOESTexture(
            textureId: Int,
            mvpMatrix: FloatArray,
            stMatrix: FloatArray,
            quadBuffer: FloatBuffer
        ) {
            GLES20.glUseProgram(oesProgram)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

            GLES20.glUniformMatrix4fv(oesMVPLoc, 1, false, mvpMatrix, 0)
            GLES20.glUniformMatrix4fv(oesSTLoc, 1, false, stMatrix, 0)

            quadBuffer.position(0)
            GLES20.glVertexAttribPointer(oesPosLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, quadBuffer)
            GLES20.glEnableVertexAttribArray(oesPosLoc)

            quadBuffer.position(2)
            GLES20.glVertexAttribPointer(oesTexCoordLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, quadBuffer)
            GLES20.glEnableVertexAttribArray(oesTexCoordLoc)

            val tDraw = System.nanoTime()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            totalGlDrawNs += (System.nanoTime() - tDraw)
        }

        fun render2DTexture(
            textureId: Int,
            mvpMatrix: FloatArray,
            quadBuffer: FloatBuffer
        ) {
            GLES20.glUseProgram(tex2DProgram)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)

            GLES20.glUniformMatrix4fv(tex2DMVPLoc, 1, false, mvpMatrix, 0)
            GLES20.glUniformMatrix4fv(tex2DSTLoc, 1, false, tex2DSTMatrix, 0)

            quadBuffer.position(0)
            GLES20.glVertexAttribPointer(tex2DPosLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, quadBuffer)
            GLES20.glEnableVertexAttribArray(tex2DPosLoc)

            quadBuffer.position(2)
            GLES20.glVertexAttribPointer(tex2DTexCoordLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, quadBuffer)
            GLES20.glEnableVertexAttribArray(tex2DTexCoordLoc)

            val tDraw = System.nanoTime()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            totalGlDrawNs += (System.nanoTime() - tDraw)
        }

        fun renderSolidColor(
            color: Int,
            mvpMatrix: FloatArray,
            quadBuffer: FloatBuffer
        ) {
            GLES20.glUseProgram(solidProgram)
            val r = ((color shr 16) and 0xFF) / 255.0f
            val g = ((color shr 8) and 0xFF) / 255.0f
            val b = (color and 0xFF) / 255.0f
            val a = ((color shr 24) and 0xFF) / 255.0f
            GLES20.glUniform4f(solidColorLoc, r, g, b, if (a > 0f) a else 1f)
            GLES20.glUniformMatrix4fv(solidMVPLoc, 1, false, mvpMatrix, 0)

            quadBuffer.position(0)
            GLES20.glVertexAttribPointer(solidPosLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, quadBuffer)
            GLES20.glEnableVertexAttribArray(solidPosLoc)

            val tDraw = System.nanoTime()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            totalGlDrawNs += (System.nanoTime() - tDraw)
        }

        fun renderTransition(
            outgoingTexId: Int,
            incomingTexId: Int,
            typeIndex: Int,
            progress: Float
        ) {
            GLES20.glUseProgram(transProgram)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, outgoingTexId)
            GLES20.glUniform1i(transOutTexLoc, 0)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, incomingTexId)
            GLES20.glUniform1i(transInTexLoc, 1)

            GLES20.glUniform1f(transProgressLoc, progress)
            GLES20.glUniform1i(transTypeLoc, typeIndex)

            fboQuadBuffer.position(0)
            GLES20.glVertexAttribPointer(transPosLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, fboQuadBuffer)
            GLES20.glEnableVertexAttribArray(transPosLoc)

            fboQuadBuffer.position(2)
            GLES20.glVertexAttribPointer(transTexCoordLoc, 2, GLES20.GL_FLOAT, false, 4 * 4, fboQuadBuffer)
            GLES20.glEnableVertexAttribArray(transTexCoordLoc)

            val tDraw = System.nanoTime()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            totalGlDrawNs += (System.nanoTime() - tDraw)
        }

        fun setPresentationTime(nsecs: Long) {
            EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, nsecs)
        }

        fun swapBuffers(): Boolean {
            return EGL14.eglSwapBuffers(eglDisplay, eglSurface)
        }

        fun release() {
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                try {
                    if (oesProgram != 0) GLES20.glDeleteProgram(oesProgram)
                    if (tex2DProgram != 0) GLES20.glDeleteProgram(tex2DProgram)
                    if (solidProgram != 0) GLES20.glDeleteProgram(solidProgram)
                    if (transProgram != 0) GLES20.glDeleteProgram(transProgram)
                } catch (e: Exception) {
                    Log.w(TAG, "Error deleting GL programs: ${e.message}")
                }
                EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                if (eglSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, eglSurface)
                }
                if (eglContext != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglDestroyContext(eglDisplay, eglContext)
                }
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(eglDisplay)
            }
            try { surface.release() } catch (e: Exception) {}
            eglDisplay = EGL14.EGL_NO_DISPLAY
            eglContext = EGL14.EGL_NO_CONTEXT
            eglSurface = EGL14.EGL_NO_SURFACE
            oesProgram = 0
            tex2DProgram = 0
            solidProgram = 0
            transProgram = 0
        }
    }

    /**
     * Dedicated asynchronous background drain thread for MediaCodec video encoder and MediaMuxer.
     * Pipelines frame encoding and container muxing concurrently with OpenGL rendering and decoding.
     */
    private class EncoderDrainThread(
        private val encoder: MediaCodec,
        private val muxer: MediaMuxer,
        private val audioFormat: MediaFormat?
    ) : Thread("EncoderDrainThread") {
        @Volatile var isRunning = true
        @Volatile var error: Throwable? = null
        val muxerStartedLatch = CountDownLatch(1)
        @Volatile var muxerStarted = false
        var videoTrackIndex = -1
        var audioTrackIndex = -1

        var drainWaitNs = 0L
        var muxWriteNs = 0L
        var totalDrainNs = 0L

        override fun run() {
            val t0 = System.nanoTime()
            val bufferInfo = MediaCodec.BufferInfo()
            try {
                while (isRunning) {
                    val waitStart = System.nanoTime()
                    val encoderStatus = encoder.dequeueOutputBuffer(bufferInfo, 10_000L) // 10ms poll
                    drainWaitNs += (System.nanoTime() - waitStart)

                    if (encoderStatus == MediaCodec.INFO_TRY_AGAIN_LATER) {
                        if (!isRunning) break
                        continue
                    } else if (encoderStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) {
                            throw RuntimeException("Video encoder format changed twice")
                        }
                        val newFormat = encoder.outputFormat
                        videoTrackIndex = muxer.addTrack(newFormat)
                        if (audioFormat != null) {
                            audioTrackIndex = muxer.addTrack(audioFormat)
                        }
                        muxer.start()
                        muxerStarted = true
                        muxerStartedLatch.countDown()
                    } else if (encoderStatus >= 0) {
                        val writeStart = System.nanoTime()
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
                        muxWriteNs += (System.nanoTime() - writeStart)

                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "EncoderDrainThread error: ${t.message}", t)
                error = t
                muxerStartedLatch.countDown()
            } finally {
                totalDrainNs = System.nanoTime() - t0
            }
        }
    }

    /**
     * Executes the full video export pipeline with hardware-accelerated decoding,
     * GPU transform matrix compositing, 12 GPU transition shaders, and gallery registration.
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

        val startTimeNs = System.nanoTime()

        // Align dimensions to multiples of 2 for video encoder compatibility (YUV 4:2:0 subsampling)
        val width = (targetWidth / 2) * 2
        val height = (targetHeight / 2) * 2
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
            totalDurationMs = 1000L
        }

        val totalFrames = ((totalDurationMs / 1000.0) * fps).toInt().coerceAtLeast(1)
        Log.i(TAG, "Hardware Export starting: ${width}x${height} @ ${fps}fps, totalDuration=${totalDurationMs}ms, frames=$totalFrames")

        // Prepare temporary output file
        val tempDir = File(context.cacheDir, "export_tmp").apply { if (!exists()) mkdirs() }
        val tempOutputFile = File(tempDir, "export_${System.currentTimeMillis()}.mp4")
        if (tempOutputFile.exists()) tempOutputFile.delete()

        // Configure MediaCodec Encoder
        val videoFormat = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, IFRAME_INTERVAL)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setFloat(MediaFormat.KEY_OPERATING_RATE, Float.MAX_VALUE)
            }
        }

        val encoder = MediaCodec.createEncoderByType(MIME_TYPE)
        encoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurfaceRaw = encoder.createInputSurface()
        val inputSurface = CodecInputSurface(inputSurfaceRaw, width, height)
        encoder.start()

        val muxer = MediaMuxer(tempOutputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        // Check for audio track source
        var audioExtractor: MediaExtractor? = null
        var audioFormat: MediaFormat? = null

        val primaryAudioTrack = audioTracks.firstOrNull { it.path.isNotBlank() && File(it.path).exists() }
        val primaryAudioSource = primaryAudioTrack?.path
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
                } else if (primaryAudioTrack != null && primaryAudioTrack.trimStartMs > 0L) {
                    audioExtractor?.seekTo(primaryAudioTrack.trimStartMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Audio track setup skipped: ${e.message}")
            }
        }

        val drainThread = EncoderDrainThread(encoder, muxer, audioFormat)
        drainThread.start()

        // Texture caches
        val photoTextures = mutableMapOf<String, Int>()
        val photoBitmaps = mutableMapOf<String, Bitmap>()
        val photoDimensions = mutableMapOf<String, Pair<Int, Int>>()
        val videoDecoders = mutableMapOf<String, HardwareVideoDecoder>()

        var decoderInitNs = 0L
        var totalDecodeNs = 0L
        var totalProcessNs = 0L
        var totalRenderNs = 0L
        var totalInputNs = 0L
        var totalDrainNs = 0L
        var audioRemuxNs = 0L
        var muxFinalizeNs = 0L

        val initStart = System.nanoTime()
        // Preload photo textures and pre-warm video decoders
        for (clip in clips) {
            val p = clip.path
            if (!p.isNullOrBlank() && File(p).exists()) {
                if (clip.isPhoto || p.endsWith(".jpg", true) || p.endsWith(".png", true) || p.endsWith(".jpeg", true)) {
                    if (!photoTextures.containsKey(p)) {
                        try {
                            val bmp = BitmapFactory.decodeFile(p)
                            if (bmp != null) {
                                val tex = IntArray(1)
                                GLES20.glGenTextures(1, tex, 0)
                                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
                                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                                GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
                                photoTextures[p] = tex[0]
                                photoDimensions[p] = Pair(bmp.width, bmp.height)
                                photoBitmaps[p] = bmp
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed caching photo at $p: ${e.message}")
                        }
                    }
                } else {
                    if (!videoDecoders.containsKey(p)) {
                        try {
                            val dec = HardwareVideoDecoder(p)
                            if (dec.isInitialized) {
                                videoDecoders[p] = dec
                            } else {
                                dec.release()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed initializing decoder for $p: ${e.message}")
                        }
                    }
                }
            }
        }
        decoderInitNs = System.nanoTime() - initStart

        // Framebuffers for transition compositing (only allocated if transitions exist)
        val hasTransitions = transitions.any { it.enabled && it.durationMs > 0 && it.type != "none" }
        val fboA = if (hasTransitions) Framebuffer(width, height) else null
        val fboB = if (hasTransitions) Framebuffer(width, height) else null

        var totalEglSwapNs = 0L
        var totalDrainJoinNs = 0L
        var totalDecoderInputWaitNs = 0L
        var totalDecoderOutputWaitNs = 0L
        var totalSurfaceTextureWaitNs = 0L
        var totalGlDrawNs = 0L
        var totalEncoderDrainWaitNs = 0L
        var totalMuxWriteNs = 0L

        // Helper to get or create a hardware video decoder for a clip
        fun getDecoderForClip(clip: ExportClip): HardwareVideoDecoder? {
            val path = clip.path ?: return null
            if (photoTextures.containsKey(path) || clip.isPhoto) return null
            if (!File(path).exists()) return null

            var dec = videoDecoders[path]
            if (dec == null) {
                dec = HardwareVideoDecoder(path)
                if (dec.isInitialized) {
                    videoDecoders[path] = dec
                } else {
                    dec.release()
                    return null
                }
            }
            return dec
        }

        // Helper to render a clip onto whichever framebuffer is currently bound
        fun renderClip(clip: ExportClip, localTimeMs: Long) {
            val processStart = System.nanoTime()
            val path = clip.path
            val decoder = if (!clip.isPhoto && path != null) getDecoderForClip(clip) else null

            // 1. Calculate transform matrices (reusable)
            val centerX = width / 2f
            val centerY = height / 2f
            val kCanvas = width.toFloat() / 360f
            val xExport = clip.safeXPos.toFloat() * kCanvas
            val yExport = clip.safeYPos.toFloat() * kCanvas
            val s = clip.safeScale.toFloat()
            val scaleX = (if (clip.flipHorizontal) -1f else 1f) * s
            val scaleY = (if (clip.flipVertical) -1f else 1f) * s
            val continuousDeg = (clip.safeRotationAngle.toFloat() * 180f / Math.PI.toFloat())
            val totalRotationDeg = clip.rotationDegrees.toFloat() + continuousDeg

            val modelMatrix = inputSurface.reusableModelMatrix
            Matrix.setIdentityM(modelMatrix, 0)
            Matrix.translateM(modelMatrix, 0, centerX + xExport, centerY + yExport, 0f)
            Matrix.rotateM(modelMatrix, 0, totalRotationDeg, 0f, 0f, 1f)
            Matrix.scaleM(modelMatrix, 0, scaleX, scaleY, 1f)
            Matrix.translateM(modelMatrix, 0, -centerX, -centerY, 0f)

            val mvpMatrix = inputSurface.reusableMvpMatrix
            Matrix.multiplyMM(mvpMatrix, 0, inputSurface.projMatrix, 0, modelMatrix, 0)

            // Determine dimensions and aspect ratio
            var contentW = width
            var contentH = height
            var isVideo = false
            var isPhoto = false

            var decodeDurationNs = 0L
            if (decoder != null && decoder.isInitialized) {
                isVideo = true
                val t0 = System.nanoTime()
                decoder.advanceTo(localTimeMs * 1000L)
                decodeDurationNs = System.nanoTime() - t0
                totalDecodeNs += decodeDurationNs

                val rot = decoder.videoRotation
                if (rot == 90 || rot == 270) {
                    contentW = decoder.videoHeight
                    contentH = decoder.videoWidth
                } else {
                    contentW = decoder.videoWidth
                    contentH = decoder.videoHeight
                }
            } else if (path != null && photoTextures.containsKey(path)) {
                isPhoto = true
                val dim = photoDimensions[path] ?: Pair(width, height)
                contentW = dim.first
                contentH = dim.second
            }

            // Calculate dstRect aspect fit
            val frameRatio = contentW.toFloat() / contentH.toFloat()
            val targetRatio = width.toFloat() / height.toFloat()
            val dstLeft: Float
            val dstTop: Float
            val dstRight: Float
            val dstBottom: Float

            if (frameRatio > targetRatio) {
                val drawH = width / frameRatio
                val top = (height - drawH) / 2f
                dstLeft = 0f
                dstTop = top
                dstRight = width.toFloat()
                dstBottom = top + drawH
            } else {
                val drawW = height * frameRatio
                val left = (width - drawW) / 2f
                dstLeft = left
                dstTop = 0f
                dstRight = left + drawW
                dstBottom = height.toFloat()
            }

            // Populate reusable quad buffer for dstRect (OpenGL standard: V=1.0 at dstTop, V=0.0 at dstBottom)
            inputSurface.reusableQuadBuffer.clear()
            inputSurface.reusableQuadBuffer.put(dstLeft).put(dstTop).put(0.0f).put(1.0f)
            inputSurface.reusableQuadBuffer.put(dstLeft).put(dstBottom).put(0.0f).put(0.0f)
            inputSurface.reusableQuadBuffer.put(dstRight).put(dstTop).put(1.0f).put(1.0f)
            inputSurface.reusableQuadBuffer.put(dstRight).put(dstBottom).put(1.0f).put(0.0f)
            inputSurface.reusableQuadBuffer.position(0)

            val processEnd = System.nanoTime()
            totalProcessNs += (processEnd - processStart - decodeDurationNs)

            val renderStart = System.nanoTime()
            if (isVideo && decoder != null) {
                inputSurface.renderOESTexture(decoder.textureId, mvpMatrix, decoder.stMatrix, inputSurface.reusableQuadBuffer)
            } else if (isPhoto && path != null && photoTextures.containsKey(path)) {
                val tex = photoTextures[path] ?: 0
                inputSurface.render2DTexture(tex, mvpMatrix, inputSurface.reusableQuadBuffer)
            } else {
                inputSurface.renderSolidColor(clip.color, mvpMatrix, inputSurface.fullQuadBuffer)
            }
            totalRenderNs += (System.nanoTime() - renderStart)
        }

        fun transitionTypeToIndex(type: String): Int {
            return when (type) {
                "fade" -> 0
                "dissolve" -> 1
                "blackFade" -> 2
                "whiteFade" -> 3
                "slideLeft" -> 4
                "slideRight" -> 5
                "slideUp" -> 6
                "slideDown" -> 7
                "wipeLeft" -> 8
                "wipeRight" -> 9
                "zoomIn" -> 10
                "zoomOut" -> 11
                else -> 0
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

                if (hasTransitions) {
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
                }

                // 2. Render Frame (Hardware Compositing)
                if (activeTransition != null && leftClipIndex != -1 && rightClipIndex != -1 && fboA != null && fboB != null) {
                    val leftClip = clips[leftClipIndex]
                    val rightClip = clips[rightClipIndex]

                    val leftLocalMs = ((currentTimeMs - clipStartTimes[leftClipIndex]) * leftClip.speed + leftClip.trimStartMs).toLong()
                    val rightLocalMs = ((currentTimeMs - clipStartTimes[rightClipIndex]) * rightClip.speed + rightClip.trimStartMs).toLong().coerceAtLeast(rightClip.trimStartMs)

                    // Render Outgoing to FBO A
                    fboA.bind()
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                    renderClip(leftClip, leftLocalMs)

                    // Render Incoming to FBO B
                    fboB.bind()
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                    renderClip(rightClip, rightLocalMs)

                    // Composite via Transition Shader to Encoder Surface
                    GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
                    GLES20.glViewport(0, 0, width, height)
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                    val typeIdx = transitionTypeToIndex(activeTransition.type)
                    val transStart = System.nanoTime()
                    inputSurface.renderTransition(fboA.textureId, fboB.textureId, typeIdx, transitionProgress.toFloat())
                    totalRenderNs += (System.nanoTime() - transStart)
                } else {
                    // Single Clip Frame - Direct Render to Encoder Surface (Zero FBO overhead)
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

                    GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
                    GLES20.glViewport(0, 0, width, height)
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                    renderClip(clip, localMs)
                }

                // 3. Submit Frame to MediaCodec
                drainThread.error?.let { throw RuntimeException("Encoder drain failed: ${it.message}", it) }
                val inputStart = System.nanoTime()
                val ptsNs = (frameIndex * 1_000_000_000L) / fps
                inputSurface.setPresentationTime(ptsNs)
                inputSurface.swapBuffers()
                val swapElapsed = System.nanoTime() - inputStart
                totalInputNs += swapElapsed
                totalEglSwapNs += swapElapsed

                // Report progress
                if (frameIndex % max(1, totalFrames / 20) == 0 || frameIndex == totalFrames - 1) {
                    val p = (frameIndex.toDouble() / totalFrames) * 0.90
                    progressCallback?.onProgress(p)
                }
            }

            // Signal End of Video Stream and wait for background drain thread to finish
            val drainJoinStart = System.nanoTime()
            encoder.signalEndOfInputStream()
            drainThread.join(30_000L)
            if (drainThread.isAlive) {
                drainThread.isRunning = false
                drainThread.join(1000L)
                throw RuntimeException("Encoder drain timed out after 30 seconds")
            }
            drainThread.error?.let { throw RuntimeException("Encoder drain failed: ${it.message}", it) }
            totalDrainJoinNs = System.nanoTime() - drainJoinStart

            // 4. Remux Audio Track if available
            if (audioExtractor != null && drainThread.audioTrackIndex != -1 && drainThread.muxerStarted) {
                val audioStart = System.nanoTime()
                try {
                    val maxBufferSize = if (audioFormat?.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE) == true) {
                        audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                    } else {
                        256 * 1024
                    }
                    val audioBuffer = ByteBuffer.allocateDirect(maxBufferSize)
                    val audioBufferInfo = MediaCodec.BufferInfo()

                    while (true) {
                        audioBufferInfo.offset = 0
                        audioBufferInfo.size = audioExtractor.readSampleData(audioBuffer, 0)
                        if (audioBufferInfo.size < 0) {
                            break
                        }
                        audioBufferInfo.presentationTimeUs = audioExtractor.sampleTime
                        if (audioBufferInfo.presentationTimeUs > totalDurationMs * 1000L) {
                            break
                        }
                        audioBufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(drainThread.audioTrackIndex, audioBuffer, audioBufferInfo)
                        audioExtractor.advance()
                    }
                } catch (audioEx: Exception) {
                    Log.w(TAG, "Audio sample remuxing error: ${audioEx.message}")
                }
                audioRemuxNs = System.nanoTime() - audioStart
            }

            // 5. Finalize Muxer
            val muxStart = System.nanoTime()
            try {
                if (drainThread.muxerStarted) {
                    muxer.stop()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Muxer stop exception: ${e.message}")
            }
            muxFinalizeNs = System.nanoTime() - muxStart

            progressCallback?.onProgress(0.95)

            val elapsedSec = (System.nanoTime() - startTimeNs) / 1_000_000_000.0
            val effectiveFps = totalFrames / elapsedSec
            val realtimeFactor = (totalDurationMs / 1000.0) / elapsedSec
            val wallClockMs = elapsedSec * 1000.0

            totalDecoderInputWaitNs = 0L
            totalDecoderOutputWaitNs = 0L
            totalSurfaceTextureWaitNs = 0L
            for (dec in videoDecoders.values) {
                totalDecoderInputWaitNs += dec.totalInputWaitNs
                totalDecoderOutputWaitNs += dec.totalOutputWaitNs
                totalSurfaceTextureWaitNs += dec.totalSurfaceWaitNs
            }
            totalGlDrawNs = inputSurface.totalGlDrawNs
            totalEncoderDrainWaitNs = drainThread.drainWaitNs
            totalMuxWriteNs = drainThread.muxWriteNs
            val totalDrainNs = drainThread.totalDrainNs

            val decInitMs = decoderInitNs / 1_000_000.0
            val decodeMs = totalDecodeNs / 1_000_000.0
            val processMs = totalProcessNs / 1_000_000.0
            val renderMs = totalRenderNs / 1_000_000.0
            val inputMs = totalInputNs / 1_000_000.0
            val drainMs = totalDrainNs / 1_000_000.0
            val drainJoinMs = totalDrainJoinNs / 1_000_000.0
            val audioMs = audioRemuxNs / 1_000_000.0
            val muxMs = muxFinalizeNs / 1_000_000.0

            val decInMs = totalDecoderInputWaitNs / 1_000_000.0
            val decOutMs = totalDecoderOutputWaitNs / 1_000_000.0
            val surfWaitMs = totalSurfaceTextureWaitNs / 1_000_000.0
            val glDrawMs = totalGlDrawNs / 1_000_000.0
            val eglSwapMs = totalEglSwapNs / 1_000_000.0
            val encWaitMs = totalEncoderDrainWaitNs / 1_000_000.0
            val muxWriteMs = totalMuxWriteNs / 1_000_000.0

            Log.i(
                TAG,
                """
================ EXPORT PIPELINE PERFORMANCE PROFILE ================
Output: ${width}x${height} @ ${fps}fps ($bitrate bps)
Total Frames: $totalFrames | Total Duration: ${totalDurationMs}ms
Wall Clock Time: %.3fs | Effective FPS: %.2f (%.2fx realtime)
---------------------------------------------------------------------
PRIMARY STAGE BREAKDOWN:
1. DECODER_INIT  : %8.2f ms (%5.1f%%)
2. FRAME_DECODE  : %8.2f ms (%5.1f%%) | avg: %6.2f ms/frame
3. FRAME_PROCESS : %8.2f ms (%5.1f%%) | avg: %6.2f ms/frame
4. GPU_RENDER    : %8.2f ms (%5.1f%%) | avg: %6.2f ms/frame
5. ENCODER_INPUT : %8.2f ms (%5.1f%%) | avg: %6.2f ms/frame
6. ENCODER_DRAIN : %8.2f ms (%5.1f%%) | avg: %6.2f ms/frame (async overlapped; join wait: %.2f ms)
7. AUDIO_REMUX   : %8.2f ms (%5.1f%%)
8. MUX_FINALIZE  : %8.2f ms (%5.1f%%)
---------------------------------------------------------------------
SUB-STAGE FINE-GRAINED BREAKDOWN:
- DECODER_INPUT_FEED  : %8.2f ms | avg: %6.2f ms/frame
- DECODER_OUTPUT_WAIT : %8.2f ms | avg: %6.2f ms/frame
- SURFACE_TEXTURE_WAIT: %8.2f ms | avg: %6.2f ms/frame
- GL_DRAW             : %8.2f ms | avg: %6.2f ms/frame
- EGL_SWAP            : %8.2f ms | avg: %6.2f ms/frame
- ENCODER_DRAIN_WAIT  : %8.2f ms | avg: %6.2f ms/frame
- MUX_WRITE           : %8.2f ms | avg: %6.2f ms/frame
=====================================================================
""".trimIndent().format(
                    elapsedSec, effectiveFps, realtimeFactor,
                    decInitMs, (decInitMs / wallClockMs) * 100.0,
                    decodeMs, (decodeMs / wallClockMs) * 100.0, decodeMs / totalFrames,
                    processMs, (processMs / wallClockMs) * 100.0, processMs / totalFrames,
                    renderMs, (renderMs / wallClockMs) * 100.0, renderMs / totalFrames,
                    inputMs, (inputMs / wallClockMs) * 100.0, inputMs / totalFrames,
                    drainMs, (drainMs / wallClockMs) * 100.0, drainMs / totalFrames, drainJoinMs,
                    audioMs, (audioMs / wallClockMs) * 100.0,
                    muxMs, (muxMs / wallClockMs) * 100.0,
                    decInMs, decInMs / totalFrames,
                    decOutMs, decOutMs / totalFrames,
                    surfWaitMs, surfWaitMs / totalFrames,
                    glDrawMs, glDrawMs / totalFrames,
                    eglSwapMs, eglSwapMs / totalFrames,
                    encWaitMs, encWaitMs / totalFrames,
                    muxWriteMs, muxWriteMs / totalFrames
                )
            )

        } finally {
            // Clean up encoder and surfaces
            try {
                drainThread.isRunning = false
                if (drainThread.isAlive) {
                    drainThread.join(1000L)
                }
            } catch (e: Exception) {}
            try {
                if (drainThread.muxerStarted) {
                    muxer.stop()
                }
            } catch (e: Exception) {}
            try { muxer.release() } catch (e: Exception) {}
            try { encoder.stop() } catch (e: Exception) {}
            try { encoder.release() } catch (e: Exception) {}

            // Clean up OpenGL FBOs, textures, and decoder surfaces while EGL context is still current
            try { fboA?.release() } catch (e: Exception) {}
            try { fboB?.release() } catch (e: Exception) {}
            try {
                photoTextures.values.forEach { tex ->
                    val textures = intArrayOf(tex)
                    GLES20.glDeleteTextures(1, textures, 0)
                }
                photoTextures.clear()
            } catch (e: Exception) {}
            videoDecoders.values.forEach { it.release() }
            videoDecoders.clear()

            // Now release EGL and input surface
            try { inputSurface.release() } catch (e: Exception) {}
            try { audioExtractor?.release() } catch (e: Exception) {}
            photoBitmaps.values.forEach { try { it.recycle() } catch (e: Exception) {} }
            photoBitmaps.clear()
        }

        if (!tempOutputFile.exists() || tempOutputFile.length() == 0L) {
            throw RuntimeException("Export failed: Output file was empty or not generated.")
        }

        // 6. Register video into MediaStore Gallery
        val galleryResult = registerToMediaStore(tempOutputFile, customOutputName)
        progressCallback?.onProgress(1.0)

        val finalElapsedSec = (System.nanoTime() - startTimeNs) / 1_000_000_000.0
        val finalEffectiveFps = totalFrames / finalElapsedSec
        val finalRealtimeFactor = (totalDurationMs / 1000.0) / finalElapsedSec

        return mapOf(
            "success" to true,
            "path" to tempOutputFile.absolutePath,
            "uri" to (galleryResult["uri"] ?: ""),
            "displayName" to (galleryResult["displayName"] ?: tempOutputFile.name),
            "sizeBytes" to tempOutputFile.length(),
            "durationMs" to totalDurationMs,
            "width" to width,
            "height" to height,
            "fps" to fps,
            "bitrate" to bitrate,
            "codec" to "H.264 / AVC",
            "exportMetrics" to mapOf(
                "wallClockSec" to finalElapsedSec,
                "effectiveFps" to finalEffectiveFps,
                "realtimeFactor" to finalRealtimeFactor,
                "decoderInitMs" to decoderInitNs / 1_000_000.0,
                "frameDecodeMs" to totalDecodeNs / 1_000_000.0,
                "frameProcessMs" to totalProcessNs / 1_000_000.0,
                "gpuRenderMs" to totalRenderNs / 1_000_000.0,
                "encoderInputMs" to totalInputNs / 1_000_000.0,
                "encoderDrainMs" to drainThread.totalDrainNs / 1_000_000.0,
                "encoderDrainJoinMs" to totalDrainJoinNs / 1_000_000.0,
                "audioRemuxMs" to audioRemuxNs / 1_000_000.0,
                "muxFinalizeMs" to muxFinalizeNs / 1_000_000.0,
                "decoderInputWaitMs" to totalDecoderInputWaitNs / 1_000_000.0,
                "decoderOutputWaitMs" to totalDecoderOutputWaitNs / 1_000_000.0,
                "surfaceTextureWaitMs" to totalSurfaceTextureWaitNs / 1_000_000.0,
                "glDrawMs" to totalGlDrawNs / 1_000_000.0,
                "eglSwapMs" to totalEglSwapNs / 1_000_000.0,
                "encoderDrainWaitMs" to totalEncoderDrainWaitNs / 1_000_000.0,
                "muxWriteMs" to totalMuxWriteNs / 1_000_000.0
            )
        )
    }

    private fun registerToMediaStore(sourceFile: File, customName: String?): Map<String, String> {
        val displayName = if (!customName.isNullOrBlank()) {
            if (customName.endsWith(".mp4")) customName else "$customName.mp4"
        } else {
            "EDITOR_FS_${System.currentTimeMillis()}.mp4"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.TITLE, displayName.removeSuffix(".mp4"))
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/EditorFS")
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
            val targetDir = File(moviesDir, "EditorFS").apply { if (!exists()) mkdirs() }
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
