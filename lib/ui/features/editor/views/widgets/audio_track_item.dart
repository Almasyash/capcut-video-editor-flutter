import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';

/// Audio track timeline item with rendered waveform visualizer
class AudioTrackItem extends StatelessWidget {
  final AudioTrack audioTrack;
  final double pixelsPerSecond;

  const AudioTrackItem({
    super.key,
    required this.audioTrack,
    required this.pixelsPerSecond,
  });

  @override
  Widget build(BuildContext context) {
    final trackWidth = audioTrack.durationInSeconds * pixelsPerSecond;
    final startOffset = audioTrack.startTimeInSeconds * pixelsPerSecond;

    return Container(
      margin: EdgeInsets.only(left: startOffset, top: 4.0, bottom: 4.0),
      width: trackWidth,
      height: AppDimensions.audioTrackHeight,
      decoration: BoxDecoration(
        color: AppColors.audioTrackBg,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Stack(
        children: [
          // Audio Waveform Visualization
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: CustomPaint(
                painter: _WaveformPainter(
                  points: audioTrack.waveformPoints,
                  color: AppColors.audioTrackWaveform.withOpacity(0.6),
                ),
              ),
            ),
          ),

          // Title & Music Info Overlay
          Positioned(
            top: 4,
            left: 8,
            right: 8,
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${audioTrack.name} • ${audioTrack.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${(audioTrack.volume * 100).round()}%',
                  style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  _WaveformPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final step = size.width / (points.length * 2);
    final centerY = size.height / 2;

    for (int i = 0; i < points.length; i++) {
      final x = i * step * 2 + step;
      final barHeight = (points[i] * size.height * 0.7).clamp(4.0, size.height);

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
