import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/bottom_tool_selector.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/top_navigation_bar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

/// The Main CapCut Video Editor Screen.
/// Contains:
/// 1. Top Navigation Bar (Aspect ratio, Undo/Redo, 1080P Export badge)
/// 2. Video Preview Screen at top
/// 3. Middle Action Toolbar (Split, Trim, Delete, Duplicate, Speed, Volume, Export)
/// 4. Interactive Multi-Track Timeline Track at bottom
/// 5. Signature Category Selector (Edit, Audio, Text, Filters, etc.)
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = EditorViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 1. Top Navigation Bar
                TopNavigationBar(viewModel: _viewModel),

                // 2. Video Preview Screen at top (Flexible/Responsive)
                Expanded(
                  flex: 5,
                  child: VideoPreviewSection(viewModel: _viewModel),
                ),

                // 3. Action Toolbar in between (Split, Trim, Delete, Export)
                ActionToolbar(viewModel: _viewModel),

                // 4. Timeline Track at bottom (Scrollable tracks, ruler, playhead)
                Expanded(
                  flex: 4,
                  child: TimelineSection(viewModel: _viewModel),
                ),

                // 5. Signature Bottom Category Selector
                BottomToolSelector(viewModel: _viewModel),
              ],
            ),
          ),
        );
      },
    );
  }
}
