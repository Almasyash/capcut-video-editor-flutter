import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/services/audio_playback_service.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/bottom_tool_selector.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/adjust_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/audio_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/edit_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/effects_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/filters_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/stickers_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/top_navigation_bar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

/// The Main CapCut Video Editor Screen.
/// Contains:
/// 1. Top Navigation Bar (Aspect ratio, Undo/Redo, 1080P Export badge)
/// 2. Video Preview Screen at top
/// 3. Middle Action Toolbar (Split, Trim, Delete, Duplicate, Speed, Volume, Export)
/// 4. Interactive Multi-Track Timeline Track at bottom
/// 5. Signature Category Selector / Active Category Drawer Panels
class EditorScreen extends StatefulWidget {
  final Project? initialProject;

  const EditorScreen({super.key, this.initialProject});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late final EditorViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = EditorViewModel(initialProject: widget.initialProject);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _viewModel.pause();
      if (AudioPlaybackService.instance.isPlaying) {
        AudioPlaybackService.instance.pause();
      }
      _viewModel.saveCurrentProject();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.pause();
    if (AudioPlaybackService.instance.isInitialized) {
      AudioPlaybackService.instance.dispose();
    }
    VideoPlaybackService.instance.disposeAll();
    _viewModel.saveCurrentProject();
    _viewModel.dispose();
    super.dispose();
  }

  Widget _buildActiveDrawer(EditorCategory drawer) {
    switch (drawer) {
      case EditorCategory.edit:
        return EditDrawer(viewModel: _viewModel);
      case EditorCategory.audio:
        return AudioDrawer(viewModel: _viewModel);
      case EditorCategory.text:
        return TextDrawer(viewModel: _viewModel);
      case EditorCategory.stickers:
        return StickersDrawer(viewModel: _viewModel);
      case EditorCategory.effects:
        return EffectsDrawer(viewModel: _viewModel);
      case EditorCategory.filters:
        return FiltersDrawer(viewModel: _viewModel);
      case EditorCategory.adjust:
        return AdjustDrawer(viewModel: _viewModel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final activeDrawer = _viewModel.activeDrawer;

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

                // 5. Signature Bottom Category Selector or Active Drawer Panel
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: activeDrawer != null
                      ? KeyedSubtree(
                          key: ValueKey('drawer_${activeDrawer.name}'),
                          child: _buildActiveDrawer(activeDrawer),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('bottom_selector'),
                          child: BottomToolSelector(viewModel: _viewModel),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
