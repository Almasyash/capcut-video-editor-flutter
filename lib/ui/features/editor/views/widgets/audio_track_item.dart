import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Interactive Audio Track timeline item with rendered waveform visualizer,
/// drag-to-slide positioning, and Left/Right amber trim handles.
class AudioTrackItem extends StatelessWidget {
  final AudioTrack audioTrack;
  final double pixelsPerSecond;
  final EditorViewModel viewModel;

  const AudioTrackItem({
    super.key,
    required this.audioTrack,
    required this.pixelsPerSecond,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final trackWidth = math.max(40.0, audioTrack.durationInSeconds * pixelsPerSecond);
    final startOffset = audioTrack.startTimeInSeconds * pixelsPerSecond;
    final isSelected = viewModel.isAudioSelected;

    return Container(
      margin: EdgeInsets.only(left: startOffset, top: 4.0, bottom: 4.0),
      width: trackWidth,
      height: AppDimensions.audioTrackHeight,
      child: GestureDetector(
        onTap: viewModel.selectAudio,
        onHorizontalDragUpdate: (details) {
          // Middle drag: slide audio track position across timeline
          final deltaSeconds = details.primaryDelta! / pixelsPerSecond;
          final newStartSec = math.max(0.0, audioTrack.startTimeInSeconds + deltaSeconds);
          viewModel.updateAudioTrackTiming(
            Duration(milliseconds: (newStartSec * 1000).round()),
            audioTrack.duration,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.audioTrackBg,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.selectionBorder : AppColors.primary.withOpacity(0.3),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.selectionBorder.withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // 1. Audio Waveform Visualization
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      points: audioTrack.waveformPoints,
                      color: AppColors.audioTrackWaveform.withOpacity(0.6),
                    ),
                  ),
                ),
              ),

              // 2. Title & Music Info Overlay
              Positioned(
                top: 4,
                left: 14,
                right: 14,
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

              // 3. Left & Right Interactive Amber Trim Handles when Selected
              if (isSelected) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildTrimHandle(
                    isLeft: true,
                    onDrag: (dx) {
                      final deltaSec = dx / pixelsPerSecond;
                      final currentStartSec = audioTrack.startTimeInSeconds;
                      final currentDurationSec = audioTrack.durationInSeconds;

                      final newStartSec = math.max(0.0, currentStartSec + deltaSec);
                      final newDurationSec = currentDurationSec - (newStartSec - currentStartSec);

                      if (newDurationSec >= 0.5) {
                        viewModel.updateAudioTrackTiming(
                          Duration(milliseconds: (newStartSec * 1000).round()),
                          Duration(milliseconds: (newDurationSec * 1000).round()),
                        );
                      }
                    },
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildTrimHandle(
                    isLeft: false,
                    onDrag: (dx) {
                      final deltaSec = dx / pixelsPerSecond;
                      final newDurationSec = math.max(0.5, audioTrack.durationInSeconds + deltaSec);
                      viewModel.updateAudioTrackTiming(
                        audioTrack.startTime,
                        Duration(milliseconds: (newDurationSec * 1000).round()),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimHandle({required bool isLeft, required ValueChanged<double> onDrag}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        onDrag(details.primaryDelta ?? 0.0);
      },
      child: Container(
        width: 14,
        decoration: BoxDecoration(
          color: AppColors.trimHandle,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(AppDimensions.radiusSm) : Radius.zero,
            right: !isLeft ? const Radius.circular(AppDimensions.radiusSm) : Radius.zero,
          ),
        ),
        child: Center(
          child: Container(
            width: 2,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
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
