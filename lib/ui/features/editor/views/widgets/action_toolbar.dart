import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'export_modal_sheet.dart';

/// Middle Action Toolbar containing Split, Trim Left/Right, Delete, Duplicate, Speed, Volume, Add Clip, and Export.
class ActionToolbar extends StatelessWidget {
  final EditorViewModel viewModel;

  const ActionToolbar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final hasSelectedClip = viewModel.selectedClip != null;

    return Container(
      height: AppDimensions.actionToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.8),
          bottom: BorderSide(color: AppColors.divider, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // 1. Play / Pause Quick Toggle
          _buildPlayPauseButton(),

          const SizedBox(width: 4),
          const VerticalDivider(color: AppColors.divider, indent: 14, endIndent: 14),
          const SizedBox(width: 4),

          // 2. Scrollable Action Buttons (Split, Trim, Delete, Speed, Volume, Export, etc.)
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              children: [
                // Split Action (Primary Highlighted)
                _buildActionButton(
                  context: context,
                  icon: Icons.call_split_rounded,
                  label: 'Split',
                  isPrimary: true,
                  enabled: viewModel.videoClips.isNotEmpty,
                  onTap: () {
                    final success = viewModel.splitAtPlayhead();
                    if (success) {
                      _showFeedback(context, '✂️ Clip split successfully at playhead');
                    } else {
                      _showFeedback(context, 'Place playhead inside a clip to split');
                    }
                  },
                ),

                // Trim Left
                _buildActionButton(
                  context: context,
                  icon: Icons.align_horizontal_left_rounded,
                  label: 'Trim Left',
                  enabled: hasSelectedClip,
                  onTap: () {
                    final success = viewModel.trimLeftToPlayhead();
                    if (success) {
                      _showFeedback(context, 'Trimmed start to playhead');
                    } else {
                      _showFeedback(context, 'Select clip & position playhead past start');
                    }
                  },
                ),

                // Trim Right
                _buildActionButton(
                  context: context,
                  icon: Icons.align_horizontal_right_rounded,
                  label: 'Trim Right',
                  enabled: hasSelectedClip,
                  onTap: () {
                    final success = viewModel.trimRightToPlayhead();
                    if (success) {
                      _showFeedback(context, 'Trimmed end to playhead');
                    } else {
                      _showFeedback(context, 'Select clip & position playhead before end');
                    }
                  },
                ),

                // Delete Clip
                _buildActionButton(
                  context: context,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  enabled: hasSelectedClip,
                  onTap: () {
                    viewModel.deleteSelectedClip();
                    _showFeedback(context, '🗑️ Clip removed');
                  },
                ),

                // Duplicate Clip
                _buildActionButton(
                  context: context,
                  icon: Icons.copy_all_rounded,
                  label: 'Duplicate',
                  enabled: hasSelectedClip,
                  onTap: () {
                    viewModel.duplicateSelectedClip();
                    _showFeedback(context, '📋 Clip duplicated');
                  },
                ),

                // Speed Controller
                _buildActionButton(
                  context: context,
                  icon: Icons.speed_rounded,
                  label: 'Speed (${viewModel.selectedClip?.speed.toStringAsFixed(1) ?? '1.0'}x)',
                  enabled: hasSelectedClip,
                  onTap: () => _showSpeedDialog(context),
                ),

                // Volume Controller
                _buildActionButton(
                  context: context,
                  icon: Icons.volume_up_rounded,
                  label: 'Volume',
                  enabled: hasSelectedClip,
                  onTap: () => _showVolumeDialog(context),
                ),

                // Add Clip (+)
                _buildActionButton(
                  context: context,
                  icon: Icons.add_to_photos_rounded,
                  label: 'Add Clip',
                  enabled: true,
                  onTap: () {
                    viewModel.addNewClip();
                    _showFeedback(context, '➕ New video clip added');
                  },
                ),

                // Export Button
                _buildActionButton(
                  context: context,
                  icon: Icons.file_upload_outlined,
                  label: 'Export',
                  isAccent: true,
                  enabled: viewModel.videoClips.isNotEmpty,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => ExportModalSheet(viewModel: viewModel),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return InkWell(
      onTap: viewModel.togglePlayPause,
      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: viewModel.isPlaying ? AppColors.secondary.withOpacity(0.2) : AppColors.surfaceElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: viewModel.isPlaying ? AppColors.secondary : AppColors.divider,
          ),
        ),
        child: Icon(
          viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 22,
          color: viewModel.isPlaying ? AppColors.secondary : AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    bool isPrimary = false,
    bool isAccent = false,
  }) {
    Color iconColor = enabled ? AppColors.iconDefault : AppColors.iconDisabled;
    Color textColor = enabled ? AppColors.textPrimary : AppColors.textMuted;
    Color? bgColor;

    if (isPrimary && enabled) {
      iconColor = AppColors.primary;
      textColor = AppColors.primary;
      bgColor = AppColors.primary.withOpacity(0.12);
    } else if (isAccent && enabled) {
      iconColor = AppColors.secondary;
      textColor = AppColors.secondary;
      bgColor = AppColors.secondary.withOpacity(0.12);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: isPrimary && enabled ? Border.all(color: AppColors.primary.withOpacity(0.4)) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: iconColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.0,
                  fontWeight: (isPrimary || isAccent) ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        duration: const Duration(milliseconds: 1200),
        backgroundColor: AppColors.surfaceHighlight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    final currentSpeed = viewModel.selectedClip?.speed ?? 1.0;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Adjust Playback Speed', style: AppTypography.headerTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0].map((spd) {
                  final isSel = (currentSpeed - spd).abs() < 0.05;
                  return ChoiceChip(
                    label: Text('${spd}x'),
                    selected: isSel,
                    selectedColor: AppColors.primary,
                    onSelected: (selected) {
                      if (selected) {
                        viewModel.setClipSpeed(spd);
                        Navigator.of(ctx).pop();
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVolumeDialog(BuildContext context) {
    double currentVolume = viewModel.selectedClip?.volume ?? 1.0;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              title: const Text('Clip Audio Volume', style: AppTypography.headerTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.volume_down_rounded, color: AppColors.textSecondary),
                      Text(
                        '${(currentVolume * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                      const Icon(Icons.volume_up_rounded, color: AppColors.primary),
                    ],
                  ),
                  Slider(
                    value: currentVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (val) {
                      setDialogState(() => currentVolume = val);
                      viewModel.setClipVolume(val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done', style: TextStyle(color: AppColors.primary)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
