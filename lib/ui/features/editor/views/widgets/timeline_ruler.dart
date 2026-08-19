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
    final effectiveDuration = (totalDurationSeconds < 5.0) ? 10.0 : totalDurationSeconds + 5.0;
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

    // Interval between major ticks (seconds)
    double majorInterval = 1.0;
    if (pixelsPerSecond < 30) {
      majorInterval = 5.0;
    } else if (pixelsPerSecond < 60) {
      majorInterval = 2.0;
    } else {
      majorInterval = 1.0;
    }

    final totalSeconds = totalDuration.ceil();
    for (double sec = 0; sec <= totalSeconds; sec += majorInterval) {
      final x = sec * pixelsPerSecond;

      // Draw Major Tick
      canvas.drawLine(
        Offset(x, size.height - 10),
        Offset(x, size.height),
        tickPaint,
      );

      // Draw Time Text
      final timeStr = TimeFormatter.formatRulerTick(sec);
      final textSpan = TextSpan(text: timeStr, style: AppTypography.rulerTick);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x + 3, 2));

      // Draw Sub Ticks (4 divisions per major interval)
      final subInterval = majorInterval / 5;
      for (int i = 1; i < 5; i++) {
        final subSec = sec + (i * subInterval);
        final subX = subSec * pixelsPerSecond;
        if (subX <= size.width) {
          canvas.drawLine(
            Offset(subX, size.height - 5),
            Offset(subX, size.height),
            subTickPaint,
          );
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
