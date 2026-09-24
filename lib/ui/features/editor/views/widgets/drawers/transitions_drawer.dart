import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class TransitionsDrawer extends StatefulWidget {
  final EditorViewModel viewModel;
  final bool isDesktop;

  const TransitionsDrawer({
    super.key,
    required this.viewModel,
    this.isDesktop = false,
  });

  @override
  State<TransitionsDrawer> createState() => _TransitionsDrawerState();
}

class _TransitionsDrawerState extends State<TransitionsDrawer> {
  double _duration = 0.5;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final clips = viewModel.videoClips;
    final selectedIdx = viewModel.selectedClipIndex ?? 0;
    final canApply = clips.length >= 2 && selectedIdx < clips.length - 1;

    String leftClipId = '';
    String rightClipId = '';
    Transition? existingTransition;

    if (canApply) {
      leftClipId = clips[selectedIdx].id;
      rightClipId = clips[selectedIdx + 1].id;
      for (final t in viewModel.currentProject.transitions) {
        if (t.leftClipId == leftClipId && t.rightClipId == rightClipId) {
          existingTransition = t;
          break;
        }
      }
    }

    final activeType = existingTransition?.type ?? TransitionType.none;

    return Container(
      height: widget.isDesktop ? null : 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.transform_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      canApply
                          ? 'Transitions (${clips[selectedIdx].title} -> ${clips[selectedIdx + 1].title})'
                          : 'Transitions (Select a clip to connect)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
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

          if (!canApply)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  clips.length < 2
                      ? 'Add at least 2 video clips to apply transitions between them'
                      : 'Select a clip before the last one to set transition to the next clip',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            )
          else ...[
            // Duration slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Text('Duration:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: _duration,
                      min: 0.1,
                      max: 2.0,
                      divisions: 19,
                      label: '${_duration.toStringAsFixed(1)}s',
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() => _duration = val);
                        if (existingTransition != null && existingTransition.type != TransitionType.none) {
                          viewModel.replaceTransition(
                            oldId: existingTransition.id,
                            replacement: existingTransition.copyWith(duration: val),
                          );
                        }
                      },
                    ),
                  ),
                  Text('${_duration.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
            ),

            // Transition Presets Grid
            widget.isDesktop
                ? Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: TransitionType.values.map((type) => _buildTypeItem(type, activeType, leftClipId, rightClipId, existingTransition)).toList(),
                    ),
                  )
                : Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: TransitionType.values.length,
                      itemBuilder: (context, idx) {
                        final type = TransitionType.values[idx];
                        return _buildTypeItem(type, activeType, leftClipId, rightClipId, existingTransition);
                      },
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeItem(TransitionType type, TransitionType activeType, String leftClipId, String rightClipId, Transition? existingTransition) {
    final isSelected = activeType == type;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (type == TransitionType.none) {
          if (existingTransition != null) {
            widget.viewModel.removeTransition(existingTransition.id);
          }
        } else {
          final newTransition = Transition(
            id: existingTransition?.id,
            type: type,
            duration: _duration,
            leftClipId: leftClipId,
            rightClipId: rightClipId,
          );
          if (existingTransition != null) {
            widget.viewModel.replaceTransition(oldId: existingTransition.id, replacement: newTransition);
          } else {
            widget.viewModel.addTransition(newTransition);
          }
        }
        setState(() {});
      },
      child: Container(
        width: widget.isDesktop ? 88 : null,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIcon(type),
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              _getLabel(type),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(TransitionType type) {
    switch (type) {
      case TransitionType.none: return Icons.block_rounded;
      case TransitionType.fade: return Icons.gradient_rounded;
      case TransitionType.dissolve: return Icons.blur_on_rounded;
      case TransitionType.blackFade: return Icons.brightness_1_rounded;
      case TransitionType.whiteFade: return Icons.wb_sunny_rounded;
      case TransitionType.slideLeft: return Icons.arrow_back_rounded;
      case TransitionType.slideRight: return Icons.arrow_forward_rounded;
      case TransitionType.slideUp: return Icons.arrow_upward_rounded;
      case TransitionType.slideDown: return Icons.arrow_downward_rounded;
      case TransitionType.wipeLeft: return Icons.swipe_left_rounded;
      case TransitionType.wipeRight: return Icons.swipe_right_rounded;
      case TransitionType.wipeUp: return Icons.swipe_up_rounded;
      case TransitionType.wipeDown: return Icons.swipe_down_rounded;
      case TransitionType.zoomIn: return Icons.zoom_in_rounded;
      case TransitionType.zoomOut: return Icons.zoom_out_rounded;
      case TransitionType.circle: return Icons.circle_outlined;
      case TransitionType.radial: return Icons.track_changes_rounded;
      case TransitionType.blur: return Icons.blur_linear_rounded;
      case TransitionType.pixelate: return Icons.grid_view_rounded;
    }
  }

  String _getLabel(TransitionType type) => type.displayName;
}
