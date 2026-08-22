import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/duplicate_options_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/export_modal_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';

/// Middle Action Toolbar containing Split, Trim Left/Right, Delete, Duplicate (with PIP option),
/// Speed, Volume, Add Clip (Media Picker), and Export.
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
                    final success = viewModel.splitClipAtPlayhead();
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

                // Duplicate Clip (Opens choice: Timeline vs Overlay Layer)
                _buildActionButton(
                  context: context,
                  icon: Icons.copy_all_rounded,
                  label: 'Duplicate',
                  enabled: hasSelectedClip,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => DuplicateOptionsSheet(viewModel: viewModel),
                    );
                  },
                ),

                // Add Clip (Opens Gallery Media Picker)
                _buildActionButton(
                  context: context,
                  icon: Icons.add_photo_alternate_rounded,
                  label: 'Add Clip',
                  enabled: true,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => MediaPickerSheet(viewModel: viewModel),
                    );
                  },
                ),

                // Edit Clip Detailed Drawer
                _buildActionButton(
                  context: context,
                  icon: Icons.edit_note_rounded,
                  label: 'Edit Tools',
                  enabled: hasSelectedClip,
                  onTap: () => viewModel.openDrawer(EditorCategory.edit),
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
            width: 1.2,
          ),
        ),
        child: Icon(
          viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 20,
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    final clip = viewModel.selectedClip;
    if (clip == null) return;

    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(AppDimensions.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Speed Adjustment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: speeds.map((s) {
                  final isSelected = clip.speed == s;
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        viewModel.setClipSpeed(s);
                        Navigator.of(ctx).pop();
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showVolumeDialog(BuildContext context) {
    final clip = viewModel.selectedClip;
    if (clip == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(AppDimensions.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Clip Volume',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        '${(clip.volume * 100).round()}%',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: clip.volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      setSheetState(() {});
                      viewModel.setClipVolume(val);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
