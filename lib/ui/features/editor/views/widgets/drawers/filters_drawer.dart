import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class FiltersDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const FiltersDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final active = viewModel.activeFilter;

    return Container(
      height: 200,
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
                    const Icon(Icons.photo_filter_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Color Filters (${active.name})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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

          // Intensity Slider (if filter != none)
          if (active.type != FilterType.none)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 2),
              child: Row(
                children: [
                  const Text('Intensity:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Expanded(
                    child: Slider(
                      value: active.intensity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      activeColor: AppColors.primary,
                      onChanged: (val) => viewModel.setFilterIntensity(val),
                    ),
                  ),
                  Text('${(active.intensity * 100).round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
            ),

          // Filters Presets Carousel
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: EditorFilter.presets.length,
              itemBuilder: (context, idx) {
                final filter = EditorFilter.presets[idx];
                final isSelected = active.type == filter.type;

                return GestureDetector(
                  onTap: () => viewModel.setFilter(filter),
                  child: Container(
                    width: 76,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.divider,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: filter.previewColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(filter.icon, size: 18, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          filter.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.primary : Colors.white70,
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
