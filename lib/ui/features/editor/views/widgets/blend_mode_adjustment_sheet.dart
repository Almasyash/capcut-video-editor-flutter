import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class BlendModeAdjustmentSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const BlendModeAdjustmentSheet({super.key, required this.viewModel});

  @override
  State<BlendModeAdjustmentSheet> createState() => _BlendModeAdjustmentSheetState();
}

class _BlendModeAdjustmentSheetState extends State<BlendModeAdjustmentSheet> {
  late BlendMode _selectedMode;

  final List<(BlendMode, String, String)> _supportedModes = [
    (BlendMode.srcOver, 'Normal', 'Standard opacity composition'),
    (BlendMode.multiply, 'Multiply', 'Darkens base with layer (shadows)'),
    (BlendMode.screen, 'Screen', 'Lightens base with layer (highlights)'),
    (BlendMode.overlay, 'Overlay', 'Multiplies darks, screens lights'),
    (BlendMode.darken, 'Darken', 'Keeps darkest pixels of each channel'),
    (BlendMode.lighten, 'Lighten', 'Keeps lightest pixels of each channel'),
    (BlendMode.colorDodge, 'Color Dodge', 'Brightens base color to reflect layer'),
    (BlendMode.softLight, 'Soft Light', 'Subtle darkening/lightening'),
    (BlendMode.hardLight, 'Hard Light', 'Strong highlights and shadows'),
    (BlendMode.difference, 'Difference', 'Subtracts color channels'),
    (BlendMode.exclusion, 'Exclusion', 'Lower contrast difference'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.viewModel.selectedClip?.blendMode ?? BlendMode.srcOver;
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.layers_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Blending Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                itemCount: _supportedModes.length,
                itemBuilder: (context, idx) {
                  final (mode, name, desc) = _supportedModes[idx];
                  final isSelected = _selectedMode == mode;

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _selectedMode = mode);
                      widget.viewModel.setClipBlendMode(mode);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: isSelected ? AppColors.primary : AppColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? AppColors.primary : Colors.white,
                                  ),
                                ),
                                Text(
                                  desc,
                                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
