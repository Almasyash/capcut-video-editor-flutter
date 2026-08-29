import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';

class EditDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const EditDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final clip = viewModel.selectedClip;

    return Container(
      height: 180,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.content_cut_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          clip != null ? 'Edit: ${clip.title}' : 'Edit Clip (Select a clip)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Done',
                  onPressed: viewModel.closeDrawer,
                ),
              ],
            ),
          ),

          if (clip == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Tap a video clip on the timeline to edit',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  _buildToolButton(
                    icon: Icons.call_split_rounded,
                    label: 'Split',
                    onTap: () => viewModel.splitClipAtPlayhead(),
                    color: AppColors.primary,
                  ),
                  _buildToolButton(
                    icon: Icons.speed_rounded,
                    label: 'Speed (${clip.speed}x)',
                    onTap: () => _showSpeedDialog(context),
                  ),
                  _buildToolButton(
                    icon: Icons.volume_up_rounded,
                    label: 'Volume (${(clip.volume * 100).round()}%)',
                    onTap: () => _showVolumeDialog(context),
                  ),
                  _buildToolButton(
                    icon: Icons.rotate_right_rounded,
                    label: 'Rotate (${clip.rotationDegrees}°)',
                    onTap: viewModel.rotateSelectedClip,
                  ),
                  _buildToolButton(
                    icon: Icons.flip_rounded,
                    label: 'Flip H',
                    onTap: viewModel.flipSelectedClipHorizontal,
                    isActive: clip.flipHorizontal,
                  ),
                  _buildToolButton(
                    icon: Icons.swap_vert_rounded,
                    label: 'Flip V',
                    onTap: viewModel.flipSelectedClipVertical,
                    isActive: clip.flipVertical,
                  ),
                  _buildToolButton(
                    icon: Icons.opacity_rounded,
                    label: 'Opacity (${(clip.opacity * 100).round()}%)',
                    onTap: () => _showOpacityDialog(context),
                  ),
                  _buildToolButton(
                    icon: Icons.find_replace_rounded,
                    label: 'Replace',
                    onTap: () => _showReplaceModal(context),
                  ),
                  _buildToolButton(
                    icon: Icons.fast_rewind_rounded,
                    label: 'Reverse',
                    onTap: viewModel.toggleSelectedClipReverse,
                    isActive: clip.isReversed,
                  ),
                  _buildToolButton(
                    icon: Icons.ac_unit_rounded,
                    label: 'Freeze',
                    onTap: viewModel.toggleSelectedClipFreeze,
                    isActive: clip.isFrozen,
                  ),
                  _buildToolButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    onTap: viewModel.deleteSelectedClip,
                    color: AppColors.error,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool isActive = false,
  }) {
    final effectiveColor = isActive ? AppColors.secondary : (color ?? AppColors.iconDefault);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.secondary.withValues(alpha: 0.15) : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(color: isActive ? AppColors.secondary : AppColors.divider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: effectiveColor),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
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
            final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
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

  void _showOpacityDialog(BuildContext context) {
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
                        'Clip Opacity',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        '${(clip.opacity * 100).round()}%',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: clip.opacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      setSheetState(() {});
                      viewModel.setSelectedClipOpacity(val);
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

  void _showReplaceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MediaPickerSheet(viewModel: viewModel, isReplacing: true),
    );
  }
}
