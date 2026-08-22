import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// CapCut signature bottom category bar (Edit, Audio, Text, Stickers, Effects, Filters, Canvas, Adjust)
class BottomToolSelector extends StatelessWidget {
  final EditorViewModel viewModel;

  const BottomToolSelector({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.bottomNavHeight,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
          children: EditorCategory.values.map((category) {
            final isSelected = category == viewModel.activeDrawer;

            return InkWell(
              onTap: () {
                if (viewModel.activeDrawer == category) {
                  viewModel.closeDrawer();
                } else {
                  viewModel.openDrawer(category);
                }
              },
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      category.icon,
                      size: 22,
                      color: isSelected ? AppColors.primary : AppColors.iconDefault,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.label,
                      style: isSelected
                          ? AppTypography.bottomNavLabelSelected
                          : AppTypography.bottomNavLabel,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
