import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class CanvasDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const CanvasDrawer({
    super.key,
    required this.viewModel,
  });

  static const List<Color> _canvasColors = [
    Colors.black,
    Color(0xFF1E1E24),
    Color(0xFF2C3E50),
    Color(0xFF00E5FF),
    Color(0xFFFF007F),
    Color(0xFFFF8008),
    Color(0xFF38EF7D),
    Color(0xFF7928CA),
  ];

  @override
  Widget build(BuildContext context) {
    final currentRatio = viewModel.aspectRatio;
    final currentColor = viewModel.canvasBackgroundColor;
    final currentBlur = viewModel.canvasBlurSigma;

    return Container(
      height: 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.crop_rotate_rounded, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Canvas & Aspect Ratio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppDimensions.md),
              children: [
                // 1. Aspect Ratio Presets
                const Text('Aspect Ratio:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: AspectRatioPreset.values.map((preset) {
                    final isSelected = currentRatio == preset;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: ChoiceChip(
                          label: Text(preset.label),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceLight,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : Colors.white,
                          ),
                          onSelected: (selected) {
                            if (selected) viewModel.setAspectRatio(preset);
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // 2. Background Color Palette
                const Text('Background Color:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: _canvasColors.map((color) {
                    final isSelected = currentColor.value == color.value;
                    return GestureDetector(
                      onTap: () => viewModel.setCanvasBackgroundColor(color),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.divider,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // 3. Background Blur
                Row(
                  children: [
                    const Text('Background Blur:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    ...[0.0, 5.0, 12.0, 20.0].map((blur) {
                      final label = blur == 0.0 ? 'Off' : (blur <= 5.0 ? 'Soft' : (blur <= 12.0 ? 'Med' : 'High'));
                      final isSelected = (currentBlur - blur).abs() < 1.0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: FilterChip(
                          label: Text(label),
                          selected: isSelected,
                          selectedColor: AppColors.secondary,
                          backgroundColor: AppColors.surfaceLight,
                          labelStyle: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.textMuted,
                          ),
                          onSelected: (_) => viewModel.setCanvasBlurSigma(blur),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
