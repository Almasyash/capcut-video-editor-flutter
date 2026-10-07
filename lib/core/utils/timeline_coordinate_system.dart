import 'dart:math' as math;
import 'time_formatter.dart';

/// Centralized, deterministic coordinate and time conversion system for Editor FS.
/// Provides frame-aware time-to-pixel and pixel-to-time conversions,
/// boundary calculations, frame snapping, and timecode formatting.
class TimelineCoordinateSystem {
  TimelineCoordinateSystem._();

  /// Converts a timeline timestamp in seconds to horizontal pixel offset X.
  static double timeToPixel(double timeInSeconds, double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return 0.0;
    return math.max(0.0, timeInSeconds) * pixelsPerSecond;
  }

  /// Converts a horizontal pixel offset X to timeline time in seconds.
  static double pixelToTime(double pixelX, double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return 0.0;
    return math.max(0.0, pixelX) / pixelsPerSecond;
  }

  /// Converts timeline time in seconds to discrete frame number at given FPS.
  static int timeToFrame(double timeInSeconds, {double fps = 30.0}) {
    if (fps <= 0) return 0;
    return (math.max(0.0, timeInSeconds) * fps).round();
  }

  /// Converts discrete frame number to timeline time in seconds.
  static double frameToTime(int frame, {double fps = 30.0}) {
    if (fps <= 0 || frame <= 0) return 0.0;
    return frame / fps;
  }

  /// Snaps a timestamp in seconds to the nearest exact video frame boundary.
  static double snapToFrame(double timeInSeconds, {double fps = 30.0}) {
    if (fps <= 0 || timeInSeconds <= 0.0) return 0.0;
    final frame = (timeInSeconds * fps).round();
    return frame / fps;
  }

  /// Formats a time in seconds into frame-aware timecode string: `00:00:12 @ 30fps` or `00:00.00`.
  static String formatFrameTimecode(double timeInSeconds, {double fps = 30.0, bool showFpsBadge = false}) {
    final frameTick = TimeFormatter.formatRulerFrameTick(timeInSeconds, fps: fps.round());
    if (showFpsBadge) {
      return '$frameTick @ ${fps.round()}fps';
    }
    return frameTick;
  }

  /// Snaps a target time to the nearest boundary if within the snap threshold (in seconds).
  static double snapToNearestBoundary(
    double timeInSeconds,
    List<double> boundaryTimestamps, {
    double thresholdSeconds = 0.08,
  }) {
    if (boundaryTimestamps.isEmpty) return timeInSeconds;

    double closest = timeInSeconds;
    double minDiff = double.infinity;

    for (final boundary in boundaryTimestamps) {
      final diff = (timeInSeconds - boundary).abs();
      if (diff < minDiff && diff <= thresholdSeconds) {
        minDiff = diff;
        closest = boundary;
      }
    }

    return closest;
  }

  /// Clamps timestamp between 0.0 and project duration.
  static double clampTime(double timeInSeconds, double maxDurationSeconds) {
    return timeInSeconds.clamp(0.0, math.max(0.0, maxDurationSeconds));
  }

  /// Clamps pixel offset between 0.0 and maximum canvas width.
  static double clampPixel(double pixelX, double maxPixelWidth) {
    return pixelX.clamp(0.0, math.max(0.0, maxPixelWidth));
  }

  /// Calculates clamped zoom level (`pixelsPerSecond`).
  static double clampZoom(double pps, {double min = 20.0, double max = 600.0}) {
    return pps.clamp(min, max);
  }
}
