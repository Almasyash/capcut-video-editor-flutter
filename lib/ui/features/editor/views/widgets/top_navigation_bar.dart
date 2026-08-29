import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'export_modal_sheet.dart';

/// Top bar in Mahmas Studio containing Brand Badge, Aspect Ratio switcher, Undo/Redo, and 1080P Export badge
class TopNavigationBar extends StatelessWidget {
  final EditorViewModel viewModel;

  const TopNavigationBar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Home / Back Button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: AppColors.textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'Home & Drafts',
            onPressed: () {
              viewModel.saveCurrentProject();
              Navigator.of(context).maybePop();
            },
          ),

          // Left: Mahmas Studio Brand Badge
          _buildBrandBadge(context),

          const SizedBox(width: 2),

          // Center-Left: Aspect Ratio Selector Dropdown/Badge
          _buildAspectRatioSelector(context),

          const Spacer(),

          // Voice Feedback (TTS) Toggle Button
          _buildTtsToggleButton(),

          // Center-Right: Undo & Redo Buttons
          _buildUndoRedoButtons(),

          const SizedBox(width: 2),

          // Right: Resolution & Export Button
          _buildExportButton(context),
        ],
      ),
    );
  }

  Widget _buildTtsToggleButton() {
    final isEnabled = viewModel.isTtsEnabled;
    return InkWell(
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      onTap: () => viewModel.toggleTts(),
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: Icon(
          isEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 15,
          color: isEnabled ? AppColors.primary : AppColors.iconDisabled,
        ),
      ),
    );
  }

  Widget _buildBrandBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.movie_filter_rounded,
                size: 12,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Mahmas',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAspectRatioSelector(BuildContext context) {
    return PopupMenuButton<AspectRatioPreset>(
      initialValue: viewModel.aspectRatio,
      tooltip: 'Change Aspect Ratio',
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
      onSelected: (preset) => viewModel.setAspectRatio(preset),
      itemBuilder: (context) {
        return AspectRatioPreset.values.map((preset) {
          final isSelected = preset == viewModel.aspectRatio;
          return PopupMenuItem<AspectRatioPreset>(
            value: preset,
            child: Row(
              children: [
                Icon(
                  Icons.aspect_ratio_rounded,
                  size: 16,
                  color: isSelected ? AppColors.primary : AppColors.iconDefault,
                ),
                const SizedBox(width: AppDimensions.sm),
                Text(
                  preset.label,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppDimensions.xs),
                Text(
                  '(${preset.description})',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.aspect_ratio_rounded, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              viewModel.aspectRatio.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildUndoRedoButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.undo_rounded,
            size: 18,
            color: viewModel.canUndo ? AppColors.iconDefault : AppColors.iconDisabled,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: viewModel.canUndo ? viewModel.undo : null,
          tooltip: 'Undo',
        ),
        IconButton(
          icon: Icon(
            Icons.redo_rounded,
            size: 18,
            color: viewModel.canRedo ? AppColors.iconDefault : AppColors.iconDisabled,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: viewModel.canRedo ? viewModel.redo : null,
          tooltip: 'Redo',
        ),
      ],
    );
  }

  Widget _buildExportButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => ExportModalSheet(viewModel: viewModel),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: AppColors.exportGradient,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              viewModel.exportSettings.resolution.label,
              style: AppTypography.badgeText,
            ),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
