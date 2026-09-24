import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/services/audio_playback_service.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/bottom_tool_selector.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/desktop_assets_panel.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/desktop_tools_panel.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/adjust_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/audio_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/edit_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/effects_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/filters_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/stickers_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/transitions_drawer.dart';
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
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = EditorViewModel(
      initialProject: widget.initialProject,
      enableMockFallback: false,
    );
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
    _keyboardFocusNode.dispose();
    _viewModel.pause();
    if (AudioPlaybackService.instance.isInitialized) {
      AudioPlaybackService.instance.dispose();
    }
    VideoPlaybackService.instance.disposeAll();
    _viewModel.saveCurrentProject();
    _viewModel.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Do not intercept shortcuts when user is actively editing text in an input field
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    // Shortcut handling
    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Space -> Play / Pause toggle
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _viewModel.togglePlayPause();
      return KeyEventResult.handled;
    }

    // Ctrl + Z -> Undo
    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (_viewModel.canUndo) _viewModel.undo();
      return KeyEventResult.handled;
    }

    // Ctrl + Y or Ctrl + Shift + Z -> Redo
    if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) ||
        (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyZ)) {
      if (_viewModel.canRedo) _viewModel.redo();
      return KeyEventResult.handled;
    }

    // Ctrl + X -> Cut
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      _viewModel.cutSelected();
      return KeyEventResult.handled;
    }

    // Ctrl + C -> Copy
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _viewModel.copySelected();
      return KeyEventResult.handled;
    }

    // Ctrl + V -> Paste
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _viewModel.pasteAtPlayhead();
      return KeyEventResult.handled;
    }

    // Ctrl + D -> Duplicate
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
      _viewModel.duplicateSelectedItem();
      return KeyEventResult.handled;
    }

    // Ctrl + I -> Import Media
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyI) {
      _viewModel.importVideoAsset();
      return KeyEventResult.handled;
    }

    // S -> Split active clip at playhead
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      if (_viewModel.selectedTextId != null) {
        _viewModel.splitTextAtPlayhead();
      } else if (_viewModel.selectedAudioTrack != null) {
        _viewModel.splitAudioAtPlayhead();
      } else if (_viewModel.selectedOverlay != null) {
        _viewModel.splitOverlayAtPlayhead();
      } else {
        _viewModel.splitClipAtPlayhead();
      }
      return KeyEventResult.handled;
    }

    // Q -> Left Cut (Trim head to playhead)
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyQ) {
      if (_viewModel.selectedTextId != null) {
        _viewModel.trimTextLeftToPlayhead();
      } else if (_viewModel.selectedAudioTrack != null) {
        _viewModel.trimAudioLeftToPlayhead();
      } else {
        _viewModel.trimLeftToPlayhead();
      }
      return KeyEventResult.handled;
    }

    // W -> Right Cut (Trim tail to playhead)
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyW) {
      if (_viewModel.selectedTextId != null) {
        _viewModel.trimTextRightToPlayhead();
      } else if (_viewModel.selectedAudioTrack != null) {
        _viewModel.trimAudioRightToPlayhead();
      } else {
        _viewModel.trimRightToPlayhead();
      }
      return KeyEventResult.handled;
    }

    // Delete / Backspace -> Delete selected element
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _viewModel.deleteSelectedItem();
      return KeyEventResult.handled;
    }

    // Arrow Right -> Directional jump to next boundary (cut, start, end)
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _viewModel.seekToNextBoundary();
      return KeyEventResult.handled;
    }

    // Arrow Left -> Directional jump to previous boundary (cut, start, end)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _viewModel.seekToPreviousBoundary();
      return KeyEventResult.handled;
    }

    // Arrow Up / Home -> Start of timeline
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.home) {
      if (_viewModel.isPlaying) _viewModel.pause();
      _viewModel.seekTo(0.0);
      return KeyEventResult.handled;
    }

    // Arrow Down / End -> End of timeline
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.end) {
      if (_viewModel.isPlaying) _viewModel.pause();
      _viewModel.seekTo(_viewModel.totalDurationInSeconds);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
      case EditorCategory.transitions:
        return TransitionsDrawer(viewModel: _viewModel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          final activeDrawer = _viewModel.activeDrawer;

          return Focus(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 850;

                    if (!isDesktop) {
                      // Mobile Layout (100% identical to original layout)
                      return Column(
                        children: [
                          // 1. Top Navigation Bar
                          TopNavigationBar(viewModel: _viewModel),

                          // 2. Video Preview Screen at top (Flexible/Responsive)
                          Expanded(
                            flex: 5,
                            child: VideoPreviewSection(
                              key: const ValueKey('mobile_video_preview'),
                              viewModel: _viewModel,
                            ),
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
                      );
                    }

                    // Professional 3-Panel NLE Desktop Layout
                    return Column(
                      children: [
                        // 1. Top Navigation Bar
                        TopNavigationBar(viewModel: _viewModel),

                        // 2. Middle Row: Left Panel (Media Assets) + Center Viewport + Right Panel (Tools Inspector)
                        Expanded(
                          flex: 5,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left Panel: Project Media Library
                              DesktopAssetsPanel(viewModel: _viewModel),

                              // Center Panel: Video Viewport Canvas
                              Expanded(
                                child: VideoPreviewSection(
                                  key: const ValueKey('desktop_video_preview'),
                                  viewModel: _viewModel,
                                ),
                              ),

                              // Right Panel: Tools & Category Drawers Inspector
                              DesktopToolsPanel(viewModel: _viewModel),
                            ],
                          ),
                        ),

                        // 3. Action Toolbar
                        ActionToolbar(viewModel: _viewModel),

                        // 4. Bottom Timeline Track
                        Expanded(
                          flex: 4,
                          child: TimelineSection(viewModel: _viewModel),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
