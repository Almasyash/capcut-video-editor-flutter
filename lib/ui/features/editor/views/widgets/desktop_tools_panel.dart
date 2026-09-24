import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/adjust_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/audio_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/edit_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/effects_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/filters_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/stickers_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/transitions_drawer.dart';

/// Desktop right-hand Tools & Properties inspector panel
class DesktopToolsPanel extends StatefulWidget {
  final EditorViewModel viewModel;

  const DesktopToolsPanel({
    super.key,
    required this.viewModel,
  });

  @override
  State<DesktopToolsPanel> createState() => _DesktopToolsPanelState();
}

class _DesktopToolsPanelState extends State<DesktopToolsPanel> {
  EditorCategory _selectedCategory = EditorCategory.edit;

  @override
  void initState() {
    super.initState();
    if (widget.viewModel.activeDrawer != null) {
      _selectedCategory = widget.viewModel.activeDrawer!;
    }
  }

  Widget _buildDrawerContent(EditorCategory category) {
    switch (category) {
      case EditorCategory.edit:
        return EditDrawer(viewModel: widget.viewModel, isDesktop: true);
      case EditorCategory.audio:
        return AudioDrawer(viewModel: widget.viewModel);
      case EditorCategory.text:
        return TextDrawer(viewModel: widget.viewModel);
      case EditorCategory.stickers:
        return StickersDrawer(viewModel: widget.viewModel);
      case EditorCategory.effects:
        return EffectsDrawer(viewModel: widget.viewModel);
      case EditorCategory.filters:
        return FiltersDrawer(viewModel: widget.viewModel);
      case EditorCategory.adjust:
        return AdjustDrawer(viewModel: widget.viewModel);
      case EditorCategory.transitions:
        return TransitionsDrawer(viewModel: widget.viewModel, isDesktop: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sync with viewModel.activeDrawer if updated externally
    if (widget.viewModel.activeDrawer != null && widget.viewModel.activeDrawer != _selectedCategory) {
      _selectedCategory = widget.viewModel.activeDrawer!;
    }

    final categories = [
      (EditorCategory.edit, 'Edit', Icons.tune_rounded),
      (EditorCategory.audio, 'Audio', Icons.audiotrack_rounded),
      (EditorCategory.text, 'Text', Icons.text_fields_rounded),
      (EditorCategory.stickers, 'Stickers', Icons.emoji_emotions_rounded),
      (EditorCategory.effects, 'Effects', Icons.auto_awesome_rounded),
      (EditorCategory.filters, 'Filters', Icons.filter_vintage_rounded),
      (EditorCategory.adjust, 'Adjust', Icons.contrast_rounded),
      (EditorCategory.transitions, 'Transitions', Icons.transform_rounded),
    ];

    return Container(
      width: 416,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header category tabs wrapped to multiple rows
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat.$1;
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() => _selectedCategory = cat.$1);
                    widget.viewModel.openDrawer(cat.$1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat.$3,
                          size: 13,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          cat.$2,
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Drawer body
          Expanded(
            child: SingleChildScrollView(
              child: _buildDrawerContent(_selectedCategory),
            ),
          ),
        ],
      ),
    );
  }
}
