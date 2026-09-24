import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/audio_waveform_service.dart';
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

    // Compute active playhead progress through this specific audio clip (0.0 to 1.0)
    final trackStartSec = audioTrack.startTimeInSeconds;
    final trackEndSec = audioTrack.endTimeInSeconds;
    final currentPlayhead = viewModel.playheadPosition;
    double playheadProgress = 0.0;
    if (currentPlayhead <= trackStartSec) {
      playheadProgress = 0.0;
    } else if (currentPlayhead >= trackEndSec) {
      playheadProgress = 1.0;
    } else {
      final activeSec = trackEndSec - trackStartSec;
      playheadProgress = activeSec > 0 ? ((currentPlayhead - trackStartSec) / activeSec).clamp(0.0, 1.0) : 0.0;
    }

    return Container(
      margin: EdgeInsets.only(left: startOffset, top: 4.0, bottom: 4.0),
      width: trackWidth,
      height: AppDimensions.audioTrackHeight,
      child: GestureDetector(
        onTap: () => viewModel.selectAudioTrack(audioTrack.id),
        onTapDown: (details) {
          if (viewModel.isPlaying) viewModel.pause();
          viewModel.selectAudioTrack(audioTrack.id);
          final targetTime = (audioTrack.startTimeInSeconds + (details.localPosition.dx / pixelsPerSecond))
              .clamp(0.0, viewModel.totalDurationInSeconds);
          viewModel.seekTo(targetTime);
        },
        onHorizontalDragUpdate: (details) {
          // Middle drag: slide audio track position across timeline
          final deltaSeconds = details.primaryDelta! / pixelsPerSecond;
          final newStartSec = math.max(0.0, audioTrack.startTimeInSeconds + deltaSeconds);
          viewModel.moveAudioTrack(
            audioTrack.id,
            Duration(milliseconds: (newStartSec * 1000).round()),
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
              // 1. Audio Waveform Visualization (Trim-accurate, zoom-adaptive, volume-responsive)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      points: audioTrack.waveformPoints,
                      trimStart: audioTrack.trimStart,
                      trimEnd: audioTrack.effectiveTrimEnd,
                      totalDuration: audioTrack.duration,
                      volume: audioTrack.volume,
                      speed: audioTrack.speed,
                      beats: audioTrack.beats,
                      showBeats: audioTrack.showBeats,
                      isMuted: audioTrack.isMuted,
                      playheadProgress: playheadProgress,
                      activeColor: AppColors.audioTrackWaveform,
                      unplayedColor: AppColors.audioTrackWaveform.withOpacity(0.55),
                      mutedColor: AppColors.textMuted.withOpacity(0.3),
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

              // 3. Left & Right Interactive Amber Trim Handles when Selected (preserving timeline startTime)
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
                          .clamp(0, currentTrimEnd.inMilliseconds - 200)
                          .toInt();

                      viewModel.updateAudioTrim(
                        audioTrack.id,
                        Duration(milliseconds: newTrimStartMs),
                        currentTrimEnd,
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
                          .clamp(audioTrack.trimStart.inMilliseconds + 200, audioTrack.duration.inMilliseconds)
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
  final Duration trimStart;
  final Duration trimEnd;
  final Duration totalDuration;
  final double volume;
  final double speed;
  final List<double> beats;
  final bool showBeats;
  final bool isMuted;
  final double playheadProgress;
  final Color activeColor;
  final Color unplayedColor;
  final Color mutedColor;

  _WaveformPainter({
    required this.points,
    this.trimStart = Duration.zero,
    Duration? trimEnd,
    Duration? totalDuration,
    this.volume = 1.0,
    this.speed = 1.0,
    this.beats = const [],
    this.showBeats = true,
    this.isMuted = false,
    this.playheadProgress = 0.0,
    Color? color,
    Color? activeColor,
    Color? unplayedColor,
    Color? mutedColor,
  })  : trimEnd = trimEnd ?? totalDuration ?? const Duration(seconds: 30),
        totalDuration = totalDuration ?? trimEnd ?? const Duration(seconds: 30),
        activeColor = activeColor ?? color ?? AppColors.audioTrackWaveform,
        unplayedColor = unplayedColor ?? (color ?? AppColors.audioTrackWaveform).withOpacity(0.55),
        mutedColor = mutedColor ?? AppColors.textMuted.withOpacity(0.3);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;

    // 1. Muted or Zero Volume Baseline
    if (isMuted || volume <= 0.001) {
      final linePaint = Paint()
        ..color = mutedColor
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);
      return;
    }

    // 2. Compute Physical Bar Layout (Constant 3.5px step for sleek density)
    const barWidth = 2.0;
    const barGap = 1.5;
    const barStep = barWidth + barGap;
    final barCount = (size.width / barStep).floor();
    if (barCount <= 0) return;

    // 3. Sliced & Zoom-Adaptive Resampling
    final effectivePoints = points.isEmpty
        ? AudioWaveformService.instance.generateOrganicWaveform(seedKey: 'fallback_${size.width.toInt()}')
        : points;

    final resampled = AudioWaveformService.instance.resampleSlicedWaveform(
      fullWaveform: effectivePoints,
      trimStart: trimStart,
      trimEnd: trimEnd,
      totalDuration: totalDuration,
      barCount: barCount,
    );

    // 4. Dual-State Paint Setup
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final unplayedPaint = Paint()
      ..color = unplayedColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final playheadX = (playheadProgress.clamp(0.0, 1.0) * size.width);

    // 5. Draw Symmetrical Waveform Bars
    final availableHalfHeight = (size.height / 2) - 2.0;
    final effectiveVolume = volume.clamp(0.0, 1.0);

    for (int i = 0; i < barCount; i++) {
      final x = i * barStep + (barWidth / 2);
      final rawAmp = resampled[i];
      final scaledAmp = (rawAmp * effectiveVolume).clamp(0.04, 1.0);
      final halfBarHeight = math.max(1.5, scaledAmp * availableHalfHeight);

      final isPlayed = x <= playheadX;
      final paint = isPlayed ? activePaint : unplayedPaint;

      canvas.drawLine(
        Offset(x, centerY - halfBarHeight),
        Offset(x, centerY + halfBarHeight),
        paint,
      );
    }

    // 6. Draw Golden Beat Markers (CapCut Match Cut Style)
    if (showBeats && beats.isNotEmpty) {
      final startSec = trimStart.inMilliseconds / 1000.0;
      final endSec = trimEnd.inMilliseconds / 1000.0;
      final speedFactor = speed > 0 ? speed : 1.0;
      final effectiveDurationSec = (endSec - startSec) / speedFactor;

      if (effectiveDurationSec > 0.0) {
        final beatDotPaint = Paint()
          ..color = const Color(0xFFFFD600) // Vibrant Gold/Yellow
          ..style = PaintingStyle.fill;

        final beatBorderPaint = Paint()
          ..color = Colors.black87
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

        final beatGuidelinePaint = Paint()
          ..color = const Color(0xFFFFD600).withOpacity(0.35)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;

        final pulsePaint = Paint()
          ..color = const Color(0xFFFFEA00).withOpacity(0.6)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        for (final b in beats) {
          if (b >= startSec && b <= endSec) {
            final relativeSec = (b - startSec) / speedFactor;
            final fraction = (relativeSec / effectiveDurationSec).clamp(0.0, 1.0);
            final beatX = fraction * size.width;

            // Vertical guideline across track height
            canvas.drawLine(
              Offset(beatX, 2),
              Offset(beatX, size.height - 2),
              beatGuidelinePaint,
            );

            // Active pulse ring if playhead is currently close to this beat
            final isNearPlayhead = (beatX - playheadX).abs() <= 6.0;
            if (isNearPlayhead) {
              canvas.drawCircle(Offset(beatX, centerY), 6.0, pulsePaint);
            }

            // Central Beat Dot
            canvas.drawCircle(Offset(beatX, centerY), 3.2, beatDotPaint);
            canvas.drawCircle(Offset(beatX, centerY), 3.2, beatBorderPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.trimStart != trimStart ||
        oldDelegate.trimEnd != trimEnd ||
        oldDelegate.totalDuration != totalDuration ||
        oldDelegate.volume != volume ||
        oldDelegate.speed != speed ||
        oldDelegate.beats != beats ||
        oldDelegate.showBeats != showBeats ||
        oldDelegate.isMuted != isMuted ||
        (oldDelegate.playheadProgress - playheadProgress).abs() > 0.005 ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.unplayedColor != unplayedColor;
  }
}
