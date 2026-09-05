import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class TransitionSelectionSheet extends StatefulWidget {
  final EditorViewModel viewModel;
  final String leftClipId;
  final String rightClipId;
  final Transition? existingTransition;

  const TransitionSelectionSheet({
    super.key,
    required this.viewModel,
    required this.leftClipId,
    required this.rightClipId,
    this.existingTransition,
  });

  @override
  State<TransitionSelectionSheet> createState() => _TransitionSelectionSheetState();
}

class _TransitionSelectionSheetState extends State<TransitionSelectionSheet> {
  late TransitionType _selectedType;
  late double _duration;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existingTransition?.type ?? TransitionType.fade;
    _duration = widget.existingTransition?.duration ?? 0.5;
  }

  void _applyTransition() {
    if (_selectedType == TransitionType.none) {
      if (widget.existingTransition != null) {
        widget.viewModel.removeTransition(widget.existingTransition!.id);
      }
      Navigator.of(context).pop();
      return;
    }

    final newTransition = Transition(
      id: widget.existingTransition?.id,
      type: _selectedType,
      duration: _duration,
      leftClipId: widget.leftClipId,
      rightClipId: widget.rightClipId,
    );

    final result = widget.existingTransition != null
        ? widget.viewModel.replaceTransition(
            oldId: widget.existingTransition!.id,
            replacement: newTransition,
          )
        : widget.viewModel.addTransition(newTransition);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errors.isNotEmpty ? result.errors.first : 'Failed to apply transition',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _removeTransition() {
    if (widget.existingTransition != null) {
      widget.viewModel.removeTransition(widget.existingTransition!.id);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Transitions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    if (widget.existingTransition != null)
                      TextButton(
                        onPressed: _removeTransition,
                        child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 24),
                      onPressed: _applyTransition,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Duration', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                Text('${_duration.toStringAsFixed(1)}s', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            Slider(
              value: _duration,
              min: 0.1,
              max: 2.0,
              divisions: 19,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.surfaceLight,
              onChanged: (val) {
                setState(() {
                  _duration = val;
                });
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: TransitionType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedType = type;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 72,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceLight,
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
                              _getIconForType(type),
                              color: isSelected ? AppColors.primary : AppColors.iconDefault,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _getLabelForType(type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(TransitionType type) {
    switch (type) {
      case TransitionType.none:
        return Icons.block_rounded;
      case TransitionType.fade:
        return Icons.gradient_rounded;
      case TransitionType.dissolve:
        return Icons.blur_on_rounded;
      case TransitionType.blackFade:
        return Icons.brightness_1_rounded;
      case TransitionType.whiteFade:
        return Icons.brightness_5_rounded;
      case TransitionType.slideLeft:
        return Icons.arrow_back_rounded;
      case TransitionType.slideRight:
        return Icons.arrow_forward_rounded;
      case TransitionType.slideUp:
        return Icons.arrow_upward_rounded;
      case TransitionType.slideDown:
        return Icons.arrow_downward_rounded;
      case TransitionType.wipeLeft:
        return Icons.swipe_left_rounded;
      case TransitionType.wipeRight:
        return Icons.swipe_right_rounded;
      case TransitionType.zoomIn:
        return Icons.zoom_in_rounded;
      case TransitionType.zoomOut:
        return Icons.zoom_out_rounded;
    }
  }

  String _getLabelForType(TransitionType type) {
    switch (type) {
      case TransitionType.none:
        return 'None';
      case TransitionType.fade:
        return 'Fade';
      case TransitionType.dissolve:
        return 'Dissolve';
      case TransitionType.blackFade:
        return 'Black Fade';
      case TransitionType.whiteFade:
        return 'White Fade';
      case TransitionType.slideLeft:
        return 'Slide L';
      case TransitionType.slideRight:
        return 'Slide R';
      case TransitionType.slideUp:
        return 'Slide U';
      case TransitionType.slideDown:
        return 'Slide D';
      case TransitionType.wipeLeft:
        return 'Wipe L';
      case TransitionType.wipeRight:
        return 'Wipe R';
      case TransitionType.zoomIn:
        return 'Zoom In';
      case TransitionType.zoomOut:
        return 'Zoom Out';
    }
  }
}
