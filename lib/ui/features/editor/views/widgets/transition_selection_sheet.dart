import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/services/transition_registry.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Bottom modal sheet providing a categorized library of video transitions,
/// duration slider, and option to apply to all adjacent clips.
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
  TransitionCategory? _selectedCategory;
  bool _applyToAll = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existingTransition?.type ?? TransitionType.fade;
    _duration = widget.existingTransition?.duration ?? TransitionRegistry.defaultDuration;
    _selectedCategory = _selectedType == TransitionType.none
        ? null
        : _selectedType.category;
  }

  void _applyTransition() {
    if (_applyToAll) {
      final result = widget.viewModel.applyTransitionToAll(
        type: _selectedType,
        duration: _duration,
      );
      if (!result.success) {
        _showError(result.errors.isNotEmpty ? result.errors.first : 'Failed to apply to all');
        return;
      }
      Navigator.of(context).pop();
      return;
    }

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
      _showError(result.errors.isNotEmpty ? result.errors.first : 'Failed to apply transition');
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<TransitionType> get _filteredTransitions {
    if (_selectedCategory == null) {
      return TransitionType.values;
    }
    return TransitionType.values
        .where((t) => t == TransitionType.none || t.category == _selectedCategory)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: AppDimensions.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Transitions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (widget.existingTransition != null)
                      IconButton(
                        tooltip: 'Remove transition',
                        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 22),
                        onPressed: _removeTransition,
                      ),
                    IconButton(
                      tooltip: 'Apply',
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 26),
                      onPressed: _applyTransition,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Category Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryChip(null, 'All'),
                  ...TransitionRegistry.categories.map((c) {
                    return _buildCategoryChip(c, TransitionRegistry.getCategoryTitle(c));
                  }),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Transition Cards Grid
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filteredTransitions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final type = _filteredTransitions[index];
                  final isSelected = _selectedType == type;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 76,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.divider,
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getIconForType(type),
                            color: isSelected ? AppColors.primary : AppColors.iconDefault,
                            size: 26,
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(
                              type.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Duration Slider & Apply to All Controls
            if (_selectedType != TransitionType.none) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transition Duration',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_duration.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _duration,
                  min: TransitionRegistry.minDuration,
                  max: TransitionRegistry.maxDuration,
                  divisions: 29, // 0.1s steps from 0.1 to 3.0
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.surfaceLight,
                  onChanged: (val) {
                    setState(() {
                      _duration = double.parse(val.toStringAsFixed(1));
                    });
                  },
                ),
              ),
            ],

            // Apply to All Checkbox
            InkWell(
              onTap: () {
                setState(() {
                  _applyToAll = !_applyToAll;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _applyToAll,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            _applyToAll = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Apply to all clips',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(TransitionCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surfaceLight,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = category;
          });
        },
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
      case TransitionType.wipeLeft:
        return Icons.swipe_left_rounded;
      case TransitionType.wipeRight:
        return Icons.swipe_right_rounded;
      case TransitionType.wipeUp:
        return Icons.swipe_up_rounded;
      case TransitionType.wipeDown:
        return Icons.swipe_down_rounded;
      case TransitionType.slideLeft:
        return Icons.arrow_back_rounded;
      case TransitionType.slideRight:
        return Icons.arrow_forward_rounded;
      case TransitionType.slideUp:
        return Icons.arrow_upward_rounded;
      case TransitionType.slideDown:
        return Icons.arrow_downward_rounded;
      case TransitionType.zoomIn:
        return Icons.zoom_in_rounded;
      case TransitionType.zoomOut:
        return Icons.zoom_out_rounded;
      case TransitionType.circle:
        return Icons.lens_outlined;
      case TransitionType.radial:
        return Icons.pie_chart_outline_rounded;
      case TransitionType.blur:
        return Icons.lens_blur_rounded;
      case TransitionType.pixelate:
        return Icons.grid_view_rounded;
    }
  }
}
