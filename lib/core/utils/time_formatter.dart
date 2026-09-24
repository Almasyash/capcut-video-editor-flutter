/// Utility to format durations and seconds into standard CapCut timecode strings.
class TimeFormatter {
  TimeFormatter._();

  /// Formats duration into `mm:ss` or `mm:ss.SS` (hundredths of a second).
  /// Example: 4.12 seconds -> `00:04.12`
  static String formatTimecode(Duration duration, {bool showMilliseconds = true}) {
    final totalMilliseconds = duration.inMilliseconds;
    if (totalMilliseconds < 0) return '00:00.00';

    final minutes = (totalMilliseconds ~/ (1000 * 60)).toString().padLeft(2, '0');
    final seconds = ((totalMilliseconds % (1000 * 60)) ~/ 1000).toString().padLeft(2, '0');

    if (!showMilliseconds) {
      return '$minutes:$seconds';
    }

    final hundredths = ((totalMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$hundredths';
  }

  /// Formats a double in seconds into `mm:ss.SS`
  static String formatSeconds(double seconds, {bool showMilliseconds = true}) {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    return formatTimecode(duration, showMilliseconds: showMilliseconds);
  }

  /// Formats duration for ruler tick display (e.g., `00:05`, `00:10`, `01:00`)
  static String formatRulerTick(double seconds) {
    final totalSeconds = seconds.floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  /// Formats duration for frame-level ruler tick display at high zoom levels (e.g. `00:01:15`, `00:02:00`)
  static String formatRulerFrameTick(double seconds, {int fps = 30}) {
    final totalFrames = (seconds * fps).round();
    final secs = totalFrames ~/ fps;
    final frame = totalFrames % fps;
    final minutes = secs ~/ 60;
    final remSecs = secs % 60;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = remSecs.toString().padLeft(2, '0');
    final frameStr = frame.toString().padLeft(2, '0');
    return '$minStr:$secStr:$frameStr';
  }
}
