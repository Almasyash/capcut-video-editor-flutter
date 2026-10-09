import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Professional Mask Adjustment Sheet for Editor FS v1.7.0
/// Supports multi-mask stacks, 5 primary geometries, feathering, expansion,
/// inversion, opacity, boolean combination modes, keyframing, mask reordering,
/// custom naming, enable/bypass toggle, precision numeric entry, and confirmation guards.
class MaskAdjustmentSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const MaskAdjustmentSheet({super.key, required this.viewModel});

  @override
  State<MaskAdjustmentSheet> createState() => _MaskAdjustmentSheetState();
}

class _MaskAdjustmentSheetState extends State<MaskAdjustmentSheet> {
  int _activeMaskIndex = 0;
  static const int _maxHardwareMasks = 4;

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

  void _updateActiveMaskDiscrete(VideoMask updated) {
    if (widget.viewModel.selectedClip != null) {
      final list = widget.viewModel.selectedClip!.masks;
      if (list.isEmpty) {
        widget.viewModel.addMaskToSelectedClip(updated);
      } else {
        widget.viewModel.updateMaskDiscreteInSelectedClip(_activeMaskIndex, updated);
      }
    } else if (widget.viewModel.selectedOverlay != null) {
      final list = widget.viewModel.selectedOverlay!.masks;
      if (list.isEmpty) {
        widget.viewModel.addMaskToSelectedOverlay(updated);
      } else {
        widget.viewModel.updateMaskDiscreteInSelectedOverlay(_activeMaskIndex, updated);
      }
    }
    setState(() {});
  }

  void _addNewMask(MaskType type) {
    if (_currentMasks.length >= _maxHardwareMasks) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 4 concurrent masks supported for native hardware export.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

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

  void _toggleCurrentMaskEnabled() {
    if (_currentMasks.isEmpty) return;
    if (widget.viewModel.selectedClip != null) {
      widget.viewModel.toggleMaskEnabledInSelectedClip(_activeMaskIndex);
    } else if (widget.viewModel.selectedOverlay != null) {
      widget.viewModel.toggleMaskEnabledInSelectedOverlay(_activeMaskIndex);
    }
    setState(() {});
  }

  void _reorderCurrentMask(int direction) {
    final list = _currentMasks;
    final targetIndex = _activeMaskIndex + direction;
    if (targetIndex < 0 || targetIndex >= list.length) return;
    if (widget.viewModel.selectedClip != null) {
      widget.viewModel.reorderMasksInSelectedClip(_activeMaskIndex, targetIndex);
    } else if (widget.viewModel.selectedOverlay != null) {
      widget.viewModel.reorderMasksInSelectedOverlay(_activeMaskIndex, targetIndex);
    }
    setState(() {
      _activeMaskIndex = targetIndex;
    });
  }

  void _renameCurrentMask(BuildContext context) {
    if (_currentMasks.isEmpty) return;
    final controller = TextEditingController(text: _activeMask.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Rename Mask', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Mask Name',
            labelStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                if (widget.viewModel.selectedClip != null) {
                  widget.viewModel.renameMaskInSelectedClip(_activeMaskIndex, newName);
                } else if (widget.viewModel.selectedOverlay != null) {
                  widget.viewModel.renameMaskInSelectedOverlay(_activeMaskIndex, newName);
                }
                setState(() {});
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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

  void _confirmDeleteCurrentMask(BuildContext context) {
    if (_currentMasks.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete Mask?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Are you sure you want to delete "${_activeMask.name}"? This action can be undone with Undo.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteCurrentMask();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
    _updateActiveMaskDiscrete(resetMask);
  }

  void _confirmResetCurrentMask(BuildContext context) {
    if (_currentMasks.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Reset Mask?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Reset position, scale, feather, and rotation adjustments on "${_activeMask.name}" to defaults?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetCurrentMask();
            },
            child: const Text('Reset', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openNumericInputDialog(
    BuildContext context,
    String title,
    double currentValue,
    double min,
    double max,
    String unit,
    ValueChanged<double> onSubmitted,
  ) {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Edit $title', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a value between ${min.toStringAsFixed(0)} and ${max.toStringAsFixed(0)} $unit:',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                suffixText: unit,
                suffixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed != null) {
                final clamped = parsed.clamp(min, max);
                widget.viewModel.beginMaskGesture();
                onSubmitted(clamped);
                widget.viewModel.commitMaskGesture();
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Apply', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
                        'Masking Engine (${masks.length}/$_maxHardwareMasks)',
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
                      for (int i = 0; i < masks.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  masks[i].enabled ? masks[i].type.icon : Icons.visibility_off_rounded,
                                  size: 14,
                                  color: _activeMaskIndex == i
                                      ? Colors.black
                                      : (masks[i].enabled ? Colors.white70 : Colors.white38),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  masks[i].name,
                                  style: TextStyle(
                                    decoration: masks[i].enabled ? TextDecoration.none : TextDecoration.lineThrough,
                                  ),
                                ),
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
                      ],
                      if (masks.length < _maxHardwareMasks)
                        IconButton(
                          tooltip: 'Add Mask (up to 4)',
                          icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
                          onPressed: () => _addNewMask(MaskType.rectangle),
                        ),
                    ],
                  ),
                ),

              // Mask Stack Reorder & Rename Controls
              if (masks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.textSecondary),
                      label: Text(
                        'Rename "${activeMask.name}"',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      onPressed: () => _renameCurrentMask(context),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Move mask backward in stack',
                      icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white70),
                      onPressed: _activeMaskIndex > 0 ? () => _reorderCurrentMask(-1) : null,
                    ),
                    Text(
                      'Layer ${_activeMaskIndex + 1}/${masks.length}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'Move mask forward in stack',
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white70),
                      onPressed: _activeMaskIndex < masks.length - 1 ? () => _reorderCurrentMask(1) : null,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 10),

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
                // Enable / Bypass Mask Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(
                        activeMask.enabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        size: 16,
                        color: activeMask.enabled ? AppColors.primary : Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        activeMask.enabled ? 'Mask Enabled' : 'Mask Bypassed (Muted)',
                        style: TextStyle(
                          fontSize: 13,
                          color: activeMask.enabled ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    activeMask.enabled ? 'Active on preview and export pipeline' : 'Temporarily ignored without deleting',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                  value: activeMask.enabled,
                  activeTrackColor: AppColors.primary,
                  onChanged: (_) => _toggleCurrentMaskEnabled(),
                ),

                const SizedBox(height: 8),

                // Feather Slider (0.0 to 100.0 px)
                _buildSlider(
                  label: 'Feather (Edge Softness)',
                  value: activeMask.feather,
                  min: 0.0,
                  max: 100.0,
                  unit: 'px',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(feather: val)),
                  context: context,
                ),

