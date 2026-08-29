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
    final isSelected = (viewModel.selectedAudioTrackId == audioTrack.id) ||
        (viewModel.isAudioSelected && viewModel.audioTracks.length == 1);
    final audioAsset = viewModel.getAssetById(audioTrack.assetId);
    final hasLocalAudio = audioAsset?.localPath != null &&
        !audioAsset!.localPath!.startsWith('content://');

    return Container(
      margin: EdgeInsets.only(left: startOffset, top: 4.0, bottom: 4.0),
      width: trackWidth,
      height: AppDimensions.audioTrackHeight,
      child: GestureDetector(
        onTap: () => viewModel.selectAudioTrack(audioTrack.id),
        onHorizontalDragUpdate: (details) {
          // Middle drag: slide audio track position across timeline
          final deltaSeconds = details.primaryDelta! / pixelsPerSecond;
          final newStartSec = math.max(0.0, audioTrack.startTimeInSeconds + deltaSeconds);
          viewModel.updateAudioTrackTiming(
            Duration(milliseconds: (newStartSec * 1000).round()),
            audioTrack.duration,
            id: audioTrack.id,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.audioTrackBg,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.selectionBorder : AppColors.primary.withValues(alpha: 0.3),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.selectionBorder.withValues(alpha: 0.3),
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
                      color: audioTrack.isMuted
                          ? AppColors.textMuted.withValues(alpha: 0.3)
                          : AppColors.audioTrackWaveform.withValues(alpha: 0.6),
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
                    Icon(
                      audioTrack.isMuted ? Icons.volume_off_rounded : Icons.music_note_rounded,
                      size: 13,
                      color: audioTrack.isMuted ? AppColors.error : AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${audioTrack.title} • ${audioTrack.speed > 1.05 || audioTrack.speed < 0.95 ? '${audioTrack.speed.toStringAsFixed(1)}x • ' : ''}${audioTrack.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: audioTrack.isMuted ? AppColors.textMuted : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      audioTrack.isMuted ? 'MUTED' : '${(audioTrack.volume * 100).round()}%',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: audioTrack.isMuted ? AppColors.error : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Real Local Audio indicator
              if (hasLocalAudio)
                Positioned(
                  bottom: 2,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sd_storage_rounded, size: 8, color: AppColors.secondary),
                        SizedBox(width: 2),
                        Text('LOCAL AUDIO', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: AppColors.secondary)),
                      ],
                    ),
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
                      final currentTrimEnd = audioTrack.effectiveTrimEnd;
                      final deltaSec = dx / pixelsPerSecond;
                      final sourceDeltaMs = (deltaSec * audioTrack.speed * 1000).round();
                      final newTrimStartMs = (audioTrack.trimStart.inMilliseconds + sourceDeltaMs)
                          .clamp(0, currentTrimEnd.inMilliseconds - 300)
                          .toInt();
                      final actualAppliedDeltaMs = newTrimStartMs - audioTrack.trimStart.inMilliseconds;
                      final timelineDeltaSec = actualAppliedDeltaMs / 1000.0 / audioTrack.speed;
                      final newStartSec = math.max(0.0, audioTrack.startTimeInSeconds + timelineDeltaSec);

                      viewModel.updateAudioTrim(
                        audioTrack.id,
                        Duration(milliseconds: newTrimStartMs),
                        currentTrimEnd,
                      );
                      viewModel.updateAudioTrackTiming(
                        Duration(milliseconds: (newStartSec * 1000).round()),
                        audioTrack.duration,
                        id: audioTrack.id,
                      );
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
                      final currentTrimEnd = audioTrack.effectiveTrimEnd;
                      final deltaSec = dx / pixelsPerSecond;
                      final sourceDeltaMs = (deltaSec * audioTrack.speed * 1000).round();
                      final newTrimEndMs = (currentTrimEnd.inMilliseconds + sourceDeltaMs)
                          .clamp(audioTrack.trimStart.inMilliseconds + 300, audioTrack.duration.inMilliseconds)
                          .toInt();

                      viewModel.updateAudioTrim(
                        audioTrack.id,
                        audioTrack.trimStart,
                        Duration(milliseconds: newTrimEndMs),
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
