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
 * Deterministic Keyframe Animation Evaluation Engine for Native Android Export.
 * Matches Flutter domain KeyframeTrackGroup and EasingCurve with 100% mathematical parity.
 */
data class ExportMotionKeyframe(
    val id: String,
    val timestampMs: Long,
    val value: Double,
    val mode: String = "easeInOut",
    val x1: Double = 0.42,
    val y1: Double = 0.0,
    val x2: Double = 0.58,
    val y2: Double = 1.0
)

data class ExportKeyframeTrack(
    val property: String,
    val defaultValue: Double,
    val keyframes: List<ExportMotionKeyframe>
) {
    fun evaluate(timeInSeconds: Double): Double {
        if (keyframes.isEmpty()) return defaultValue
        if (keyframes.size == 1) return keyframes[0].value
        val timeMs = (timeInSeconds * 1000.0).toLong()
        if (timeMs <= keyframes.first().timestampMs) return keyframes.first().value
        if (timeMs >= keyframes.last().timestampMs) return keyframes.last().value

        // Binary search for bounding interval [k_i, k_{i+1}]
        var low = 0
        var high = keyframes.size - 1
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (keyframes[mid].timestampMs <= timeMs) {
                if (mid == keyframes.size - 1 || keyframes[mid + 1].timestampMs > timeMs) {
                    val k1 = keyframes[mid]
                    val k2 = keyframes[mid + 1]
                    val durationMs = k2.timestampMs - k1.timestampMs
                    if (durationMs <= 0L) return k1.value
                    val progress = (timeMs - k1.timestampMs).toDouble() / durationMs.toDouble()
                    val easedProgress = evaluateEasing(k1, progress.coerceIn(0.0, 1.0))
                    return k1.value + (k2.value - k1.value) * easedProgress
                }
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return keyframes.last().value
    }

    private fun evaluateEasing(kf: ExportMotionKeyframe, t: Double): Double {
        return when (kf.mode) {
            "hold" -> if (t >= 1.0) 1.0 else 0.0
            "linear" -> t
            "easeIn" -> t * t * t
            "easeOut" -> 1.0 - Math.pow(1.0 - t, 3.0)
            "easeInOut" -> if (t < 0.5) 4.0 * t * t * t else 1.0 - Math.pow(-2.0 * t + 2.0, 3.0) / 2.0
            "cubicBezier" -> evaluateCubicBezier(kf.x1, kf.y1, kf.x2, kf.y2, t)
            else -> if (t < 0.5) 4.0 * t * t * t else 1.0 - Math.pow(-2.0 * t + 2.0, 3.0) / 2.0
        }
    }

    private fun evaluateCubicBezier(x1: Double, y1: Double, x2: Double, y2: Double, t: Double): Double {
        if (t <= 0.0) return 0.0
        if (t >= 1.0) return 1.0
        var s = t
        for (i in 0 until 8) {
            val currentX = sampleCurveX(x1, x2, s) - t
            if (Math.abs(currentX) < 1e-5) break
            val dx = sampleCurveDerivativeX(x1, x2, s)
            if (Math.abs(dx) < 1e-5) break
            s -= currentX / dx
        }
        s = s.coerceIn(0.0, 1.0)
        return sampleCurveY(y1, y2, s).coerceIn(0.0, 1.0)
    }

    private fun sampleCurveX(x1: Double, x2: Double, t: Double): Double =
        3.0 * (1.0 - t) * (1.0 - t) * t * x1 + 3.0 * (1.0 - t) * t * t * x2 + t * t * t

    private fun sampleCurveDerivativeX(x1: Double, x2: Double, t: Double): Double =
        3.0 * (1.0 - t) * (1.0 - t) * x1 + 6.0 * (1.0 - t) * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2)

    private fun sampleCurveY(y1: Double, y2: Double, t: Double): Double =
        3.0 * (1.0 - t) * (1.0 - t) * t * y1 + 3.0 * (1.0 - t) * t * t * y2 + t * t * t
}

data class ExportKeyframeTrackGroup(
    val tracks: Map<String, ExportKeyframeTrack> = emptyMap()
) {
    fun hasProperty(prop: String): Boolean = tracks[prop]?.keyframes?.isNotEmpty() == true

    fun evaluate(prop: String, timeInSeconds: Double, fallback: Double): Double {
        val track = tracks[prop] ?: return fallback
        if (track.keyframes.isEmpty()) return fallback
        return track.evaluate(timeInSeconds)
    }
}

object KeyframeParser {
    @Suppress("UNCHECKED_CAST")
    fun parseTrackGroup(map: Map<String, Any>?): ExportKeyframeTrackGroup {
        if (map == null) return ExportKeyframeTrackGroup()
        val rawTracks = map["tracks"] as? Map<String, Any> ?: return ExportKeyframeTrackGroup()
        val tracksMap = mutableMapOf<String, ExportKeyframeTrack>()

        for ((propName, rawTrackObj) in rawTracks) {
            val trackMap = rawTrackObj as? Map<String, Any> ?: continue
            val defVal = (trackMap["defaultValue"] as? Number)?.toDouble() ?: 0.0
            val rawKfs = trackMap["keyframes"] as? List<Map<String, Any>> ?: emptyList()
            val kfs = rawKfs.map { kfMap ->
                val id = kfMap["id"] as? String ?: ""
                val ts = (kfMap["timestampMs"] as? Number)?.toLong() ?: 0L
                val v = (kfMap["value"] as? Number)?.toDouble() ?: 0.0
                val easingMap = kfMap["easing"] as? Map<String, Any>
                val mode = easingMap?.get("mode") as? String ?: (kfMap["easing"] as? String ?: "easeInOut")
                val x1 = (easingMap?.get("x1") as? Number)?.toDouble() ?: 0.42
                val y1 = (easingMap?.get("y1") as? Number)?.toDouble() ?: 0.0
                val x2 = (easingMap?.get("x2") as? Number)?.toDouble() ?: 0.58
                val y2 = (easingMap?.get("y2") as? Number)?.toDouble() ?: 1.0
                ExportMotionKeyframe(
                    id = id,
                    timestampMs = ts,
                    value = v,
                    mode = mode,
                    x1 = x1,
                    y1 = y1,
                    x2 = x2,
                    y2 = y2
                )
            }.sortedBy { it.timestampMs }

            tracksMap[propName] = ExportKeyframeTrack(
                property = propName,
                defaultValue = defVal,
                keyframes = kfs
            )
        }
        return ExportKeyframeTrackGroup(tracksMap)
    }
}

/**
 * Speed Ramping and Time Remapping native engine structures
 */
data class ExportSpeedPoint(
    val timeRatio: Double,
    val speedMultiplier: Double
)

data class ExportSpeedCurve(
    val type: String = "none",
    val points: List<ExportSpeedPoint> = emptyList(),
    val keepPitch: Boolean = true,
    val smoothSlowMo: Boolean = true
) {
    val averageSpeed: Double
        get() {
            if (points.isEmpty()) return 1.0
            if (points.size == 1) return points.first().speedMultiplier.coerceAtLeast(0.1)
            var sum = 0.0
            val steps = 20
            for (i in 0..steps) {
                val t = i.toDouble() / steps
                sum += evaluateSpeedAt(t)
            }
            return (sum / (steps + 1)).coerceIn(0.1, 50.0)
        }

    fun evaluateSpeedAt(tRatio: Double): Double {
        if (points.isEmpty()) return 1.0
        val t = tRatio.coerceIn(0.0, 1.0)
        if (t <= points.first().timeRatio) return points.first().speedMultiplier.coerceAtLeast(0.1)
        if (t >= points.last().timeRatio) return points.last().speedMultiplier.coerceAtLeast(0.1)
        for (i in 0 until points.size - 1) {
            val p0 = points[i]
            val p1 = points[i + 1]
            if (t >= p0.timeRatio && t <= p1.timeRatio) {
                val span = (p1.timeRatio - p0.timeRatio).coerceAtLeast(0.0001)
                val u = (t - p0.timeRatio) / span
                val s = p0.speedMultiplier + u * (p1.speedMultiplier - p0.speedMultiplier)
                return s.coerceIn(0.1, 50.0)
            }
        }
        return 1.0
    }

    fun getSourceProgressAt(tRatio: Double): Double {
        val t = tRatio.coerceIn(0.0, 1.0)
        if (t <= 0.0) return 0.0
        if (t >= 1.0) return 1.0
        val steps = 50
        val dt = 1.0 / steps
        val targetIndex = (t * steps).toInt().coerceIn(1, steps)

        var totalArea = 0.0
        var targetArea = 0.0
        for (i in 0 until steps) {
            val mid = (i + 0.5) * dt
            val spd = evaluateSpeedAt(mid)
            totalArea += spd * dt
            if (i < targetIndex) {
                targetArea += spd * dt
            }
        }
        if (totalArea <= 0.00001) return t
        return (targetArea / totalArea).coerceIn(0.0, 1.0)
    }
}

data class ExportFreezeFrame(
    val timelineOffsetMs: Long,
    val durationMs: Long,
    val sourceTimeMs: Long
)

object ExportTimeRemapper {
    fun timelineToSourceTime(
        timelineOffsetMs: Long,
        trimStartMs: Long,
        trimEndMs: Long,
        originalDurationMs: Long,
        speed: Double = 1.0,
        speedCurve: ExportSpeedCurve? = null,
        freezeFrame: ExportFreezeFrame? = null,
        isFrozen: Boolean = false,
        isReversed: Boolean = false
    ): Long {
        val trimmedDurationMs = (trimEndMs - trimStartMs).coerceAtLeast(0L)
        if (trimmedDurationMs <= 0L) return trimStartMs

        if (isFrozen) {
            return trimStartMs
        }

        if (freezeFrame != null && freezeFrame.durationMs > 0L) {
            val fStart = freezeFrame.timelineOffsetMs
            val fEnd = fStart + freezeFrame.durationMs
            if (timelineOffsetMs in fStart..fEnd) {
                return freezeFrame.sourceTimeMs
            }
            val effectiveTimelineMs = if (timelineOffsetMs > fEnd) timelineOffsetMs - freezeFrame.durationMs else timelineOffsetMs
            return computeSpeedSourceTime(
                effectiveTimelineMs,
                trimStartMs,
                trimEndMs,
                trimmedDurationMs,
                speed,
                speedCurve,
                isReversed
            )
        }

        return computeSpeedSourceTime(
            timelineOffsetMs,
            trimStartMs,
            trimEndMs,
            trimmedDurationMs,
            speed,
            speedCurve,
            isReversed
        )
    }