                // Expansion Slider (-100.0 to 100.0 px)
                _buildSlider(
                  label: 'Expansion (Dilation/Erosion)',
                  value: activeMask.expansion,
                  min: -100.0,
                  max: 100.0,
                  unit: 'px',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(expansion: val)),
                  context: context,
                ),

                // Size / Scale Slider
                _buildSlider(
                  label: 'Scale Size',
                  value: activeMask.scale,
                  min: 0.1,
                  max: 3.0,
                  unit: 'x',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(scale: val, size: val)),
                  context: context,
                ),

                // Rotation Slider
                _buildSlider(
                  label: 'Rotation',
                  value: activeMask.rotation,
                  min: -180.0,
                  max: 180.0,
                  unit: '°',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(rotation: val)),
                  context: context,
                ),

                // Opacity Slider
                _buildSlider(
                  label: 'Mask Opacity',
                  value: activeMask.opacity * 100.0,
                  min: 0.0,
                  max: 100.0,
                  unit: '%',
                  onChanged: (val) => _updateActiveMask(activeMask.copyWith(opacity: val / 100.0)),
                  context: context,
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
                              if (selected) _updateActiveMaskDiscrete(activeMask.copyWith(combineMode: mode));
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
                  onChanged: (val) => _updateActiveMaskDiscrete(activeMask.copyWith(inverted: val)),
                ),

                const SizedBox(height: 12),

                // Bottom Action Buttons with confirmation safeguards
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.white70),
                      label: const Text('Reset', style: TextStyle(color: Colors.white70)),
                      onPressed: () => _confirmResetCurrentMask(context),
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
                      onPressed: () => _confirmDeleteCurrentMask(context),
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
              _updateActiveMaskDiscrete(_activeMask.copyWith(type: type));
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
    required BuildContext context,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _openNumericInputDialog(context, label, value, min, max, unit, onChanged),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${value.toStringAsFixed(1)} $unit',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    const SizedBox(width: 3),
                    const Icon(Icons.edit_rounded, size: 11, color: AppColors.primary),
                  ],
                ),
              ),
            ),
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
