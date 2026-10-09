import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Professional Mask Adjustment Sheet for Editor FS v1.6.0
/// Supports multi-mask stacks, 5 primary geometries, feathering, expansion,
/// inversion, opacity, boolean combination modes, and keyframing.
class MaskAdjustmentSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const MaskAdjustmentSheet({super.key, required this.viewModel});

  @override
  State<MaskAdjustmentSheet> createState() => _MaskAdjustmentSheetState();
}

class _MaskAdjustmentSheetState extends State<MaskAdjustmentSheet> {
  int _activeMaskIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.viewModel.setMaskModeActive(true);
  }

  @override
  void dispose() {
    widget.viewModel.setMaskModeActive(false);
    super.dispose();
  }

  List<VideoMask> get _currentMasks {
    if (widget.viewModel.selectedClip != null) {
      return widget.viewModel.selectedClip!.masks;
    } else if (widget.viewModel.selectedOverlay != null) {
      return widget.viewModel.selectedOverlay!.masks;
    }
    return const [];
  }

  VideoMask get _activeMask {
    final list = _currentMasks;
    if (list.isNotEmpty && _activeMaskIndex < list.length) {
      return list[_activeMaskIndex];
    }
    return const VideoMask(type: MaskType.none);
  }

  void _updateActiveMask(VideoMask updated) {
    if (widget.viewModel.selectedClip != null) {
      final list = widget.viewModel.selectedClip!.masks;
      if (list.isEmpty) {
        widget.viewModel.addMaskToSelectedClip(updated);
      } else {
        widget.viewModel.updateMaskInSelectedClip(_activeMaskIndex, updated);
      }
    } else if (widget.viewModel.selectedOverlay != null) {
      final list = widget.viewModel.selectedOverlay!.masks;
      if (list.isEmpty) {
        widget.viewModel.addMaskToSelectedOverlay(updated);
      } else {
        widget.viewModel.updateMaskInSelectedOverlay(_activeMaskIndex, updated);
      }
    }
    setState(() {});
  }

  void _addNewMask(MaskType type) {
    final count = _currentMasks.length + 1;
    final newMask = VideoMask(
      id: 'mask_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Mask $count',
      type: type,
      width: 0.5,
      height: 0.5,
      scale: 1.0,
      opacity: 1.0,
      feather: 0.0,
      expansion: 0.0,
    );

    if (widget.viewModel.selectedClip != null) {
      widget.viewModel.addMaskToSelectedClip(newMask);
    } else if (widget.viewModel.selectedOverlay != null) {
      widget.viewModel.addMaskToSelectedOverlay(newMask);
    }

    setState(() {
      _activeMaskIndex = _currentMasks.length - 1;
    });
  }

  void _deleteCurrentMask() {
    if (_currentMasks.isEmpty) return;
    if (widget.viewModel.selectedClip != null) {
      widget.viewModel.removeMaskFromSelectedClip(_activeMaskIndex);
    } else if (widget.viewModel.selectedOverlay != null) {
      widget.viewModel.removeMaskFromSelectedOverlay(_activeMaskIndex);
    }
    setState(() {
      if (_activeMaskIndex >= _currentMasks.length) {
        _activeMaskIndex = math.max(0, _currentMasks.length - 1);
      }
    });
  }

  void _resetCurrentMask() {
    if (_currentMasks.isEmpty) return;
    final current = _activeMask;
    final resetMask = VideoMask(
      id: current.id,
      name: current.name,
      type: current.type,
      width: 0.5,
      height: 0.5,
      scale: 1.0,
      opacity: 1.0,
      feather: 0.0,
      expansion: 0.0,
      positionX: 0.0,
      positionY: 0.0,
      rotation: 0.0,
      inverted: false,
      combineMode: MaskCombineMode.add,
    );
    _updateActiveMask(resetMask);
  }

  @override
  Widget build(BuildContext context) {
    final masks = _currentMasks;
    final activeMask = _activeMask;
    final hasActiveMask = activeMask.type != MaskType.none;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.md),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.masks_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Masking Engine (${masks.length} ${masks.length == 1 ? "mask" : "masks"})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Add Keyframe',
                        icon: const Icon(Icons.diamond_outlined, color: AppColors.primary, size: 22),
                        onPressed: () {
                          widget.viewModel.addMaskKeyframeAtPlayhead();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Multi-mask stack tabs (if masks exist)
              if (masks.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < masks.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(masks[i].type.icon, size: 14, color: _activeMaskIndex == i ? Colors.black : Colors.white70),
                                const SizedBox(width: 4),
                                Text(masks[i].name),
                              ],
                            ),
                            selected: _activeMaskIndex == i,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.surfaceLight,
                            labelStyle: TextStyle(
                              color: _activeMaskIndex == i ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            onSelected: (selected) {
                              if (selected) setState(() => _activeMaskIndex = i);
                            },
                          ),
                        ),
                      IconButton(
                        tooltip: 'Add Mask',
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
                        onPressed: () => _addNewMask(MaskType.rectangle),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Geometry Type Presets
              const Text('Shape Geometry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTypeChip(MaskType.rectangle, activeMask.type),
                    _buildTypeChip(MaskType.ellipse, activeMask.type),
                    _buildTypeChip(MaskType.polygon, activeMask.type),
                    _buildTypeChip(MaskType.linear, activeMask.type),
                    _buildTypeChip(MaskType.radial, activeMask.type),
                    _buildTypeChip(MaskType.split, activeMask.type),
                    _buildTypeChip(MaskType.filmstrip, activeMask.type),
                    _buildTypeChip(MaskType.circle, activeMask.type),
                    _buildTypeChip(MaskType.heart, activeMask.type),
                    _buildTypeChip(MaskType.star, activeMask.type),
                    _buildTypeChip(MaskType.none, activeMask.type),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (hasActiveMask) ...[
                // Feather Slider
                _buildSlider(
                  label: 'Feather (Edge Softness)',
                  value: activeMask.feather,
                  min: 0.0,
                  max: 50.0,
                  unit: 'px',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(feather: val)),
                ),

                // Expansion Slider
                _buildSlider(
                  label: 'Expansion (Dilation/Erosion)',
                  value: activeMask.expansion,
                  min: -50.0,
                  max: 50.0,
                  unit: 'px',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(expansion: val)),
                ),

                // Size / Scale Slider
                _buildSlider(
                  label: 'Scale Size',
                  value: activeMask.scale,
                  min: 0.2,
                  max: 2.0,
                  unit: 'x',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(scale: val, size: val)),
                ),

                // Rotation Slider
                _buildSlider(
                  label: 'Rotation',
                  value: activeMask.rotation,
                  min: -180.0,
                  max: 180.0,
                  unit: '°',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(rotation: val)),
                ),

                // Opacity Slider
                _buildSlider(
                  label: 'Mask Opacity',
                  value: activeMask.opacity * 100.0,
                  min: 0.0,
                  max: 100.0,
                  unit: '%',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(opacity: val / 100.0)),
                ),

                const SizedBox(height: 8),

                // Boolean Combination Mode (Add, Intersect, Subtract, Difference)
                if (masks.length > 1) ...[
                  const Text('Combination Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: MaskCombineMode.values.map((mode) {
                        final isSel = activeMask.combineMode == mode;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(mode.displayName),
                            selected: isSel,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.surfaceLight,
                            labelStyle: TextStyle(
                              color: isSel ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            onSelected: (selected) {
                              if (selected) _updateActiveMask(activeMask.copyWith(combineMode: mode));
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Invert Mask Toggle Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Invert Mask', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Hide inside and display outside the boundary', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  value: activeMask.inverted,
                  activeTrackColor: AppColors.primary,
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(inverted: val)),
                ),

                const SizedBox(height: 12),

                // Bottom Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.white70),
                      label: const Text('Reset', style: TextStyle(color: Colors.white70)),
                      onPressed: _resetCurrentMask,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                      label: const Text('Duplicate', style: TextStyle(color: AppColors.primary)),
                      onPressed: () {
                        if (widget.viewModel.selectedClip != null) {
                          widget.viewModel.duplicateMaskInSelectedClip(_activeMaskIndex);
                        } else if (widget.viewModel.selectedOverlay != null) {
                          widget.viewModel.duplicateMaskInSelectedOverlay(_activeMaskIndex);
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                      label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      onPressed: _deleteCurrentMask,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(MaskType type, MaskType current) {
    final isSelected = current == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 14, color: isSelected ? Colors.black : Colors.white70),
            const SizedBox(width: 4),
            Text(type.displayName.toUpperCase()),
          ],
        ),
        selected: isSelected,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surfaceLight,
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        onSelected: (selected) {
          if (selected) {
            if (_currentMasks.isEmpty) {
              _addNewMask(type);
            } else {
              _updateActiveMask(_activeMask.copyWith(type: type));
            }
          }
        },
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Text('${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: AppColors.primary,
          onChanged: onChanged,
          onChangeStart: (_) => widget.viewModel.beginMaskGesture(),
          onChangeEnd: (_) => widget.viewModel.commitMaskGesture(),
        ),
      ],
    );
  }
}
