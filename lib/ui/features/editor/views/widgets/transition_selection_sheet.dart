import 'dart:math' as math;
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

  double get _maxAllowedDuration {
    return widget.viewModel.getMaxTransitionDurationForBoundary(
      widget.leftClipId,
      widget.rightClipId,
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existingTransition?.type ?? TransitionType.fade;
    final maxAllowed = widget.viewModel.getMaxTransitionDurationForBoundary(
      widget.leftClipId,
      widget.rightClipId,
    );
    final initialDuration = widget.existingTransition?.duration ?? TransitionRegistry.defaultDuration;
    _duration = initialDuration.clamp(TransitionRegistry.minDuration, maxAllowed);
    _selectedCategory = _selectedType == TransitionType.none
        ? null
        : _selectedType.category;
  }

  void _onSelectType(TransitionType type) {
    setState(() {
      _selectedType = type;
    });
    _syncToViewModel(type, _duration);
  }

  void _onDurationChanged(double duration) {
    setState(() {
      _duration = duration;
    });
    if (_selectedType != TransitionType.none) {
      _syncToViewModel(_selectedType, duration);
    }
  }

  void _syncToViewModel(TransitionType type, double duration) {
    if (_applyToAll) {
      final result = widget.viewModel.applyTransitionToAll(type: type, duration: duration);
      if (!result.success && result.errors.isNotEmpty) {
        _showError(result.errors.first);
      }
      return;
    }

    if (type == TransitionType.none) {
      final current = widget.viewModel.transitions.where(
        (t) => t.leftClipId == widget.leftClipId && t.rightClipId == widget.rightClipId,
      ).firstOrNull;
      if (current != null) {
        widget.viewModel.removeTransition(current.id);
      }
      return;
    }

    final current = widget.viewModel.transitions.where(
      (t) => t.leftClipId == widget.leftClipId && t.rightClipId == widget.rightClipId,
    ).firstOrNull;

    final newTransition = Transition(
      id: current?.id,
      type: type,
      duration: duration,
      leftClipId: widget.leftClipId,
      rightClipId: widget.rightClipId,
    );

    final result = current != null
        ? widget.viewModel.replaceTransition(oldId: current.id, replacement: newTransition)
        : widget.viewModel.addTransition(newTransition);

    if (!result.success && result.errors.isNotEmpty) {
      _showError(result.errors.first);
    }
  }

  void _done() {
    if (_selectedType != TransitionType.none) {
      _syncToViewModel(_selectedType, _duration);
    }
    Navigator.of(context).pop();
  }

  void _removeTransition() {
    setState(() {
      _selectedType = TransitionType.none;
    });
    _syncToViewModel(TransitionType.none, _duration);
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
    final maxAllowed = _maxAllowedDuration;
    final leftClip = widget.viewModel.videoClips.where((c) => c.id == widget.leftClipId).firstOrNull;
    final rightClip = widget.viewModel.videoClips.where((c) => c.id == widget.rightClipId).firstOrNull;
    final leftTitle = leftClip != null ? leftClip.title : 'Clip A';
    final rightTitle = rightClip != null ? rightClip.title : 'Clip B';

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$leftTitle → $rightTitle',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Max: ${maxAllowed.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (widget.existingTransition != null || _selectedType != TransitionType.none)
                      IconButton(
                        tooltip: 'Remove transition',
                        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 22),
                        onPressed: _removeTransition,
                      ),
                    IconButton(
                      tooltip: 'Done',
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 26),
                      onPressed: _done,
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
                    onTap: () => _onSelectType(type),
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
                      '${_duration.toStringAsFixed(2)}s',
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
                  value: _duration.clamp(TransitionRegistry.minDuration, maxAllowed),
                  min: TransitionRegistry.minDuration,
                  max: maxAllowed > TransitionRegistry.minDuration ? maxAllowed : TransitionRegistry.minDuration + 0.01,
                  divisions: math.max(1, ((maxAllowed - TransitionRegistry.minDuration) * 10).round()),
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.surfaceLight,
                  onChanged: (val) {
                    _onDurationChanged(double.parse(val.toStringAsFixed(2)));
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
