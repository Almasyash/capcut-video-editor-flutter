import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class MaskAdjustmentSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const MaskAdjustmentSheet({super.key, required this.viewModel});

  @override
  State<MaskAdjustmentSheet> createState() => _MaskAdjustmentSheetState();
}

class _MaskAdjustmentSheetState extends State<MaskAdjustmentSheet> {
  late MaskType _selectedType;
  late double _size;
  late double _feather;
  late bool _inverted;

  @override
  void initState() {
    super.initState();
    final mask = widget.viewModel.selectedClip?.mask;
    _selectedType = mask?.type ?? MaskType.none;
    _size = mask?.size ?? 0.8;
    _feather = mask?.feather ?? 0.0;
    _inverted = mask?.inverted ?? false;
  }

  void _updateMask() {
    if (_selectedType == MaskType.none) {
      widget.viewModel.removeClipMask();
    } else {
      widget.viewModel.setClipMask(
        VideoMask(
          type: _selectedType,
          size: _size,
          feather: _feather,
          inverted: _inverted,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.crop_free_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Masking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mask Shape Presets
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MaskType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getMaskIcon(type), size: 14, color: isSelected ? Colors.black : Colors.white70),
                          const SizedBox(width: 4),
                          Text(type.name.toUpperCase()),
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
                          setState(() => _selectedType = type);
                          _updateMask();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            if (_selectedType != MaskType.none) ...[
              // Mask Size Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Mask Size:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('${(_size * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: _size,
                min: 0.2,
                max: 1.5,
                divisions: 26,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  setState(() => _size = val);
                  _updateMask();
                },
              ),

              // Feather Softness Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Feather (Soft Edge):', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('${_feather.round()} px', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: _feather,
                min: 0.0,
                max: 30.0,
                divisions: 30,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  setState(() => _feather = val);
                  _updateMask();
                },
              ),

              // Invert Toggle Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Invert Mask', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Hide inside and show outside', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                value: _inverted,
                activeTrackColor: AppColors.primary,
                onChanged: (val) {
                  setState(() => _inverted = val);
                  _updateMask();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getMaskIcon(MaskType type) {
    switch (type) {
      case MaskType.none: return Icons.block_rounded;
      case MaskType.split: return Icons.horizontal_split_rounded;
      case MaskType.filmstrip: return Icons.view_stream_rounded;
      case MaskType.rectangle: return Icons.crop_square_rounded;
      case MaskType.circle: return Icons.circle_outlined;
      case MaskType.heart: return Icons.favorite_rounded;
      case MaskType.star: return Icons.star_rounded;
    }
  }
}
