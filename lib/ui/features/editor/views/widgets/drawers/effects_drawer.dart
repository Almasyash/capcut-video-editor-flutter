import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class EffectsDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const EffectsDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final active = viewModel.activeEffect;

    return Container(
      height: 180,
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
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Text('Video Effects (${active.name})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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

          // Effects List
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: VideoEffect.presets.length,
              itemBuilder: (context, idx) {
                final effect = VideoEffect.presets[idx];
                final isSelected = active.type == effect.type;

                return GestureDetector(
                  onTap: () => viewModel.setEffect(effect),
                  child: Container(
                    width: 78,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? effect.color.withValues(alpha: 0.2) : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      border: Border.all(
                        color: isSelected ? effect.color : AppColors.divider,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(effect.icon, color: isSelected ? effect.color : AppColors.iconDefault, size: 26),
                        const SizedBox(height: 8),
                        Text(
                          effect.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : AppColors.textMuted,
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
    );
  }
}
