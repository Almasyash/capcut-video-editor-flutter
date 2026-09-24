import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/audio_beat_service.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// CapCut-style Match Cut & Audio Beat Options Modal Bottom Sheet
class BeatOptionsSheet extends StatelessWidget {
  final EditorViewModel viewModel;
  final AudioTrack audioTrack;

  const BeatOptionsSheet({
    super.key,
    required this.viewModel,
    required this.audioTrack,
  });

  static Future<void> show(BuildContext context, EditorViewModel viewModel) async {
    final track = viewModel.selectedAudioTrack;
    if (track == null) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final liveTrack = viewModel.audioTracks.firstWhere(
            (t) => t.id == track.id,
            orElse: () => track,
          );
          return BeatOptionsSheet(viewModel: viewModel, audioTrack: liveTrack);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final beatCount = audioTrack.beats.length;
    final visibleBeats = audioTrack.visibleTimelineBeats;

    // Check if playhead is currently within 0.12s of an existing beat
    final playheadPos = viewModel.playheadPosition;
    final isNearBeat = audioTrack.showBeats &&
        visibleBeats.any((b) => (b - playheadPos).abs() <= 0.12);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: Title, Track Name, and Beat Count Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFFFFD600), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Match Cut / Beats',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          audioTrack.title,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: beatCount > 0
                        ? const Color(0xFFFFD600).withOpacity(0.2)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: beatCount > 0 ? const Color(0xFFFFD600) : AppColors.divider,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: beatCount > 0 ? const Color(0xFFFFD600) : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$beatCount Beats',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: beatCount > 0 ? const Color(0xFFFFD600) : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Section 1: Auto Beat Generation
            const Text(
              'AUTO GENERATE BEATS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _buildAutoBeatButton(
                    context: context,
                    icon: Icons.flash_on_rounded,
                    title: 'Beat 1',
                    subtitle: 'Strong Drops',
                    onTap: () {
                      viewModel.generateBeatsForTrack(
                        audioTrack.id,
                        sensitivity: BeatSensitivity.strongDownbeats,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildAutoBeatButton(
                    context: context,
                    icon: Icons.electric_bolt_rounded,
                    title: 'Beat 2',
                    subtitle: 'Fast Tempo',
                    onTap: () {
                      viewModel.generateBeatsForTrack(
                        audioTrack.id,
                        sensitivity: BeatSensitivity.fastBeats,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: beatCount > 0 ? () => viewModel.clearBeatsForTrack(audioTrack.id) : null,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: beatCount > 0 ? AppColors.error : AppColors.textMuted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: beatCount > 0 ? AppColors.error : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 2: Manual Rhythm Tapper & Audition
            const Text(
              'MANUAL RHYTHM TAPPER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  // Play / Pause preview button
                  IconButton.filled(
                    onPressed: () {
                      if (viewModel.isPlaying) {
                        viewModel.pause();
                      } else {
                        viewModel.play();
                      }
                    },
                    icon: Icon(
                      viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Large Add / Delete Beat button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => viewModel.toggleBeatAtPlayhead(audioTrack.id),
                      icon: Icon(
                        isNearBeat ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                        size: 20,
                        color: isNearBeat ? Colors.white : Colors.black,
                      ),
                      label: Text(
                        isNearBeat ? 'Delete Beat' : '+ Add Beat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isNearBeat ? Colors.white : Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isNearBeat ? AppColors.error : const Color(0xFFFFD600),
                        foregroundColor: isNearBeat ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Section 3: Magnetic Snapping & Visibility Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  // Magnetic Snap Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.adjust_rounded, size: 18, color: Color(0xFFFFD600)),
                          SizedBox(width: 8),
                          Text(
                            'Magnetic Snap to Beats',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: viewModel.isSnapToBeatEnabled,
                        activeColor: const Color(0xFFFFD600),
                        onChanged: (val) => viewModel.toggleSnapToBeat(val),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.divider, height: 1),

                  // Show Markers Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.visibility_rounded, size: 18, color: AppColors.textSecondary),
                          SizedBox(width: 8),
                          Text(
                            'Show Waveform Beat Dots',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: audioTrack.showBeats,
                        activeColor: const Color(0xFFFFD600),
                        onChanged: (_) => viewModel.toggleBeatsVisibility(audioTrack.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoBeatButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD600).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFFFFD600)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