    private fun computeSpeedSourceTime(
        timelineOffsetMs: Long,
        trimStartMs: Long,
        trimEndMs: Long,
        trimmedDurationMs: Long,
        speed: Double,
        speedCurve: ExportSpeedCurve?,
        isReversed: Boolean
    ): Long {
        val mappedMs: Long = if (speedCurve != null && speedCurve.points.isNotEmpty()) {
            val effectiveDurationMs = (trimmedDurationMs / speedCurve.averageSpeed).toLong().coerceAtLeast(1L)
            val timelineRatio = (timelineOffsetMs.toDouble() / effectiveDurationMs.toDouble()).coerceIn(0.0, 1.0)
            val sourceProgress = speedCurve.getSourceProgressAt(timelineRatio)
            trimStartMs + (trimmedDurationMs * sourceProgress).toLong()
        } else {
            val effSpeed = if (speed > 0.0) speed else 1.0
            trimStartMs + (timelineOffsetMs * effSpeed).toLong()
        }

        val clampedMs = mappedMs.coerceIn(trimStartMs, trimEndMs)
        return if (isReversed) {
            trimEndMs - (clampedMs - trimStartMs)
        } else {
            clampedMs
        }
    }

    fun calculateActiveDurationMs(
        trimStartMs: Long,
        trimEndMs: Long,
        speed: Double,
        speedCurve: ExportSpeedCurve?,
        freezeFrame: ExportFreezeFrame?
    ): Long {
        val trimmedMs = (trimEndMs - trimStartMs).coerceAtLeast(0L)
        val baseMs = if (speedCurve != null && speedCurve.points.isNotEmpty()) {
            (trimmedMs / speedCurve.averageSpeed).toLong().coerceAtLeast(1L)
        } else {
            val effSpeed = if (speed > 0.0) speed else 1.0
            (trimmedMs / effSpeed).toLong().coerceAtLeast(1L)
        }
        val freezeMs = freezeFrame?.durationMs ?: 0L
        return baseMs + freezeMs
    }
}

object SpeedRemapParser {
    @Suppress("UNCHECKED_CAST")
    fun parseSpeedCurve(map: Map<String, Any>?): ExportSpeedCurve? {
        if (map == null) return null
        val type = map["type"] as? String ?: "none"
        if (type == "none") return null
        val pointsRaw = map["points"] as? List<Map<String, Any>> ?: emptyList()
        val points = pointsRaw.map { pt ->
            ExportSpeedPoint(
                timeRatio = (pt["timeRatio"] as? Number)?.toDouble() ?: 0.0,
                speedMultiplier = (pt["speedMultiplier"] as? Number)?.toDouble() ?: 1.0
            )
        }
        val keepPitch = map["keepPitch"] as? Boolean ?: true
        val smoothSlowMo = map["smoothSlowMo"] as? Boolean ?: true
        return ExportSpeedCurve(type, points, keepPitch, smoothSlowMo)
    }

    fun parseFreezeFrame(map: Map<String, Any>?): ExportFreezeFrame? {
        if (map == null) return null
        val offsetMs = (map["timelineOffsetMs"] as? Number)?.toLong() ?: 0L
        val durMs = (map["durationMs"] as? Number)?.toLong() ?: 0L
        val srcMs = (map["sourceTimeMs"] as? Number)?.toLong() ?: 0L
        if (durMs <= 0L) return null
        return ExportFreezeFrame(offsetMs, durMs, srcMs)
    }
}

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
    val rotationAngle: Double = 0.0,
    val brightness: Double = 0.0,
    val contrast: Double = 0.0,
    val saturation: Double = 0.0,
    val exposure: Double = 0.0,
    val temperature: Double = 0.0,
    val tint: Double = 0.0,
    val highlights: Double = 0.0,
    val shadows: Double = 0.0,
    val blacks: Double = 0.0,
    val whites: Double = 0.0,
    val vignette: Double = 0.0,
    val vignetteRadius: Double = 0.8,
    val vignetteSoftness: Double = 0.5,
    val sharpness: Double = 0.0,
    val filterId: String? = null,
    val filterIntensity: Double = 1.0,
    val keyframeTracks: ExportKeyframeTrackGroup = ExportKeyframeTrackGroup(),
    val speedCurve: ExportSpeedCurve? = null,
    val freezeFrame: ExportFreezeFrame? = null,
    val isFrozen: Boolean = false,
    val isReversed: Boolean = false
) {
    val activeDurationMs: Long
        get() = ExportTimeRemapper.calculateActiveDurationMs(
            trimStartMs,
            trimEndMs,
            speed,
            speedCurve,
            freezeFrame
        )

    val hasColorGrading: Boolean
        get() = (brightness != 0.0 || contrast != 0.0 || saturation != 0.0 || exposure != 0.0 ||
                temperature != 0.0 || tint != 0.0 || highlights != 0.0 || shadows != 0.0 ||
                blacks != 0.0 || whites != 0.0 ||
                (filterId != null && filterId != "none" && filterIntensity > 0.0))

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
    val volume: Double,
    val speed: Double = 1.0,
    val fadeInMs: Long = 0L,
    val fadeOutMs: Long = 0L,
    val isMuted: Boolean = false,
    val keyframeTracks: ExportKeyframeTrackGroup = ExportKeyframeTrackGroup()
)

data class AudioSourceSpec(
    val path: String,
    val timelineStartMs: Long,
    val trimStartMs: Long,
    val trimEndMs: Long,
    val volume: Double,
    val speed: Double = 1.0,
    val fadeInMs: Long = 0L,
    val fadeOutMs: Long = 0L,
    val keyframeTracks: ExportKeyframeTrackGroup = ExportKeyframeTrackGroup()
)

data class ExportTextOverlay(
    val id: String,
    val text: String,
    val startTimeMs: Long,
    val durationMs: Long,
    val fontSize: Double,
    val textColor: Int,
    val backgroundColor: Int?,
    val x: Double,
    val y: Double,
    val isBold: Boolean,
    val isItalic: Boolean,
    val isUnderline: Boolean = false,
    val textAlign: String = "center",
    val fontFamily: String? = null,
    val boxWidth: Double? = null,
    val scale: Double = 1.0,
    val keyframeTracks: ExportKeyframeTrackGroup = ExportKeyframeTrackGroup()
)

data class ExportPipOverlay(
    val id: String,
    val path: String?,
    val thumbnailPath: String?,
    val isPhoto: Boolean,
    val title: String,
    val startTimeMs: Long,
    val durationMs: Long,
    val x: Double,
    val y: Double,
    val scale: Double,
    val rotation: Double,
    val opacity: Double,
    val flipHorizontal: Boolean = false,
    val flipVertical: Boolean = false,
    val speed: Double = 1.0,
    val volume: Double = 1.0,
    val isMuted: Boolean = false,
    val filterId: String? = null,
    val filterIntensity: Double = 1.0,
    val blendMode: String? = null,
    val enableChromaKey: Boolean = false,
    val chromaKeyColor: Int = 0,
    val chromaSimilarity: Double = 0.4,
    val chromaSmoothness: Double = 0.1,
    val cropLeft: Double = 0.0,
    val cropTop: Double = 0.0,
    val cropWidth: Double = 1.0,
    val cropHeight: Double = 1.0,
    val cornerTopLeftX: Double = 0.0,
    val cornerTopLeftY: Double = 0.0,
    val cornerTopRightX: Double = 1.0,
    val cornerTopRightY: Double = 0.0,
    val cornerBottomLeftX: Double = 0.0,
    val cornerBottomLeftY: Double = 1.0,
    val cornerBottomRightX: Double = 1.0,
    val cornerBottomRightY: Double = 1.0,
    val inAnimation: String? = null,
    val inAnimationDuration: Double = 0.5,
    val overallAnimation: String? = null,
    val outAnimation: String? = null,
    val outAnimationDuration: Double = 0.5,
    val brightness: Double = 0.0,
    val contrast: Double = 0.0,
    val saturation: Double = 0.0,
    val exposure: Double = 0.0,
    val temperature: Double = 0.0,
    val tint: Double = 0.0,
    val vignette: Double = 0.0,
    val sharpness: Double = 0.0,
    val outlineEnabled: Boolean = false,
    val outlineColor: Int = 0,
    val outlineWidth: Double = 2.0,
    val shadowEnabled: Boolean = false,
    val shadowColor: Int = 0,
    val shadowBlur: Double = 8.0,
    val shadowDx: Double = 2.0,
    val shadowDy: Double = 4.0,
    val shadowOpacity: Double = 0.6,
    val glowEnabled: Boolean = false,
    val glowColor: Int = 0,
    val glowRadius: Double = 12.0,
    val glowIntensity: Double = 0.7,
    val keyframeTracks: ExportKeyframeTrackGroup = ExportKeyframeTrackGroup(),
    val speedCurve: ExportSpeedCurve? = null,
    val freezeFrame: ExportFreezeFrame? = null,
    val isFrozen: Boolean = false,
    val isReversed: Boolean = false
) {
    val hasColorGrading: Boolean
        get() = (brightness != 0.0 || contrast != 0.0 || saturation != 0.0 || exposure != 0.0 ||
                temperature != 0.0 || tint != 0.0 || (filterId != null && filterId != "none" && filterIntensity > 0.0))
}

