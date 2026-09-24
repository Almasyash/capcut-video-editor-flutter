import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';

/// Timeline Ruler widget rendering tick marks and second labels matching the zoom scale
class TimelineRuler extends StatelessWidget {
  final double totalDurationSeconds;
  final double pixelsPerSecond;

  const TimelineRuler({
    super.key,
    required this.totalDurationSeconds,
    required this.pixelsPerSecond,
  });

  @override
  Widget build(BuildContext context) {
    // When project has clips, ruler matches exact media duration. For empty project, default to 5.0s placeholder.
    final effectiveDuration = (totalDurationSeconds <= 0.0) ? 5.0 : totalDurationSeconds;
    final totalWidth = effectiveDuration * pixelsPerSecond;

    return Container(
      height: AppDimensions.timelineRulerHeight,
      width: totalWidth,
      color: AppColors.timelineRulerBg,
      child: CustomPaint(
        size: Size(totalWidth, AppDimensions.timelineRulerHeight),
        painter: _TimelineRulerPainter(
          totalDuration: effectiveDuration,
          pixelsPerSecond: pixelsPerSecond,
        ),
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  final double totalDuration;
  final double pixelsPerSecond;

  _TimelineRulerPainter({
    required this.totalDuration,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = AppColors.timelineRulerTick
      ..strokeWidth = 1.0;

    final subTickPaint = Paint()
      ..color = AppColors.timelineRulerTick.withOpacity(0.4)
      ..strokeWidth = 0.8;

    // Interval between major ticks (seconds) and sub-ticks (frame precision)
    double majorInterval = 1.0;
    int subDivisions = 5;
    bool isFrameMode = false;

    if (pixelsPerSecond < 30) {
      majorInterval = 5.0;
      subDivisions = 5;
    } else if (pixelsPerSecond < 60) {
      majorInterval = 2.0;
      subDivisions = 4;
    } else if (pixelsPerSecond < 180) {
      majorInterval = 1.0;
      subDivisions = 5;
    } else if (pixelsPerSecond < 350) {
      // 10-frame intervals (~0.33s), sub-tick per single frame
      majorInterval = 10 / 30.0;
      subDivisions = 10;
      isFrameMode = true;
    } else {
      // Maximum zoom: 5-frame intervals (~0.16s), sub-tick per single frame
      majorInterval = 5 / 30.0;
      subDivisions = 5;
      isFrameMode = true;
    }

    for (double sec = 0; sec <= totalDuration + 1e-4; sec += majorInterval) {
      final x = sec * pixelsPerSecond;
      if (x > size.width + 1.0) break;

      // Draw Major Tick
      canvas.drawLine(
        Offset(x, size.height - (isFrameMode ? 12 : 10)),
        Offset(x, size.height),
        tickPaint,
      );

      // Draw Time Text (frames at high zoom, seconds at standard zoom)
      final timeStr = isFrameMode
          ? TimeFormatter.formatRulerFrameTick(sec)
          : TimeFormatter.formatRulerTick(sec);
      final textSpan = TextSpan(
        text: timeStr,
        style: isFrameMode
            ? AppTypography.rulerTick.copyWith(fontSize: 8.5, color: AppColors.primary)
            : AppTypography.rulerTick,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x + 3, 2));

      // Draw Sub Ticks (frame divisions)
      final subInterval = majorInterval / subDivisions;
      for (int i = 1; i < subDivisions; i++) {
        final subSec = sec + (i * subInterval);
        if (subSec <= totalDuration + 1e-4) {
          final subX = subSec * pixelsPerSecond;
          if (subX <= size.width) {
            canvas.drawLine(
              Offset(subX, size.height - (isFrameMode ? 6 : 5)),
              Offset(subX, size.height),
              subTickPaint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.totalDuration != totalDuration ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}