object ColorGradingHelper {
    fun calculateMatrixAndOffset(
        brightness: Float,
        contrast: Float,
        saturation: Float,
        exposure: Float,
        temperature: Float,
        tint: Float,
        highlights: Float,
        shadows: Float,
        blacks: Float,
        whites: Float,
        filterId: String?,
        filterIntensity: Float,
        outMatrix: FloatArray,
        outOffset: FloatArray
    ) {
        val b = (brightness + exposure) * (50.0f / 255.0f)
        val c = (1.0f + contrast).coerceIn(0.0f, 3.0f)
        val s = (1.0f + saturation).coerceIn(0.0f, 3.0f)

        var tempR = if (temperature > 0f) temperature * (25.0f / 255.0f) else 0f
        var tempB = if (temperature < 0f) -temperature * (25.0f / 255.0f) else 0f
        var tintG = if (tint < 0f) -tint * (20.0f / 255.0f) else 0f
        var tintM = if (tint > 0f) tint * (20.0f / 255.0f) else 0f

        val highOffset = (highlights + whites) * (15.0f / 255.0f)
        val shadowOffset = (shadows + blacks) * (15.0f / 255.0f)
        var totalOffset = b + highOffset + shadowOffset

        var rScale = 1.0f
        var gScale = 1.0f
        var bScale = 1.0f

        if (filterId != null && filterId.isNotEmpty() && filterId != "none" && filterIntensity > 0.0f) {
            val fi = filterIntensity.coerceIn(0.0f, 1.0f)
            when (filterId.lowercase()) {
                "vivid" -> {
                    rScale *= (1.0f + 0.3f * fi)
                    gScale *= (1.0f + 0.3f * fi)
                    bScale *= (1.0f + 0.3f * fi)
                    totalOffset += (5.0f / 255.0f) * fi
                }
                "warm" -> {
                    tempR += (35.0f / 255.0f) * fi
                    tempB -= (20.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.15f * fi)
                }
                "cool" -> {
                    tempB += (35.0f / 255.0f) * fi
                    tempR -= (15.0f / 255.0f) * fi
                    bScale *= (1.0f + 0.25f * fi)
                }
                "vintage" -> {
                    tempR += (20.0f / 255.0f) * fi
                    tempB -= (20.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.1f * fi)
                }
                "cinema", "cinematic" -> {
                    tempR += (15.0f / 255.0f) * fi
                    tempB += (25.0f / 255.0f) * fi
                    tintG -= (10.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.15f * fi)
                }
                "fade" -> {
                    rScale *= (1.0f - 0.15f * fi)
                    gScale *= (1.0f - 0.15f * fi)
                    bScale *= (1.0f - 0.15f * fi)
                    totalOffset += (30.0f / 255.0f) * fi
                }
                "sepia" -> {
                    tempR += (30.0f / 255.0f) * fi
                    tempB -= (20.0f / 255.0f) * fi
                    tintG += (10.0f / 255.0f) * fi
                }
                "dramatic" -> {
                    rScale *= (1.0f + 0.35f * fi)
                    gScale *= (1.0f + 0.35f * fi)
                    bScale *= (1.0f + 0.35f * fi)
                    totalOffset -= (15.0f / 255.0f) * fi
                }
                "portrait" -> {
                    tempR += (10.0f / 255.0f) * fi
                    tintG += (5.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.1f * fi)
                }
                "cyberpunk" -> {
                    tempR += (40.0f / 255.0f) * fi
                    tempB += (40.0f / 255.0f) * fi
                    tintG -= (20.0f / 255.0f) * fi
                }
                "moody" -> {
                    rScale *= (1.0f - 0.1f * fi)
                    gScale *= (1.0f - 0.1f * fi)
                    bScale *= (1.0f - 0.05f * fi)
                    totalOffset -= (10.0f / 255.0f) * fi
                }
                "teal_orange", "tealandorange" -> {
                    tempR += (20.0f / 255.0f) * fi
                    tempB -= (15.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.2f * fi)
                    bScale *= (1.0f - 0.2f * fi)
                }
                "warm_sunset", "warmsunset" -> {
                    tempR += (15.0f / 255.0f) * fi
                    tempB -= (10.0f / 255.0f) * fi
                    rScale *= (1.0f + 0.25f * fi)
                    gScale *= (1.0f + 0.1f * fi)
                    bScale *= (1.0f - 0.25f * fi)
                }
            }
        }

        val isMono = filterId?.lowercase() in listOf("mono", "blackandwhite", "black_white", "bw", "grayscale")
        val effS = if (isMono) s * (1.0f - filterIntensity.coerceIn(0f, 1f)) else s

        val lumR = 0.2126f * (1.0f - effS)
        val lumG = 0.7152f * (1.0f - effS)
        val lumB = 0.0722f * (1.0f - effS)

        val m00 = (lumR + effS) * c * rScale
        val m01 = lumG * c * rScale
        val m02 = lumB * c * rScale

        val m10 = lumR * c * gScale
        val m11 = (lumG + effS) * c * gScale
        val m12 = lumB * c * gScale

        val m20 = lumR * c * bScale
        val m21 = lumG * c * bScale
        val m22 = (lumB + effS) * c * bScale

        val cOffset = (128.0f / 255.0f) * (1.0f - c)

        outMatrix[0] = m00; outMatrix[1] = m10; outMatrix[2] = m20; outMatrix[3] = 0f
        outMatrix[4] = m01; outMatrix[5] = m11; outMatrix[6] = m21; outMatrix[7] = 0f
        outMatrix[8] = m02; outMatrix[9] = m12; outMatrix[10] = m22; outMatrix[11] = 0f
        outMatrix[12] = 0f; outMatrix[13] = 0f; outMatrix[14] = 0f; outMatrix[15] = 1f

        outOffset[0] = totalOffset + tempR + tintM + cOffset
        outOffset[1] = totalOffset + tintG + cOffset
        outOffset[2] = totalOffset + tempB + tintM + cOffset
        outOffset[3] = 0f
    }
}

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
        private var oesColorMatrixLoc = 0
        private var oesColorOffsetLoc = 0
        private var oesHasColorGradingLoc = 0
        private var oesVignetteLoc = 0
        private var oesVignetteRadiusLoc = 0
        private var oesVignetteSoftnessLoc = 0
        private var oesSharpenLoc = 0
        private var oesTexelSizeLoc = 0
        private var oesAlphaLoc = 0

        private var tex2DProgram = 0
        private var tex2DPosLoc = 0
        private var tex2DTexCoordLoc = 0
        private var tex2DMVPLoc = 0
        private var tex2DSTLoc = 0
        private var tex2DAlphaLoc = 0
        private var tex2DColorMatrixLoc = 0
        private var tex2DColorOffsetLoc = 0
        private var tex2DHasColorGradingLoc = 0
        private var tex2DVignetteLoc = 0
        private var tex2DVignetteRadiusLoc = 0
        private var tex2DVignetteSoftnessLoc = 0
        private var tex2DSharpenLoc = 0
        private var tex2DTexelSizeLoc = 0

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
        val reusableOverlayQuadBuffer: FloatBuffer
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

            reusableOverlayQuadBuffer = ByteBuffer.allocateDirect(16 * 4)
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
                uniform mat4 uColorMatrix;
                uniform vec4 uColorOffset;
                uniform float uHasColorGrading;
                uniform float uVignette;
                uniform float uVignetteRadius;
                uniform float uVignetteSoftness;
                uniform float uSharpen;
                uniform vec2 uTexelSize;
                uniform float uAlpha;

                void main() {
                    vec4 col;
                    if (uSharpen > 0.0) {
                        vec4 c = texture2D(sTexture, vTextureCoord);
                        vec4 up = texture2D(sTexture, vTextureCoord + vec2(0.0, uTexelSize.y));
                        vec4 down = texture2D(sTexture, vTextureCoord - vec2(0.0, uTexelSize.y));
                        vec4 left = texture2D(sTexture, vTextureCoord - vec2(uTexelSize.x, 0.0));
                        vec4 right = texture2D(sTexture, vTextureCoord + vec2(uTexelSize.x, 0.0));
                        col = clamp(c + (c * 4.0 - up - down - left - right) * uSharpen, 0.0, 1.0);
                    } else {
                        col = texture2D(sTexture, vTextureCoord);
                    }
                    if (uHasColorGrading > 0.5) {
                        col = clamp(uColorMatrix * col + uColorOffset, 0.0, 1.0);
                    }
                    if (uVignette > 0.0) {
                        vec2 uv = vTextureCoord - vec2(0.5);
                        float dist = length(uv) * 1.41421356;
                        float vig = smoothstep(uVignetteRadius, uVignetteRadius - max(uVignetteSoftness, 0.001), dist);
                        col.rgb = mix(col.rgb, col.rgb * vig, uVignette);
                    }
                    gl_FragColor = vec4(col.rgb, col.a * uAlpha);
                }
            """.trimIndent()

            oesProgram = createProgram(oesVS, oesFS)
            oesPosLoc = GLES20.glGetAttribLocation(oesProgram, "aPosition")
            oesTexCoordLoc = GLES20.glGetAttribLocation(oesProgram, "aTextureCoord")
            oesMVPLoc = GLES20.glGetUniformLocation(oesProgram, "uMVPMatrix")
            oesSTLoc = GLES20.glGetUniformLocation(oesProgram, "uSTMatrix")
            oesColorMatrixLoc = GLES20.glGetUniformLocation(oesProgram, "uColorMatrix")
            oesColorOffsetLoc = GLES20.glGetUniformLocation(oesProgram, "uColorOffset")
            oesHasColorGradingLoc = GLES20.glGetUniformLocation(oesProgram, "uHasColorGrading")
            oesVignetteLoc = GLES20.glGetUniformLocation(oesProgram, "uVignette")
            oesVignetteRadiusLoc = GLES20.glGetUniformLocation(oesProgram, "uVignetteRadius")
            oesVignetteSoftnessLoc = GLES20.glGetUniformLocation(oesProgram, "uVignetteSoftness")
            oesSharpenLoc = GLES20.glGetUniformLocation(oesProgram, "uSharpen")
            oesTexelSizeLoc = GLES20.glGetUniformLocation(oesProgram, "uTexelSize")
            oesAlphaLoc = GLES20.glGetUniformLocation(oesProgram, "uAlpha")

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
                uniform float uAlpha;
                uniform mat4 uColorMatrix;
                uniform vec4 uColorOffset;
                uniform float uHasColorGrading;
                uniform float uVignette;
                uniform float uVignetteRadius;
                uniform float uVignetteSoftness;
                uniform float uSharpen;
                uniform vec2 uTexelSize;

                void main() {
                    vec4 col;
                    if (uSharpen > 0.0) {
                        vec4 c = texture2D(sTexture, vTextureCoord);
                        vec4 up = texture2D(sTexture, vTextureCoord + vec2(0.0, uTexelSize.y));
                        vec4 down = texture2D(sTexture, vTextureCoord - vec2(0.0, uTexelSize.y));
                        vec4 left = texture2D(sTexture, vTextureCoord - vec2(uTexelSize.x, 0.0));
                        vec4 right = texture2D(sTexture, vTextureCoord + vec2(uTexelSize.x, 0.0));
                        col = clamp(c + (c * 4.0 - up - down - left - right) * uSharpen, 0.0, 1.0);
                    } else {
                        col = texture2D(sTexture, vTextureCoord);
                    }
                    if (uHasColorGrading > 0.5) {
                        col = clamp(uColorMatrix * col + uColorOffset, 0.0, 1.0);
                    }
                    if (uVignette > 0.0) {
                        vec2 uv = vTextureCoord - vec2(0.5);
                        float dist = length(uv) * 1.41421356;
                        float vig = smoothstep(uVignetteRadius, uVignetteRadius - max(uVignetteSoftness, 0.001), dist);
                        col.rgb = mix(col.rgb, col.rgb * vig, uVignette);
                    }
                    gl_FragColor = vec4(col.rgb, col.a * uAlpha);
                }
            """.trimIndent()

            tex2DProgram = createProgram(tex2DVS, tex2DFS)
            tex2DPosLoc = GLES20.glGetAttribLocation(tex2DProgram, "aPosition")
            tex2DTexCoordLoc = GLES20.glGetAttribLocation(tex2DProgram, "aTextureCoord")
            tex2DMVPLoc = GLES20.glGetUniformLocation(tex2DProgram, "uMVPMatrix")
            tex2DSTLoc = GLES20.glGetUniformLocation(tex2DProgram, "uSTMatrix")
            tex2DAlphaLoc = GLES20.glGetUniformLocation(tex2DProgram, "uAlpha")
            tex2DColorMatrixLoc = GLES20.glGetUniformLocation(tex2DProgram, "uColorMatrix")
            tex2DColorOffsetLoc = GLES20.glGetUniformLocation(tex2DProgram, "uColorOffset")
            tex2DHasColorGradingLoc = GLES20.glGetUniformLocation(tex2DProgram, "uHasColorGrading")
            tex2DVignetteLoc = GLES20.glGetUniformLocation(tex2DProgram, "uVignette")
            tex2DVignetteRadiusLoc = GLES20.glGetUniformLocation(tex2DProgram, "uVignetteRadius")
            tex2DVignetteSoftnessLoc = GLES20.glGetUniformLocation(tex2DProgram, "uVignetteSoftness")
            tex2DSharpenLoc = GLES20.glGetUniformLocation(tex2DProgram, "uSharpen")
            tex2DTexelSizeLoc = GLES20.glGetUniformLocation(tex2DProgram, "uTexelSize")

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
                    } else if (uType == 12) { // wipeUp
                        if (vTextureCoord.y < (1.0 - p)) {
                            gl_FragColor = cOut;
                        } else {
                            gl_FragColor = cIn;
                        }
                    } else if (uType == 13) { // wipeDown
                        if (vTextureCoord.y > p) {
                            gl_FragColor = cOut;
                        } else {
                            gl_FragColor = cIn;
                        }
                    } else if (uType == 14) { // circle
                        float dist = length(vTextureCoord - 0.5);
                        if (dist <= p * 0.7071) {
                            gl_FragColor = cIn;
                        } else {
                            gl_FragColor = cOut;
                        }
                    } else if (uType == 15) { // radial
                        vec2 d = vTextureCoord - 0.5;
                        float angle = (atan(d.y, d.x) + 3.14159265) / 6.2831853;
                        if (angle <= p) {
                            gl_FragColor = cIn;
                        } else {
                            gl_FragColor = cOut;
                        }
                    } else if (uType == 16) { // blur
                        float blurAmount = (1.0 - abs(p - 0.5) * 2.0) * 0.015;
                        vec4 bOut = (
                            texture2D(uOutgoingTex, vTextureCoord + vec2(-blurAmount, -blurAmount)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(0.0, -blurAmount)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(blurAmount, -blurAmount)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(-blurAmount, 0.0)) +
                            texture2D(uOutgoingTex, vTextureCoord) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(blurAmount, 0.0)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(-blurAmount, blurAmount)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(0.0, blurAmount)) +
                            texture2D(uOutgoingTex, vTextureCoord + vec2(blurAmount, blurAmount))
                        ) / 9.0;
                        vec4 bIn = (
                            texture2D(uIncomingTex, vTextureCoord + vec2(-blurAmount, -blurAmount)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(0.0, -blurAmount)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(blurAmount, -blurAmount)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(-blurAmount, 0.0)) +
                            texture2D(uIncomingTex, vTextureCoord) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(blurAmount, 0.0)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(-blurAmount, blurAmount)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(0.0, blurAmount)) +
                            texture2D(uIncomingTex, vTextureCoord + vec2(blurAmount, blurAmount))
                        ) / 9.0;
                        gl_FragColor = mix(bOut, bIn, p);
                    } else if (uType == 17) { // pixelate
                        float peak = 1.0 - abs(p - 0.5) * 2.0;
                        float cells = mix(100.0, 15.0, peak);
                        vec2 steppedUv = floor(vTextureCoord * cells) / cells;
                        vec4 pOut = texture2D(uOutgoingTex, steppedUv);
                        vec4 pIn = texture2D(uIncomingTex, steppedUv);
                        gl_FragColor = mix(pOut, pIn, p);
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
            quadBuffer: FloatBuffer,
            alpha: Float = 1.0f,
            colorMatrix: FloatArray? = null,
            colorOffset: FloatArray? = null,
            vignette: Float = 0f,
            vignetteRadius: Float = 0.8f,
            vignetteSoftness: Float = 0.5f,
            sharpen: Float = 0f,
            texW: Float = width.toFloat(),
            texH: Float = height.toFloat()
        ) {
            GLES20.glUseProgram(oesProgram)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

            GLES20.glUniformMatrix4fv(oesMVPLoc, 1, false, mvpMatrix, 0)
            GLES20.glUniformMatrix4fv(oesSTLoc, 1, false, stMatrix, 0)
            if (oesAlphaLoc >= 0) {
                GLES20.glUniform1f(oesAlphaLoc, alpha)
            }

            if (colorMatrix != null && colorOffset != null && oesHasColorGradingLoc >= 0) {
                GLES20.glUniform1f(oesHasColorGradingLoc, 1.0f)
                GLES20.glUniformMatrix4fv(oesColorMatrixLoc, 1, false, colorMatrix, 0)
                GLES20.glUniform4fv(oesColorOffsetLoc, 1, colorOffset, 0)
            } else if (oesHasColorGradingLoc >= 0) {
                GLES20.glUniform1f(oesHasColorGradingLoc, 0.0f)
            }

            if (oesVignetteLoc >= 0) {
                GLES20.glUniform1f(oesVignetteLoc, vignette)
                GLES20.glUniform1f(oesVignetteRadiusLoc, vignetteRadius)
                GLES20.glUniform1f(oesVignetteSoftnessLoc, vignetteSoftness)
            }
            if (oesSharpenLoc >= 0) {
                GLES20.glUniform1f(oesSharpenLoc, sharpen)
                GLES20.glUniform2f(oesTexelSizeLoc, 1.0f / max(texW, 1.0f), 1.0f / max(texH, 1.0f))
            }

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
            quadBuffer: FloatBuffer,
            alpha: Float = 1.0f,
            colorMatrix: FloatArray? = null,
            colorOffset: FloatArray? = null,
            vignette: Float = 0f,
            vignetteRadius: Float = 0.8f,
            vignetteSoftness: Float = 0.5f,
            sharpen: Float = 0f,
            texW: Float = width.toFloat(),
            texH: Float = height.toFloat()
        ) {
            GLES20.glUseProgram(tex2DProgram)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)

            GLES20.glUniformMatrix4fv(tex2DMVPLoc, 1, false, mvpMatrix, 0)
            GLES20.glUniformMatrix4fv(tex2DSTLoc, 1, false, tex2DSTMatrix, 0)
            if (tex2DAlphaLoc >= 0) {
                GLES20.glUniform1f(tex2DAlphaLoc, alpha)
            }

            if (colorMatrix != null && colorOffset != null && tex2DHasColorGradingLoc >= 0) {
                GLES20.glUniform1f(tex2DHasColorGradingLoc, 1.0f)
                GLES20.glUniformMatrix4fv(tex2DColorMatrixLoc, 1, false, colorMatrix, 0)
                GLES20.glUniform4fv(tex2DColorOffsetLoc, 1, colorOffset, 0)
            } else if (tex2DHasColorGradingLoc >= 0) {
                GLES20.glUniform1f(tex2DHasColorGradingLoc, 0.0f)
            }

            if (tex2DVignetteLoc >= 0) {
                GLES20.glUniform1f(tex2DVignetteLoc, vignette)
                GLES20.glUniform1f(tex2DVignetteRadiusLoc, vignetteRadius)
                GLES20.glUniform1f(tex2DVignetteSoftnessLoc, vignetteSoftness)
            }
            if (tex2DSharpenLoc >= 0) {
                GLES20.glUniform1f(tex2DSharpenLoc, sharpen)
                GLES20.glUniform2f(tex2DTexelSizeLoc, 1.0f / max(texW, 1.0f), 1.0f / max(texH, 1.0f))
            }

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

        fun renderOverlay(
            textureId: Int,
            dstLeft: Float,
            dstTop: Float,
            dstRight: Float,
            dstBottom: Float
        ) {
            reusableOverlayQuadBuffer.clear()
            reusableOverlayQuadBuffer.put(dstLeft).put(dstTop).put(0.0f).put(1.0f)
            reusableOverlayQuadBuffer.put(dstLeft).put(dstBottom).put(0.0f).put(0.0f)
            reusableOverlayQuadBuffer.put(dstRight).put(dstTop).put(1.0f).put(1.0f)
            reusableOverlayQuadBuffer.put(dstRight).put(dstBottom).put(1.0f).put(0.0f)
            reusableOverlayQuadBuffer.position(0)

            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            render2DTexture(textureId, projMatrix, reusableOverlayQuadBuffer)
            GLES20.glDisable(GLES20.GL_BLEND)
        }

        fun renderPipOverlay(
            textureId: Int,
            dstCenterX: Float,
            dstCenterY: Float,
            baseW: Float,
            baseH: Float,
            scale: Float,
            rotationRad: Float,
            opacity: Float,
            flipH: Boolean,
            flipV: Boolean,
            cropLeft: Float = 0f,
            cropTop: Float = 0f,
            cropWidth: Float = 1f,
            cropHeight: Float = 1f,
            cornerTlX: Float = 0f,
            cornerTlY: Float = 0f,
            cornerTrX: Float = 1f,
            cornerTrY: Float = 0f,
            cornerBlX: Float = 0f,
            cornerBlY: Float = 1f,
            cornerBrX: Float = 1f,
            cornerBrY: Float = 1f,
            colorMatrix: FloatArray? = null,
            colorOffset: FloatArray? = null,
            vignette: Float = 0f,
            vignetteRadius: Float = 0.8f,
            vignetteSoftness: Float = 0.5f,
            sharpen: Float = 0f
        ) {
            val halfW = (baseW * scale) / 2.0f
            val halfH = (baseH * scale) / 2.0f

            val uMin = cropLeft.coerceIn(0f, 1f)
            val uMax = (cropLeft + cropWidth).coerceIn(0f, 1f)
            val vMin = cropTop.coerceIn(0f, 1f)
            val vMax = (cropTop + cropHeight).coerceIn(0f, 1f)

            val uLeft = if (flipH) uMax else uMin
            val uRight = if (flipH) uMin else uMax
            val vTop = if (flipV) vMin else vMax
            val vBottom = if (flipV) vMax else vMin

            val cosR = Math.cos(rotationRad.toDouble()).toFloat()
            val sinR = Math.sin(rotationRad.toDouble()).toFloat()

            fun rotX(x: Float, y: Float) = x * cosR - y * sinR + dstCenterX
            fun rotY(x: Float, y: Float) = x * sinR + y * cosR + dstCenterY

            val isPinned = (cornerTlX != 0f || cornerTlY != 0f || cornerTrX != 1f || cornerTrY != 0f ||
                    cornerBlX != 0f || cornerBlY != 1f || cornerBrX != 1f || cornerBrY != 1f)

            val x0 = if (isPinned) rotX((cornerTlX - 0.5f) * 2f * halfW, (cornerTlY - 0.5f) * 2f * halfH) else rotX(-halfW, -halfH)
            val y0 = if (isPinned) rotY((cornerTlX - 0.5f) * 2f * halfW, (cornerTlY - 0.5f) * 2f * halfH) else rotY(-halfW, -halfH)

            val x1 = if (isPinned) rotX((cornerBlX - 0.5f) * 2f * halfW, (cornerBlY - 0.5f) * 2f * halfH) else rotX(-halfW, halfH)
            val y1 = if (isPinned) rotY((cornerBlX - 0.5f) * 2f * halfW, (cornerBlY - 0.5f) * 2f * halfH) else rotY(-halfW, halfH)

            val x2 = if (isPinned) rotX((cornerTrX - 0.5f) * 2f * halfW, (cornerTrY - 0.5f) * 2f * halfH) else rotX(halfW, -halfH)
            val y2 = if (isPinned) rotY((cornerTrX - 0.5f) * 2f * halfW, (cornerTrY - 0.5f) * 2f * halfH) else rotY(halfW, -halfH)

            val x3 = if (isPinned) rotX((cornerBrX - 0.5f) * 2f * halfW, (cornerBrY - 0.5f) * 2f * halfH) else rotX(halfW, halfH)
            val y3 = if (isPinned) rotY((cornerBrX - 0.5f) * 2f * halfW, (cornerBrY - 0.5f) * 2f * halfH) else rotY(halfW, halfH)

            reusableOverlayQuadBuffer.clear()
            reusableOverlayQuadBuffer.put(x0).put(y0).put(uLeft).put(vTop)
            reusableOverlayQuadBuffer.put(x1).put(y1).put(uLeft).put(vBottom)
            reusableOverlayQuadBuffer.put(x2).put(y2).put(uRight).put(vTop)
            reusableOverlayQuadBuffer.put(x3).put(y3).put(uRight).put(vBottom)
            reusableOverlayQuadBuffer.position(0)

            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            render2DTexture(
                textureId,
                projMatrix,
                reusableOverlayQuadBuffer,
                alpha = opacity,
                colorMatrix = colorMatrix,
                colorOffset = colorOffset,
                vignette = vignette,
                vignetteRadius = vignetteRadius,
                vignetteSoftness = vignetteSoftness,
                sharpen = sharpen,
                texW = baseW * scale,
                texH = baseH * scale
            )
            GLES20.glDisable(GLES20.GL_BLEND)
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
        textOverlays: List<ExportTextOverlay> = emptyList(),
        pipOverlays: List<ExportPipOverlay> = emptyList(),
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

        // Gather all active audio sources across video clips, audio tracks, and PIP overlays
        val audioSources = ArrayList<AudioSourceSpec>()

        // 1. Primary video clips audio
        for (i in clips.indices) {
            val clip = clips[i]
            if (!clip.isPhoto && (clip.volume > 0.0 || clip.keyframeTracks.hasProperty("volume")) && !clip.path.isNullOrBlank() && File(clip.path).exists()) {
                audioSources.add(
                    AudioSourceSpec(
                        path = clip.path,
                        timelineStartMs = clipStartTimes[i],
                        trimStartMs = clip.trimStartMs,
                        trimEndMs = clip.trimEndMs,
                        volume = clip.volume,
                        speed = clip.speed,
                        fadeInMs = 0L,
                        fadeOutMs = 0L,
                        keyframeTracks = clip.keyframeTracks
                    )
                )
            }
        }

        // 2. Audio tracks & PIP audio
        for (track in audioTracks) {
            if (!track.isMuted && (track.volume > 0.0 || track.keyframeTracks.hasProperty("volume")) && track.path.isNotBlank() && File(track.path).exists()) {
                audioSources.add(
                    AudioSourceSpec(
                        path = track.path,
                        timelineStartMs = track.startTimeMs,
                        trimStartMs = track.trimStartMs,
                        trimEndMs = track.trimEndMs,
                        volume = track.volume,
                        speed = track.speed,
                        fadeInMs = track.fadeInMs,
                        fadeOutMs = track.fadeOutMs,
                        keyframeTracks = track.keyframeTracks
                    )
                )
            }
        }

        var audioExtractor: MediaExtractor? = null
        var audioFormat: MediaFormat? = null
        var tempMixedAudioFile: File? = null

        if (audioSources.isNotEmpty()) {
            val (mixedExt, mixedFile) = mixAndEncodeAudio(audioSources, totalDurationMs, tempDir)
            if (mixedExt != null && mixedFile != null) {
                audioExtractor = mixedExt
                tempMixedAudioFile = mixedFile
                audioFormat = mixedExt.getTrackFormat(0)
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

        // Text overlay textures cache
        val textTextures = mutableMapOf<String, Pair<Bitmap, Int>>()
        for (overlay in textOverlays) {
            if (overlay.text.isNotBlank()) {
                try {
                    val scaleFactor = height / 720.0f
                    val baseTypeface = when (overlay.fontFamily?.lowercase()?.trim()) {
                        "serif" -> Typeface.SERIF
                        "sans-serif" -> Typeface.SANS_SERIF
                        "monospace" -> Typeface.MONOSPACE
                        else -> Typeface.DEFAULT
                    }
                    val typefaceStyle = when {
                        overlay.isBold && overlay.isItalic -> Typeface.BOLD_ITALIC
                        overlay.isBold -> Typeface.BOLD
                        overlay.isItalic -> Typeface.ITALIC
                        else -> Typeface.NORMAL
                    }

                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = overlay.textColor
                        textSize = (overlay.fontSize.toFloat() * scaleFactor).coerceAtLeast(18f)
                        typeface = Typeface.create(baseTypeface, typefaceStyle)
                        isUnderlineText = overlay.isUnderline
                    }

                    val lines = overlay.text.split("\n")
                    val fontMetrics = paint.fontMetrics
                    val lineHeight = fontMetrics.descent - fontMetrics.ascent
                    var maxLineWidth = 0f
                    for (line in lines) {
                        val lw = paint.measureText(line)
                        if (lw > maxLineWidth) maxLineWidth = lw
                    }
                    val totalTextHeight = lineHeight * lines.size

                    val padX = (16f * scaleFactor).toInt()
                    val padY = (10f * scaleFactor).toInt()
                    val targetBoxW = if (overlay.boxWidth != null && overlay.boxWidth > 0) {
                        (overlay.boxWidth.toFloat() * scaleFactor).coerceAtLeast(maxLineWidth + padX * 2)
                    } else {
                        maxLineWidth + padX * 2
                    }
                    val bmpW = targetBoxW.toInt().coerceAtLeast(4)
                    val bmpH = (totalTextHeight + padY * 2).toInt().coerceAtLeast(4)
                    val availableW = bmpW - padX * 2

                    val bmp = Bitmap.createBitmap(bmpW, bmpH, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)

                    val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = overlay.backgroundColor ?: Color.argb(165, 0, 0, 0)
                        style = Paint.Style.FILL
                    }
                    val radius = 8f * scaleFactor
                    canvas.drawRoundRect(RectF(0f, 0f, bmpW.toFloat(), bmpH.toFloat()), radius, radius, bgPaint)

                    val align = overlay.textAlign.lowercase()
                    for (i in lines.indices) {
                        val line = lines[i]
                        val lw = paint.measureText(line)
                        val drawX = when (align) {
                            "left" -> padX.toFloat()
                            "right" -> padX.toFloat() + (availableW - lw)
                            else -> padX.toFloat() + (availableW - lw) / 2f
                        }
                        val drawY = padY.toFloat() - fontMetrics.ascent + (i * lineHeight)
                        canvas.drawText(line, drawX, drawY, paint)
                    }

                    val texIds = IntArray(1)
                    GLES20.glGenTextures(1, texIds, 0)
                    val texId = texIds[0]
                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texId)
                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)

                    textTextures[overlay.id] = Pair(bmp, texId)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed creating text overlay texture for '${overlay.text}': ${e.message}")
                }
            }
        }

        // PIP overlay textures cache
        val pipTextures = mutableMapOf<String, Int>()
        for (pip in pipOverlays) {
            val isImagePip = pip.isPhoto ||
                    (pip.path != null && (
                        pip.path.lowercase().endsWith(".jpg") ||
                        pip.path.lowercase().endsWith(".jpeg") ||
                        pip.path.lowercase().endsWith(".png") ||
                        pip.path.lowercase().endsWith(".webp") ||
                        pip.path.lowercase().endsWith(".bmp") ||
                        pip.path.lowercase().endsWith(".gif") ||
                        pip.path.lowercase().endsWith(".heic") ||
                        pip.path.lowercase().endsWith(".avif")
                    ))
            val imgPath = if (isImagePip) pip.path else (pip.thumbnailPath ?: pip.path)
            if (imgPath != null && !pipTextures.containsKey(imgPath)) {
                val f = File(imgPath)
                if (f.exists()) {
                    try {
                        val options = BitmapFactory.Options().apply {
                            inPreferredConfig = Bitmap.Config.ARGB_8888
                        }
                        val bitmap = BitmapFactory.decodeFile(f.absolutePath, options)
                        if (bitmap != null) {
                            Log.d(TAG, "[PIP] Export Image Decode Success: path=${f.absolutePath}, width=${bitmap.width}, height=${bitmap.height}, config=${bitmap.config}")
                            val tex = IntArray(1)
                            GLES20.glGenTextures(1, tex, 0)
                            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
                            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
                            pipTextures[imgPath] = tex[0]
                            bitmap.recycle()
                        } else {
                            Log.e(TAG, "[PIP] Export Image Decode Failed: bitmap == null for ${f.absolutePath}. Reason: file exists=${f.exists()}, length=${f.length()} bytes, canRead=${f.canRead()}, outMimeType=${options.outMimeType}")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "[PIP] Failed creating PIP texture for '${pip.title}': ${e.message}", e)
                    }
                } else {
                    Log.e(TAG, "[PIP] Export Image File Does Not Exist: $imgPath")
                }
            }
        }

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

            val localTimeSec = localTimeMs / 1000.0
            val kfTracks = clip.keyframeTracks

            // 1. Calculate transform matrices (reusable) with keyframe evaluation
            val centerX = width / 2f
            val centerY = height / 2f
            val kCanvas = width.toFloat() / 360f

            val evalX = kfTracks.evaluate("positionX", localTimeSec, clip.safeXPos)
            val evalY = kfTracks.evaluate("positionY", localTimeSec, clip.safeYPos)
            val evalScale = kfTracks.evaluate("scale", localTimeSec, clip.safeScale)
            val evalRotationAngle = kfTracks.evaluate("rotation", localTimeSec, clip.safeRotationAngle)
            val evalOpacity = kfTracks.evaluate("opacity", localTimeSec, 1.0).coerceIn(0.0, 1.0).toFloat()

            val xExport = evalX.toFloat() * kCanvas
            val yExport = evalY.toFloat() * kCanvas
            val s = evalScale.toFloat()
            val scaleX = (if (clip.flipHorizontal) -1f else 1f) * s
            val scaleY = (if (clip.flipVertical) -1f else 1f) * s
            val continuousDeg = (evalRotationAngle.toFloat() * 180f / Math.PI.toFloat())
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
            val effBrightness = kfTracks.evaluate("brightness", localTimeSec, clip.brightness).toFloat()
            val effContrast = kfTracks.evaluate("contrast", localTimeSec, clip.contrast).toFloat()
            val effSaturation = kfTracks.evaluate("saturation", localTimeSec, clip.saturation).toFloat()
            val effExposure = kfTracks.evaluate("exposure", localTimeSec, clip.exposure).toFloat()
            val effTemperature = kfTracks.evaluate("temperature", localTimeSec, clip.temperature).toFloat()
            val effTint = kfTracks.evaluate("tint", localTimeSec, clip.tint).toFloat()
            val effHighlights = kfTracks.evaluate("highlights", localTimeSec, clip.highlights).toFloat()
            val effShadows = kfTracks.evaluate("shadows", localTimeSec, clip.shadows).toFloat()
            val effBlacks = kfTracks.evaluate("blacks", localTimeSec, clip.blacks).toFloat()
            val effWhites = kfTracks.evaluate("whites", localTimeSec, clip.whites).toFloat()
            val effVignette = kfTracks.evaluate("vignette", localTimeSec, clip.vignette).toFloat()
            val effVignetteRadius = clip.vignetteRadius.toFloat()
            val effVignetteSoftness = clip.vignetteSoftness.toFloat()
            val effSharpness = kfTracks.evaluate("sharpness", localTimeSec, clip.sharpness).toFloat()
            val effFilterIntensity = kfTracks.evaluate("filterIntensity", localTimeSec, clip.filterIntensity).toFloat()

            val hasColorGrading = clip.hasColorGrading || effBrightness != 0f || effContrast != 0f ||
                effSaturation != 0f || effExposure != 0f || effTemperature != 0f || effTint != 0f ||
                effHighlights != 0f || effShadows != 0f || effBlacks != 0f || effWhites != 0f ||
                (clip.filterId != null && effFilterIntensity > 0f)

            val clipColorMatrix = if (hasColorGrading) FloatArray(16) else null
            val clipColorOffset = if (hasColorGrading) FloatArray(4) else null
            if (hasColorGrading && clipColorMatrix != null && clipColorOffset != null) {
                ColorGradingHelper.calculateMatrixAndOffset(
                    brightness = effBrightness,
                    contrast = effContrast,
                    saturation = effSaturation,
                    exposure = effExposure,
                    temperature = effTemperature,
                    tint = effTint,
                    highlights = effHighlights,
                    shadows = effShadows,
                    blacks = effBlacks,
                    whites = effWhites,
                    filterId = clip.filterId,
                    filterIntensity = effFilterIntensity,
                    outMatrix = clipColorMatrix,
                    outOffset = clipColorOffset
                )
            }

            if (evalOpacity < 1.0f) {
                GLES20.glEnable(GLES20.GL_BLEND)
                GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            }

            if (isVideo && decoder != null) {
                inputSurface.renderOESTexture(
                    decoder.textureId,
                    mvpMatrix,
                    decoder.stMatrix,
                    inputSurface.reusableQuadBuffer,
                    alpha = evalOpacity,
                    colorMatrix = clipColorMatrix,
                    colorOffset = clipColorOffset,
                    vignette = effVignette,
                    vignetteRadius = effVignetteRadius,
                    vignetteSoftness = effVignetteSoftness,
                    sharpen = effSharpness,
                    texW = contentW.toFloat(),
                    texH = contentH.toFloat()
                )
            } else if (isPhoto && path != null && photoTextures.containsKey(path)) {
                val tex = photoTextures[path] ?: 0
                inputSurface.render2DTexture(
                    tex,
                    mvpMatrix,
                    inputSurface.reusableQuadBuffer,
                    alpha = evalOpacity,
                    colorMatrix = clipColorMatrix,
                    colorOffset = clipColorOffset,
                    vignette = effVignette,
                    vignetteRadius = effVignetteRadius,
                    vignetteSoftness = effVignetteSoftness,
                    sharpen = effSharpness,
                    texW = contentW.toFloat(),
                    texH = contentH.toFloat()
                )
            } else {
                inputSurface.renderSolidColor(clip.color, mvpMatrix, inputSurface.fullQuadBuffer)
            }

            if (evalOpacity < 1.0f) {
                GLES20.glDisable(GLES20.GL_BLEND)
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
                "wipeUp" -> 12
                "wipeDown" -> 13
                "circle" -> 14
                "radial" -> 15
                "blur" -> 16
                "pixelate" -> 17
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

                    val leftLocalMs = ExportTimeRemapper.timelineToSourceTime(
                        currentTimeMs - clipStartTimes[leftClipIndex],
                        leftClip.trimStartMs,
                        leftClip.trimEndMs,
                        leftClip.originalDurationMs,
                        leftClip.speed,
                        leftClip.speedCurve,
                        leftClip.freezeFrame,
                        leftClip.isFrozen,
                        leftClip.isReversed
                    ).coerceIn(0L, leftClip.originalDurationMs)

                    val rightLocalMs = ExportTimeRemapper.timelineToSourceTime(
                        currentTimeMs - clipStartTimes[rightClipIndex],
                        rightClip.trimStartMs,
                        rightClip.trimEndMs,
                        rightClip.originalDurationMs,
                        rightClip.speed,
                        rightClip.speedCurve,
                        rightClip.freezeFrame,
                        rightClip.isFrozen,
                        rightClip.isReversed
                    ).coerceIn(0L, rightClip.originalDurationMs)

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
                    val localMs = ExportTimeRemapper.timelineToSourceTime(
                        currentTimeMs - clipStartTimes[activeClipIndex],
                        clip.trimStartMs,
                        clip.trimEndMs,
                        clip.originalDurationMs,
                        clip.speed,
                        clip.speedCurve,
                        clip.freezeFrame,
                        clip.isFrozen,
                        clip.isReversed
                    ).coerceIn(0L, clip.originalDurationMs)

                    GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
                    GLES20.glViewport(0, 0, width, height)
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                    renderClip(clip, localMs)
                }

                // Composite Active PIP Overlays
                if (pipTextures.isNotEmpty()) {
                    for (pip in pipOverlays) {
                        val pipEnd = pip.startTimeMs + pip.durationMs
                        if (currentTimeMs in pip.startTimeMs..pipEnd) {
                            val isImagePip = pip.isPhoto ||
                                    (pip.path != null && (
                                        pip.path.lowercase().endsWith(".jpg") ||
                                        pip.path.lowercase().endsWith(".jpeg") ||
                                        pip.path.lowercase().endsWith(".png") ||
                                        pip.path.lowercase().endsWith(".webp") ||
                                        pip.path.lowercase().endsWith(".bmp") ||
                                        pip.path.lowercase().endsWith(".gif") ||
                                        pip.path.lowercase().endsWith(".heic") ||
                                        pip.path.lowercase().endsWith(".avif")
                                    ))
                            val imgPath = if (isImagePip) pip.path else (pip.thumbnailPath ?: pip.path)
                            val texId = if (imgPath != null) pipTextures[imgPath] else null
                            if (texId != null && texId > 0) {
                                val centerX = (pip.x * width).toFloat()
                                val centerY = (pip.y * height).toFloat()
                                val pipW = width * 0.45f
                                val pipH = pipW * (9.0f / 16.0f)

                                val elapsedMs = (currentTimeMs - pip.startTimeMs).coerceAtLeast(0L)
                                val remainingMs = (pipEnd - currentTimeMs).coerceAtLeast(0L)
                                val inDurMs = (pip.inAnimationDuration * 1000).toLong().coerceIn(100L, 2000L)
                                val outDurMs = (pip.outAnimationDuration * 1000).toLong().coerceIn(100L, 2000L)

                                var animScale = 1.0f
                                var animOpacity = 1.0f
                                var animRotation = 0.0f
                                var animOffsetX = 0.0f
                                var animOffsetY = 0.0f

                                if (pip.inAnimation != null && pip.inAnimation != "none" && elapsedMs < inDurMs) {
                                    val t = (elapsedMs.toFloat() / inDurMs.toFloat()).coerceIn(0f, 1f)
                                    when (pip.inAnimation) {
                                        "fade", "fadeIn" -> animOpacity *= t
                                        "slideRight" -> { animOffsetX += (1f - t) * pipW; animOpacity *= t }
                                        "slideLeft" -> { animOffsetX -= (1f - t) * pipW; animOpacity *= t }
                                        "slideUp" -> { animOffsetY -= (1f - t) * pipH; animOpacity *= t }
                                        "slideDown" -> { animOffsetY += (1f - t) * pipH; animOpacity *= t }
                                        "zoomIn" -> { animScale *= (0.2f + 0.8f * t); animOpacity *= t }
                                        "zoomOut" -> { animScale *= (1.8f - 0.8f * t); animOpacity *= t }
                                        "rotateIn" -> { animRotation += (1f - t) * Math.PI.toFloat(); animScale *= t }
                                        "bounce" -> {
                                            val bt = if (t == 0f || t == 1f) t else (Math.pow(2.0, -10.0 * t.toDouble()) * Math.sin((t - 0.075) * (2 * Math.PI) / 0.3) + 1.0).toFloat()
                                            animScale *= bt.coerceIn(0f, 1.5f)
                                        }
                                    }
                                }

                                if (pip.outAnimation != null && pip.outAnimation != "none" && remainingMs < outDurMs) {
                                    val t = (remainingMs.toFloat() / outDurMs.toFloat()).coerceIn(0f, 1f)
                                    when (pip.outAnimation) {
                                        "fade", "fadeOut" -> animOpacity *= t
                                        "slideRight" -> { animOffsetX += (1f - t) * pipW; animOpacity *= t }
                                        "slideLeft" -> { animOffsetX -= (1f - t) * pipW; animOpacity *= t }
                                        "slideUp" -> { animOffsetY -= (1f - t) * pipH; animOpacity *= t }
                                        "slideDown" -> { animOffsetY += (1f - t) * pipH; animOpacity *= t }
                                        "zoomIn" -> { animScale *= (1f + (1f - t) * 0.8f); animOpacity *= t }
                                        "zoomOut" -> animScale *= t
                                    }
                                }

                                if (pip.overallAnimation != null && pip.overallAnimation != "none") {
                                    val sec = elapsedMs / 1000.0
                                    when (pip.overallAnimation) {
                                        "pulse" -> animScale *= 1.0f + 0.08f * Math.sin(sec * 6.0).toFloat()
                                        "float" -> animOffsetY += 6.0f * Math.sin(sec * 3.5).toFloat()
                                        "spin" -> animRotation += (sec * 1.5f).toFloat() % (2f * Math.PI.toFloat())
                                        "flicker" -> animOpacity *= (0.85f + 0.15f * Math.sin(sec * 20.0).toFloat()).coerceIn(0f, 1f)
                                        "shake" -> animOffsetX += 4.0f * Math.sin(sec * 25.0).toFloat()
                                    }
                                }

                                val pipSec = (currentTimeMs - pip.startTimeMs) / 1000.0
                                val pipKfs = pip.keyframeTracks

                                val baseCenterX = (pipKfs.evaluate("positionX", pipSec, pip.x) * width).toFloat()
                                val baseCenterY = (pipKfs.evaluate("positionY", pipSec, pip.y) * height).toFloat()
                                val baseScale = pipKfs.evaluate("scale", pipSec, pip.scale).toFloat()
                                val baseRotation = pipKfs.evaluate("rotation", pipSec, pip.rotation).toFloat()
                                val baseOpacity = pipKfs.evaluate("opacity", pipSec, pip.opacity).toFloat()

                                val effScale = (baseScale * animScale).coerceIn(0.05f, 10f)
                                val effRotation = baseRotation + animRotation
                                val effOpacity = (baseOpacity * animOpacity).coerceIn(0f, 1f)
                                val effCenterX = baseCenterX + animOffsetX
                                val effCenterY = baseCenterY + animOffsetY

                                val kfBrightness = pipKfs.evaluate("brightness", pipSec, pip.brightness).toFloat()
                                val kfContrast = pipKfs.evaluate("contrast", pipSec, pip.contrast).toFloat()
                                val kfSaturation = pipKfs.evaluate("saturation", pipSec, pip.saturation).toFloat()
                                val kfExposure = pipKfs.evaluate("exposure", pipSec, pip.exposure).toFloat()
                                val kfTemp = pipKfs.evaluate("temperature", pipSec, pip.temperature).toFloat()
                                val kfTint = pipKfs.evaluate("tint", pipSec, pip.tint).toFloat()
                                val kfVignette = pipKfs.evaluate("vignette", pipSec, pip.vignette).toFloat()
                                val kfSharpness = pipKfs.evaluate("sharpness", pipSec, pip.sharpness).toFloat()
                                val kfFilterIntensity = pipKfs.evaluate("filterIntensity", pipSec, pip.filterIntensity).toFloat()

                                val pipHasGrading = pip.hasColorGrading || kfBrightness != 0f || kfContrast != 0f ||
                                    kfSaturation != 0f || kfExposure != 0f || kfTemp != 0f || kfTint != 0f ||
                                    (pip.filterId != null && kfFilterIntensity > 0f)

                                val pipColorMatrix = if (pipHasGrading) FloatArray(16) else null
                                val pipColorOffset = if (pipHasGrading) FloatArray(4) else null
                                if (pipHasGrading && pipColorMatrix != null && pipColorOffset != null) {
                                    ColorGradingHelper.calculateMatrixAndOffset(
                                        brightness = kfBrightness,
                                        contrast = kfContrast,
                                        saturation = kfSaturation,
                                        exposure = kfExposure,
                                        temperature = kfTemp,
                                        tint = kfTint,
                                        highlights = 0f,
                                        shadows = 0f,
                                        blacks = 0f,
                                        whites = 0f,
                                        filterId = pip.filterId,
                                        filterIntensity = kfFilterIntensity,
                                        outMatrix = pipColorMatrix,
                                        outOffset = pipColorOffset
                                    )
                                }

                                inputSurface.renderPipOverlay(
                                    textureId = texId,
                                    dstCenterX = effCenterX,
                                    dstCenterY = effCenterY,
                                    baseW = pipW,
                                    baseH = pipH,
                                    scale = effScale,
                                    rotationRad = effRotation,
                                    opacity = effOpacity,
                                    flipH = pip.flipHorizontal,
                                    flipV = pip.flipVertical,
                                    cropLeft = pip.cropLeft.toFloat(),
                                    cropTop = pip.cropTop.toFloat(),
                                    cropWidth = pip.cropWidth.toFloat(),
                                    cropHeight = pip.cropHeight.toFloat(),
                                    cornerTlX = pip.cornerTopLeftX.toFloat(),
                                    cornerTlY = pip.cornerTopLeftY.toFloat(),
                                    cornerTrX = pip.cornerTopRightX.toFloat(),
                                    cornerTrY = pip.cornerTopRightY.toFloat(),
                                    cornerBlX = pip.cornerBottomLeftX.toFloat(),
                                    cornerBlY = pip.cornerBottomLeftY.toFloat(),
                                    cornerBrX = pip.cornerBottomRightX.toFloat(),
                                    cornerBrY = pip.cornerBottomRightY.toFloat(),
                                    colorMatrix = pipColorMatrix,
                                    colorOffset = pipColorOffset,
                                    vignette = kfVignette,
                                    sharpen = kfSharpness
                                )
                            }
                        }
                    }
                }

                // Composite Active Text Overlays
                if (textTextures.isNotEmpty()) {
                    for (txt in textOverlays) {
                        val txtEnd = txt.startTimeMs + txt.durationMs
                        if (currentTimeMs in txt.startTimeMs..txtEnd) {
                            val data = textTextures[txt.id] ?: continue
                            val texId = data.second
                            val bW = data.first.width.toFloat()
                            val bH = data.first.height.toFloat()

                            val txtSec = (currentTimeMs - txt.startTimeMs) / 1000.0
                            val txtKfs = txt.keyframeTracks

                            if (txtKfs.tracks.isNotEmpty() || txt.scale != 1.0) {
                                val evalX = txtKfs.evaluate("positionX", txtSec, txt.x).coerceIn(0.0, 1.0)
                                val evalY = txtKfs.evaluate("positionY", txtSec, txt.y).coerceIn(0.0, 1.0)
                                val evalScale = txtKfs.evaluate("scale", txtSec, txt.scale).coerceIn(0.05, 10.0).toFloat()
                                val evalRotationDeg = txtKfs.evaluate("rotation", txtSec, 0.0).toFloat()
                                val evalRotationRad = (evalRotationDeg * Math.PI / 180.0).toFloat()
                                val evalOpacity = txtKfs.evaluate("opacity", txtSec, 1.0).coerceIn(0.0, 1.0).toFloat()

                                val centerX = (evalX * width).toFloat()
                                val centerY = (evalY * height).toFloat()

                                inputSurface.renderPipOverlay(
                                    textureId = texId,
                                    dstCenterX = centerX,
                                    dstCenterY = centerY,
                                    baseW = bW,
                                    baseH = bH,
                                    scale = evalScale,
                                    rotationRad = evalRotationRad,
                                    opacity = evalOpacity,
                                    flipH = false,
                                    flipV = false
                                )
                            } else {
                                val dstLeft = ((width - bW) * txt.x.toFloat()).coerceIn(0f, (width - bW).coerceAtLeast(0f))
                                val dstTop = ((height - bH) * txt.y.toFloat()).coerceIn(0f, (height - bH).coerceAtLeast(0f))
                                val dstRight = dstLeft + bW
                                val dstBottom = dstTop + bH

                                inputSurface.renderOverlay(texId, dstLeft, dstTop, dstRight, dstBottom)
                            }
                        }
                    }
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

            if (!drainThread.muxerStartedLatch.await(10, java.util.concurrent.TimeUnit.SECONDS)) {
                throw RuntimeException("Encoder drain thread never started muxer")
            }

            drainThread.join(30_000L)
            if (drainThread.isAlive) {
                drainThread.isRunning = false
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
                        val rawSampleTimeUs = audioExtractor.sampleTime
                        val presentationTimeUs = rawSampleTimeUs.coerceAtLeast(0L)
                        if (presentationTimeUs > totalDurationMs * 1000L) {
                            break
                        }
                        audioBufferInfo.presentationTimeUs = presentationTimeUs
                        audioBufferInfo.flags = audioExtractor.sampleFlags
                        if ((audioBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                            muxer.writeSampleData(drainThread.audioTrackIndex, audioBuffer, audioBufferInfo)
                        }
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
            try {
                for ((_, pair) in textTextures) {
                    val textures = intArrayOf(pair.second)
                    GLES20.glDeleteTextures(1, textures, 0)
                    pair.first.recycle()
                }
                textTextures.clear()
            } catch (e: Exception) {}
            try {
                pipTextures.values.forEach { tex ->
                    val textures = intArrayOf(tex)
                    GLES20.glDeleteTextures(1, textures, 0)
                }
                pipTextures.clear()
            } catch (e: Exception) {}
            videoDecoders.values.forEach { it.release() }
            videoDecoders.clear()

            // Now release EGL and input surface
            try { inputSurface.release() } catch (e: Exception) {}
            try { audioExtractor?.release() } catch (e: Exception) {}
            try { tempMixedAudioFile?.delete() } catch (e: Exception) {}
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

    /**
     * Decodes, mixes, normalizes, and AAC-encodes multi-track audio streams (video audio, music, voice, PIP audio)
     * with sample-accurate timeline positioning, volume gain (0-200%), fade-in/out envelopes, and soft-limiter clamping.
     * Returns a Pair of MediaExtractor pointing to the mixed temporary AAC/M4A file and the temporary File itself.
     */
    private fun mixAndEncodeAudio(
        sources: List<AudioSourceSpec>,
        totalDurationMs: Long,
        tempDir: File
    ): Pair<MediaExtractor?, File?> {
        if (sources.isEmpty() || totalDurationMs <= 0L) {
            return Pair(null, null)
        }

        val targetSampleRate = 44100
        val targetChannels = 2 // stereo
        val totalFrames = ((totalDurationMs * targetSampleRate) / 1000L).toInt().coerceAtLeast(1)

        val masterLeft = FloatArray(totalFrames)
        val masterRight = FloatArray(totalFrames)
        var anySourceMixed = false

        for (source in sources) {
            if ((source.volume <= 0.0 && !source.keyframeTracks.hasProperty("volume")) || source.path.isBlank()) continue
            val file = File(source.path)
            if (!file.exists()) continue

            var extractor: MediaExtractor? = null
            var decoder: MediaCodec? = null
            try {
                extractor = MediaExtractor()
                extractor.setDataSource(source.path)

                var audioTrackIdx = -1
                var trackFormat: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val fmt = extractor.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        audioTrackIdx = i
                        trackFormat = fmt
                        break
                    }
                }

                if (audioTrackIdx == -1 || trackFormat == null) {
                    extractor.release()
                    continue
                }

                extractor.selectTrack(audioTrackIdx)
                val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
                val srcSampleRate = if (trackFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    trackFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                } else targetSampleRate
                val srcChannels = if (trackFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    trackFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else 2

                val decodedLeft = ArrayList<Float>()
                val decodedRight = ArrayList<Float>()

                // Seek to trimStart if specified
                if (source.trimStartMs > 0L) {
                    extractor.seekTo(source.trimStartMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                }

                val trimStartUs = source.trimStartMs * 1000L
                val trimEndUs = source.trimEndMs * 1000L

                if (mime == "audio/raw" || mime.contains("pcm")) {
                    // Raw PCM from uncompressed WAV
                    val rawBuffer = ByteBuffer.allocateDirect(16384)
                    while (true) {
                        val sampleSize = extractor.readSampleData(rawBuffer, 0)
                        if (sampleSize < 0) break
                        val pts = extractor.sampleTime
                        if (trimEndUs > 0L && pts > trimEndUs) break

                        if (trimStartUs <= 0L || pts >= trimStartUs) {
                            rawBuffer.position(0)
                            rawBuffer.limit(sampleSize)
                            rawBuffer.order(ByteOrder.LITTLE_ENDIAN)
                            val shortBuf = rawBuffer.asShortBuffer()
                            val numSamples = shortBuf.remaining()
                            if (srcChannels == 1) {
                                for (s in 0 until numSamples) {
                                    val v = shortBuf.get().toFloat()
                                    decodedLeft.add(v)
                                    decodedRight.add(v)
                                }
                            } else if (srcChannels >= 2) {
                                val frames = numSamples / srcChannels
                                for (f in 0 until frames) {
                                    val l = shortBuf.get().toFloat()
                                    val r = shortBuf.get().toFloat()
                                    for (c in 2 until srcChannels) {
                                        shortBuf.get()
                                    }
                                    decodedLeft.add(l)
                                    decodedRight.add(r)
                                }
                            }
                        }
                        extractor.advance()
                    }
                } else {
                    // Compressed audio (AAC, MP3, OGG, Opus, FLAC) decoded via MediaCodec
                    decoder = MediaCodec.createDecoderByType(mime)
                    decoder.configure(trackFormat, null, null, 0)
                    decoder.start()

                    val inBufferInfo = MediaCodec.BufferInfo()
                    var inputEos = false
                    var outputEos = false
                    val timeoutUs = 10_000L

                    while (!outputEos) {
                        if (!inputEos) {
                            val inIdx = decoder.dequeueInputBuffer(timeoutUs)
                            if (inIdx >= 0) {
                                val inBuffer = decoder.getInputBuffer(inIdx)
                                if (inBuffer != null) {
                                    val sampleSize = extractor.readSampleData(inBuffer, 0)
                                    if (sampleSize < 0) {
                                        decoder.queueInputBuffer(inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                        inputEos = true
                                    } else {
                                        val sampleTime = extractor.sampleTime
                                        if (trimEndUs > 0L && sampleTime > trimEndUs + 200_000L) {
                                            decoder.queueInputBuffer(inIdx, 0, 0, sampleTime, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                            inputEos = true
                                        } else {
                                            decoder.queueInputBuffer(inIdx, 0, sampleSize, sampleTime, 0)
                                            extractor.advance()
                                        }
                                    }
                                }
                            }
                        }

                        val outIdx = decoder.dequeueOutputBuffer(inBufferInfo, timeoutUs)
                        if (outIdx >= 0) {
                            if ((inBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                outputEos = true
                            }
                            if (inBufferInfo.size > 0) {
                                val outBuffer = decoder.getOutputBuffer(outIdx)
                                if (outBuffer != null) {
                                    outBuffer.position(inBufferInfo.offset)
                                    outBuffer.limit(inBufferInfo.offset + inBufferInfo.size)
                                    outBuffer.order(ByteOrder.LITTLE_ENDIAN)
                                    val shortBuf = outBuffer.asShortBuffer()
                                    val numSamples = shortBuf.remaining()

                                    val pts = inBufferInfo.presentationTimeUs
                                    if (trimEndUs <= 0L || pts <= trimEndUs) {
                                        if (srcChannels == 1) {
                                            for (s in 0 until numSamples) {
                                                val v = shortBuf.get().toFloat()
                                                decodedLeft.add(v)
                                                decodedRight.add(v)
                                            }
                                        } else if (srcChannels == 2) {
                                            val frames = numSamples / 2
                                            for (f in 0 until frames) {
                                                decodedLeft.add(shortBuf.get().toFloat())
                                                decodedRight.add(shortBuf.get().toFloat())
                                            }
                                        } else {
                                            val frames = numSamples / srcChannels
                                            for (f in 0 until frames) {
                                                val l = shortBuf.get().toFloat()
                                                val r = shortBuf.get().toFloat()
                                                for (c in 2 until srcChannels) {
                                                    shortBuf.get()
                                                }
                                                decodedLeft.add(l)
                                                decodedRight.add(r)
                                            }
                                        }
                                    }
                                }
                            }
                            decoder.releaseOutputBuffer(outIdx, false)
                        } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            // format updated
                        } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER && inputEos) {
                            break
                        }
                    }
                }

                if (decodedLeft.isNotEmpty()) {
                    anySourceMixed = true
                    val srcFrameCount = decodedLeft.size
                    val timelineStartFrame = ((source.timelineStartMs * targetSampleRate) / 1000L).toInt()
                    val clipDurationMs = if (source.trimEndMs > source.trimStartMs) {
                        source.trimEndMs - source.trimStartMs
                    } else {
                        (srcFrameCount * 1000L) / srcSampleRate
                    }
                    val targetDurationFrames = ((clipDurationMs * targetSampleRate) / 1000L).toInt()

                    var fadeInFrames = ((source.fadeInMs * targetSampleRate) / 1000L).toInt()
                    var fadeOutFrames = ((source.fadeOutMs * targetSampleRate) / 1000L).toInt()
                    if (fadeInFrames + fadeOutFrames > targetDurationFrames && targetDurationFrames > 0) {
                        val scale = targetDurationFrames.toDouble() / (fadeInFrames + fadeOutFrames).toDouble()
                        fadeInFrames = (fadeInFrames * scale).toInt()
                        fadeOutFrames = (fadeOutFrames * scale).toInt()
                    }

                    val maxMixFrames = min(targetDurationFrames, totalFrames - timelineStartFrame)

                    for (f in 0 until maxMixFrames) {
                        val masterFrame = timelineStartFrame + f
                        if (masterFrame < 0 || masterFrame >= totalFrames) continue

                        // Sample rate conversion / interpolation
                        val srcIdxFloat = (f.toDouble() * srcSampleRate) / targetSampleRate
                        val srcIdx0 = srcIdxFloat.toInt().coerceIn(0, srcFrameCount - 1)
                        val srcIdx1 = (srcIdx0 + 1).coerceIn(0, srcFrameCount - 1)
                        val frac = (srcIdxFloat - srcIdx0).toFloat()

                        val rawL = decodedLeft[srcIdx0] * (1f - frac) + decodedLeft[srcIdx1] * frac
                        val rawR = decodedRight[srcIdx0] * (1f - frac) + decodedRight[srcIdx1] * frac

                        // Fade envelope
                        var fade = 1.0
                        if (fadeInFrames > 0 && f < fadeInFrames) {
                            fade = (f.toDouble() / fadeInFrames).coerceIn(0.0, 1.0)
                        } else if (fadeOutFrames > 0 && f > (targetDurationFrames - fadeOutFrames)) {
                            fade = ((targetDurationFrames - f).toDouble() / fadeOutFrames).coerceIn(0.0, 1.0)
                        }

                        val sampleSec = f.toDouble() / targetSampleRate.toDouble()
                        val baseVolume = if (source.keyframeTracks.hasProperty("volume")) {
                            source.keyframeTracks.evaluate("volume", sampleSec, source.volume)
                        } else {
                            source.volume
                        }
                        val gain = (baseVolume * fade).toFloat()
                        masterLeft[masterFrame] += rawL * gain
                        masterRight[masterFrame] += rawR * gain
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Audio source decode error for ${source.path}: ${e.message}")
            } finally {
                try {
                    decoder?.stop()
                    decoder?.release()
                } catch (_: Exception) {}
                try {
                    extractor?.release()
                } catch (_: Exception) {}
            }
        }

        if (!anySourceMixed) {
            return Pair(null, null)
        }

        // Convert master floating point samples to 16-bit PCM ShortArray with limiter / soft clamping
        val masterPcm = ShortArray(totalFrames * 2)
        for (i in 0 until totalFrames) {
            val l = masterLeft[i].coerceIn(-32768f, 32767f).toInt().toShort()
            val r = masterRight[i].coerceIn(-32768f, 32767f).toInt().toShort()
            masterPcm[i * 2] = l
            masterPcm[i * 2 + 1] = r
        }

        // Encode master PCM into temporary AAC/M4A file
        var tempM4aFile: File? = null
        var mixedExtractor: MediaExtractor? = null
        try {
            tempM4aFile = File.createTempFile("export_mixed_audio_", ".m4a", tempDir)
            val audioMuxer = MediaMuxer(tempM4aFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val aacFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, targetSampleRate, targetChannels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 192000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
            }

            val aacEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            aacEncoder.configure(aacFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            aacEncoder.start()

            var audioTrackIndex = -1
            var audioMuxerStarted = false
            val bufferInfo = MediaCodec.BufferInfo()

            var pcmShortOffset = 0
            val totalShorts = masterPcm.size
            val shortsPerChunk = 2048 // 1024 stereo frames
            var encodeEos = false

            while (!encodeEos) {
                // Feed PCM input
                if (pcmShortOffset < totalShorts) {
                    val inIdx = aacEncoder.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val inBuf = aacEncoder.getInputBuffer(inIdx)
                        if (inBuf != null) {
                            inBuf.clear()
                            val count = min(shortsPerChunk, totalShorts - pcmShortOffset)
                            inBuf.order(ByteOrder.LITTLE_ENDIAN)
                            for (k in 0 until count) {
                                inBuf.putShort(masterPcm[pcmShortOffset + k])
                            }
                            val ptsUs = ((pcmShortOffset / 2).toLong() * 1_000_000L) / targetSampleRate
                            pcmShortOffset += count
                            val flags = if (pcmShortOffset >= totalShorts) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                            aacEncoder.queueInputBuffer(inIdx, 0, count * 2, ptsUs, flags)
                        }
                    }
                }

                // Drain AAC output
                val outStatus = aacEncoder.dequeueOutputBuffer(bufferInfo, 10_000L)
                if (outStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (!audioMuxerStarted) {
                        audioTrackIndex = audioMuxer.addTrack(aacEncoder.outputFormat)
                        audioMuxer.start()
                        audioMuxerStarted = true
                    }
                } else if (outStatus >= 0) {
                    val outBuf = aacEncoder.getOutputBuffer(outStatus)
                    if (outBuf != null && bufferInfo.size > 0 && audioMuxerStarted) {
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                            outBuf.position(bufferInfo.offset)
                            outBuf.limit(bufferInfo.offset + bufferInfo.size)
                            audioMuxer.writeSampleData(audioTrackIndex, outBuf, bufferInfo)
                        }
                    }
                    aacEncoder.releaseOutputBuffer(outStatus, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        encodeEos = true
                    }
                }
            }

            try {
                aacEncoder.stop()
                aacEncoder.release()
            } catch (_: Exception) {}

            try {
                if (audioMuxerStarted) {
                    audioMuxer.stop()
                }
                audioMuxer.release()
            } catch (_: Exception) {}

            // Open extractor on the generated M4A file
            val ext = MediaExtractor()
            ext.setDataSource(tempM4aFile.absolutePath)
            var found = false
            for (i in 0 until ext.trackCount) {
                val fmt = ext.getTrackFormat(i)
                val m = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                if (m.startsWith("audio/")) {
                    ext.selectTrack(i)
                    found = true
                    break
                }
            }

            if (found) {
                mixedExtractor = ext
                Log.i(TAG, "Multi-track audio mix & AAC encode completed: ${masterPcm.size / 2} frames (${totalDurationMs}ms)")
            } else {
                ext.release()
                tempM4aFile.delete()
                tempM4aFile = null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mix and encode audio: ${e.message}", e)
            try {
                tempM4aFile?.delete()
            } catch (_: Exception) {}
            tempM4aFile = null
        }

        return Pair(mixedExtractor, tempM4aFile)
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
