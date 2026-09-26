import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/enums/interaction_mode.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/domain/models/clip_spatial_transform.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/interactive_transform_canvas.dart';
import 'package:capcut_video_editor/core/utils/chroma_key_helper.dart';
import 'package:capcut_video_editor/core/utils/font_helper.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';

/// Top Video Preview Screen containing the live video canvas, aspect-ratio viewport,
/// color grading LUT filters, adjustments, Picture-in-Picture (PIP) layers,
/// active stickers, subtitles, and hardware-accelerated playback surface.
class VideoPreviewSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const VideoPreviewSection({super.key, required this.viewModel});

  @override
  State<VideoPreviewSection> createState() => VideoPreviewSectionState();
}

class VideoPreviewSectionState extends State<VideoPreviewSection> {
  EditorViewModel get viewModel => widget.viewModel;

  final GlobalKey _canvasKey = GlobalKey();
  VideoPlayerSession? _session;
  String? _loadedPath;
  String? _lastActiveClipId;
  bool _isPlaying = false;
  double _lastPlayheadPosition = -1.0;

  OverlayEntry? _fullScreenEntry;
  bool get isFullScreen => _fullScreenEntry != null;

  void _enterFullScreen() {
    _fullScreenEntry = OverlayEntry(
      builder: (ctx) => _buildFullScreenOverlay(ctx),
    );
    Overlay.of(context).insert(_fullScreenEntry!);
    setState(() {});
  }

  void _exitFullScreen() {
    _fullScreenEntry?.remove();
    _fullScreenEntry = null;
    widget.viewModel.refreshTimelineLayout();
    if (mounted) setState(() {});
  }

  void exitFullScreen() => _exitFullScreen();

  @override
  void initState() {
    super.initState();
    _syncPlayerWithModel();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayerWithModel();
    if (_fullScreenEntry != null && _fullScreenEntry!.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fullScreenEntry != null && _fullScreenEntry!.mounted) {
          _fullScreenEntry?.markNeedsBuild();
        }
      });
    }
  }

  @override
  void dispose() {
    _fullScreenEntry?.remove();
    _fullScreenEntry = null;
    if (_session != null) {
      VideoPlaybackService.instance.disposeSession(_session!.textureId);
      _session = null;
    }
    if (_secondarySession != null) {
      VideoPlaybackService.instance.disposeSession(_secondarySession!.textureId);
      _secondarySession = null;
    }
    super.dispose();
  }

  VideoPlayerSession? _secondarySession;
  String? _secondaryLoadedPath;
  String? _secondaryClipId;

  void _syncPlayerWithModel() {
    final activeTransition = widget.viewModel.activeTransitionAtPlayhead;

    if (activeTransition != null) {
      _syncTransitionPlayback(activeTransition);
    } else {
      _syncNormalPlayback();
    }
  }

  void _syncNormalPlayback() {
    if (_secondarySession != null) {
      VideoPlaybackService.instance.disposeSession(_secondarySession!.textureId);
      _secondarySession = null;
      _secondaryLoadedPath = null;
      _secondaryClipId = null;
    }

    final activeClip = widget.viewModel.currentActiveClipAtPlayhead;
    final activeClipStart = widget.viewModel.activeClipStartTimeAtPlayhead;
    String? localPath;
    if (activeClip is VideoClip) {
      final asset = widget.viewModel.getAssetById(activeClip.assetId);
      if (asset != null && !asset.isPhoto) {
        localPath = asset.localPath;
      }
    }

    // Calculate source offset in seconds for current active clip
    final deltaInClipSec = (widget.viewModel.playheadPosition - activeClipStart).clamp(
      0.0,
      activeClip is VideoClip ? activeClip.durationInSeconds : 1000.0,
    );
    final sourceOffsetSec = (activeClip is VideoClip)
        ? (activeClip.speedCurve != null
            ? (activeClip.trimStart.inMilliseconds / 1000.0) +
                ((activeClip.trimEnd - activeClip.trimStart).inMilliseconds / 1000.0) *
                    activeClip.speedCurve!.getSourceProgressAt(
                      (deltaInClipSec / math.max(0.001, activeClip.durationInSeconds)).clamp(0.0, 1.0),
                    )
            : (activeClip.trimStart.inMilliseconds / 1000.0) + (deltaInClipSec * activeClip.speed))
        : deltaInClipSec;
    final sourceOffsetMs = (sourceOffsetSec * 1000).round();

    // 1. If path changed, initialize new native player session
    if (localPath != _loadedPath) {
      _loadedPath = localPath;
      _lastActiveClipId = activeClip?.id;
      if (_session != null) {
        VideoPlaybackService.instance.disposeSession(_session!.textureId);
        _session = null;
      }

      if (localPath != null && !localPath.startsWith('content://') && !kIsWeb && File(localPath).existsSync()) {
        VideoPlaybackService.instance.createSession(localPath).then((session) {
          if (mounted && _loadedPath == localPath) {
            setState(() {
              _session = session;
            });
            if (session != null && activeClip is VideoClip) {
              VideoPlaybackService.instance.setVolume(session.textureId, activeClip.effectiveVolume);
              final initialSpeed = activeClip.speedCurve != null
                  ? activeClip.speedCurve!.evaluateSpeedAt(
                      (deltaInClipSec / math.max(0.001, activeClip.durationInSeconds)).clamp(0.0, 1.0),
                    )
                  : activeClip.speed;
              VideoPlaybackService.instance.setSpeed(session.textureId, initialSpeed);
              if (widget.viewModel.isPlaying) {
                debugPrint('[AUTO_PLAY_TRACE] VideoPreviewSection calling play because viewModel.isPlaying is TRUE (pos=${sourceOffsetMs}ms)');
                VideoPlaybackService.instance.play(session.textureId, position: Duration(milliseconds: sourceOffsetMs));
                _isPlaying = true;
              } else {
                // Seek to the current position; on Windows force a repaint after seek
                // so the Texture widget shows frame content instead of black.
                VideoPlaybackService.instance
                    .seekTo(session.textureId, Duration(milliseconds: sourceOffsetMs))
                    .then((_) {
                  if (mounted) {
                    // Small delay to let MF grab the first decoded frame into texture
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (mounted) setState(() {});
                    });
                  }
                });
                _isPlaying = false;
              }
            }
          }
        });
      }
      return;
    }

    // 2. Sync dynamic volume & speed properties
    if (_session != null && _session!.isInitialized && activeClip is VideoClip) {
      VideoPlaybackService.instance.setVolume(_session!.textureId, activeClip.effectiveVolume);
      final currentClipSpeed = activeClip.speedCurve != null
          ? activeClip.speedCurve!.evaluateSpeedAt(
              (deltaInClipSec / math.max(0.001, activeClip.durationInSeconds)).clamp(0.0, 1.0),
            )
          : activeClip.speed;
      VideoPlaybackService.instance.setSpeed(_session!.textureId, currentClipSpeed);
    }

    // 3. Handle clip boundary switches on the same media file (e.g. split clips)
    if (_session != null && _session!.isInitialized && activeClip != null && activeClip.id != _lastActiveClipId) {
      _lastActiveClipId = activeClip.id;
      VideoPlaybackService.instance.seekTo(_session!.textureId, Duration(milliseconds: sourceOffsetMs));
    }

    // 4. Sync play/pause state with authoritative start position
    if (_session != null && _session!.isInitialized) {
      if (widget.viewModel.isPlaying && !_isPlaying) {
        _isPlaying = true;
        debugPrint('[AUTO_PLAY_TRACE] VideoPreviewSection syncing play state at target pos=${sourceOffsetMs}ms');
        VideoPlaybackService.instance.play(_session!.textureId, position: Duration(milliseconds: sourceOffsetMs));
      } else if (!widget.viewModel.isPlaying && _isPlaying) {
        _isPlaying = false;
        debugPrint('[AUTO_PLAY_TRACE] VideoPreviewSection syncing pause state (pos=${sourceOffsetMs}ms)');
        VideoPlaybackService.instance.pause(_session!.textureId);
        _lastPlayheadPosition = widget.viewModel.playheadPosition;
        VideoPlaybackService.instance.seekTo(
          _session!.textureId,
          Duration(milliseconds: sourceOffsetMs),
        );
      }

      // 5. Sync seek position if changed while paused or scrubbed
      if (!widget.viewModel.isPlaying && (_lastPlayheadPosition - widget.viewModel.playheadPosition).abs() > 0.02) {
        _lastPlayheadPosition = widget.viewModel.playheadPosition;
        VideoPlaybackService.instance.seekTo(
          _session!.textureId,
          Duration(milliseconds: sourceOffsetMs),
        );
      }
    }
  }

  void _syncTransitionPlayback(ActiveTransitionState trans) {
    final leftClip = trans.leftClip;
    final rightClip = trans.rightClip;
    String? pathA;
    String? pathB;

    final assetA = widget.viewModel.getAssetById(leftClip.assetId);
    if (assetA != null && !assetA.isPhoto) {
      pathA = assetA.localPath;
    }
    final assetB = widget.viewModel.getAssetById(rightClip.assetId);
    if (assetB != null && !assetB.isPhoto) {
      pathB = assetB.localPath;
    }

    // Primary session: Clip A
    _lastActiveClipId = leftClip.id;
    if (pathA != _loadedPath) {
      _loadedPath = pathA;
      if (_session != null) {
        VideoPlaybackService.instance.disposeSession(_session!.textureId);
        _session = null;
      }
      if (pathA != null && !pathA.startsWith('content://') && !kIsWeb && File(pathA).existsSync()) {
        VideoPlaybackService.instance.createSession(pathA).then((session) {
          if (mounted && _loadedPath == pathA) {
            setState(() {
              _session = session;
            });
            if (session != null) {
              VideoPlaybackService.instance.setVolume(session.textureId, leftClip.effectiveVolume * (1.0 - trans.progress));
              VideoPlaybackService.instance.setSpeed(session.textureId, leftClip.speed);
              if (widget.viewModel.isPlaying) {
                VideoPlaybackService.instance.play(session.textureId, position: Duration(milliseconds: trans.sourceOffsetMsA));
              } else {
                VideoPlaybackService.instance.seekTo(session.textureId, Duration(milliseconds: trans.sourceOffsetMsA));
              }
            }
          }
        });
      }
    } else if (_session != null && _session!.isInitialized) {
      VideoPlaybackService.instance.setVolume(sessionSafeId(_session!), leftClip.effectiveVolume * (1.0 - trans.progress));
      VideoPlaybackService.instance.setSpeed(sessionSafeId(_session!), leftClip.speed);
    }

    // Secondary session: Clip B
    _secondaryClipId = rightClip.id;
    if (pathB != _secondaryLoadedPath) {
      _secondaryLoadedPath = pathB;
      if (_secondarySession != null) {
        VideoPlaybackService.instance.disposeSession(_secondarySession!.textureId);
        _secondarySession = null;
      }
      if (pathB != null && !pathB.startsWith('content://') && !kIsWeb && File(pathB).existsSync()) {
        VideoPlaybackService.instance.createSession(pathB).then((session) {
          if (mounted && _secondaryLoadedPath == pathB) {
            setState(() {
              _secondarySession = session;
            });
            if (session != null) {
              VideoPlaybackService.instance.setVolume(session.textureId, rightClip.effectiveVolume * trans.progress);
              VideoPlaybackService.instance.setSpeed(session.textureId, rightClip.speed);
              if (widget.viewModel.isPlaying) {
                VideoPlaybackService.instance.play(session.textureId, position: Duration(milliseconds: trans.sourceOffsetMsB));
              } else {
                VideoPlaybackService.instance.seekTo(session.textureId, Duration(milliseconds: trans.sourceOffsetMsB));
              }
            }
          }
        });
      }
    } else if (_secondarySession != null && _secondarySession!.isInitialized) {
      VideoPlaybackService.instance.setVolume(sessionSafeId(_secondarySession!), rightClip.effectiveVolume * trans.progress);
      VideoPlaybackService.instance.setSpeed(sessionSafeId(_secondarySession!), rightClip.speed);
    }

    // Play / Pause / Scrub sync across both sessions
    if (widget.viewModel.isPlaying && !_isPlaying) {
      _isPlaying = true;
      if (_session != null && _session!.isInitialized) {
        VideoPlaybackService.instance.play(_session!.textureId, position: Duration(milliseconds: trans.sourceOffsetMsA));
      }
      if (_secondarySession != null && _secondarySession!.isInitialized) {
        VideoPlaybackService.instance.play(_secondarySession!.textureId, position: Duration(milliseconds: trans.sourceOffsetMsB));
      }
    } else if (!widget.viewModel.isPlaying && _isPlaying) {
      _isPlaying = false;
      if (_session != null && _session!.isInitialized) {
        VideoPlaybackService.instance.pause(_session!.textureId);
        VideoPlaybackService.instance.seekTo(_session!.textureId, Duration(milliseconds: trans.sourceOffsetMsA));
      }
      if (_secondarySession != null && _secondarySession!.isInitialized) {
        VideoPlaybackService.instance.pause(_secondarySession!.textureId);
        VideoPlaybackService.instance.seekTo(_secondarySession!.textureId, Duration(milliseconds: trans.sourceOffsetMsB));
      }
      _lastPlayheadPosition = widget.viewModel.playheadPosition;
    } else if (!widget.viewModel.isPlaying && (_lastPlayheadPosition - widget.viewModel.playheadPosition).abs() > 0.02) {
      _lastPlayheadPosition = widget.viewModel.playheadPosition;
      if (_session != null && _session!.isInitialized) {
        VideoPlaybackService.instance.seekTo(_session!.textureId, Duration(milliseconds: trans.sourceOffsetMsA));
      }
      if (_secondarySession != null && _secondarySession!.isInitialized) {
        VideoPlaybackService.instance.seekTo(_secondarySession!.textureId, Duration(milliseconds: trans.sourceOffsetMsB));
      }
    }
  }

  int sessionSafeId(VideoPlayerSession s) => s.textureId;

  @override
  Widget build(BuildContext context) {
    // Always show canvas centered — fullscreen overlay is an OverlayEntry on top
    return Container(
      width: double.infinity,
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.sm),
          child: FittedBox(
            fit: BoxFit.contain,
            child: _buildCanvasContainer(),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasContainer({double? customWidth, double? customHeight}) {
    final activeClip = viewModel.currentActiveClipAtPlayhead;
    final activeTransition = viewModel.activeTransitionAtPlayhead;
    final activeOverlays = viewModel.activeOverlayClipsAtPlayhead;
    final activeStickers = viewModel.activeStickersAtPlayhead;
    final activeTexts = viewModel.activeTextOverlaysAtPlayhead;
    final targetRatio = viewModel.aspectRatio.ratio ?? (9 / 16);

    final filter = viewModel.activeFilter.getColorFilter();
    final adjustments = viewModel.colorAdjustments.getColorFilter();

    final width = customWidth ?? 360.0;
    final height = customHeight ?? (width / targetRatio);

    return SizedBox(
      key: _canvasKey,
      width: width,
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: viewModel.canvasBackgroundColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.surfaceHighlight, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Primary Video Canvas with Transformations, Filters & Adjustments
            if (activeTransition != null)
              _buildTransitionCanvas(activeTransition, filter, adjustments)
            else if (activeClip != null)
              _buildMainVideoCanvas(activeClip, filter, adjustments)
            else
              const Center(
                child: Text(
                  'No media on timeline',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),

            // 2. Visual Effects Overlay (Glitch, VHS, RGB, Sparkle)
            if (viewModel.activeEffect.type != VideoEffectType.none)
              _buildEffectOverlay(viewModel.activeEffect),

            // 3. Secondary Picture-in-Picture (PIP) Overlay Layers
            ...activeOverlays.map((overlay) => _buildOverlayLayer(overlay)),

            // 4. Active Stickers Overlays
            ...activeStickers.map((sticker) => _buildStickerOverlay(sticker)),

            // 5. Tap to Play / Pause / Deselect Gesture Overlay
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (viewModel.selectedTextId != null) {
                  viewModel.selectText(null);
                } else if (viewModel.isCropModeActive) {
                  viewModel.setCropMode(false);
                } else if (viewModel.selectedClipId == null) {
                  viewModel.togglePlayPause();
                }
              },
              child: AnimatedOpacity(
                opacity: viewModel.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: IgnorePointer(
                    ignoring: viewModel.isPlaying,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: viewModel.togglePlayPause,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 6. Active Text / Subtitle Overlays (Positioned on top for direct fluent touch manipulation)
            ...activeTexts.map((text) => _buildTextOverlay(text, canvasWidth: width, canvasHeight: height)),

            // 7. Interactive Crop Area Resize Handles (Priority when crop mode active)
            if (viewModel.isCropModeActive ||
                (viewModel.selectedClip?.mask?.isActive == true && viewModel.selectedTextId == null))
              _CropAreaHandlesOverlay(
                viewModel: viewModel,
                canvasWidth: width,
                canvasHeight: height,
                canvasKey: _canvasKey,
              ),

            // 7. Top-Left: Badges (Aspect Ratio & Active Filter)
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      viewModel.aspectRatio.label,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (viewModel.activeFilter.type != EditorFilter.presets.first.type) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        viewModel.activeFilter.name,
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  if (activeTransition != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentPurple.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TRANSITION: ${activeTransition.transition.type.name.toUpperCase()} ${(activeTransition.progress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Top-Right: Fullscreen Toggle Button
            if (!isFullScreen)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _enterFullScreen,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: const Icon(
                        Icons.fullscreen_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

            // 8. Bottom-Center: Live Timecode Pill
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        TimeFormatter.formatSeconds(viewModel.playheadPosition),
                        style: AppTypography.timecodeLarge,
                      ),
                      const Text(' / ', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      Text(
                        TimeFormatter.formatSeconds(viewModel.totalDurationInSeconds),
                        style: AppTypography.timecodeMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenOverlay(BuildContext overlayContext) {
    final targetRatio = viewModel.aspectRatio.ratio ?? (9 / 16);

    return Material(
      color: Colors.black,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.keyF): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.space): DoNothingAndStopPropagationIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (intent) => _exitFullScreen(),
            ),
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.keyF) {
                  _exitFullScreen();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.space) {
                  viewModel.togglePlayPause();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth - 40;
                final maxH = constraints.maxHeight - 140;
                double w = maxW;
                double h = w / targetRatio;
                if (h > maxH) {
                  h = maxH;
                  w = h * targetRatio;
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Maximized Centered Canvas
                    Center(
                      child: _buildCanvasContainer(customWidth: w, customHeight: h),
                    ),

                    // Top Floating Header Bar with Minimize Button
                    Positioned(
                      top: 16,
                      left: 24,
                      right: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam_rounded, size: 14, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${viewModel.aspectRatio.label} • Fullscreen Mode',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _exitFullScreen,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primary, width: 1.2),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen_exit_rounded, color: AppColors.primary, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Minimize (Esc)',
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Floating Scrubber & Play/Pause Controls
                    Positioned(
                      bottom: 20,
                      left: 24,
                      right: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: AppColors.primary,
                                size: 26,
                              ),
                              onPressed: viewModel.togglePlayPause,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              TimeFormatter.formatSeconds(viewModel.playheadPosition),
                              style: AppTypography.timecodeLarge,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  activeTrackColor: AppColors.primary,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: AppColors.primary,
                                ),
                                child: Slider(
                                  value: viewModel.playheadPosition.clamp(0.0, math.max(0.01, viewModel.totalDurationInSeconds)),
                                  min: 0.0,
                                  max: math.max(0.01, viewModel.totalDurationInSeconds),
                                  onChanged: (pos) => viewModel.seekTo(pos),
                                ),
                              ),
                            ),
                            Text(
                              TimeFormatter.formatSeconds(viewModel.totalDurationInSeconds),
                              style: AppTypography.timecodeMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  ),
);
  }

  Widget _buildTransitionCanvas(
    ActiveTransitionState state,
    ColorFilter? filter,
    ColorFilter? adjustments,
  ) {
    final outgoing = _buildSingleClipVisual(state.leftClip);
    final incoming = _buildSingleClipVisual(state.rightClip);
    final progress = state.progress;

    Widget effect;
    switch (state.transition.type) {
      case TransitionType.fade:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: (1.0 - progress).clamp(0.0, 1.0), child: outgoing),
            Opacity(opacity: progress.clamp(0.0, 1.0), child: incoming),
          ],
        );
        break;

      case TransitionType.dissolve:
        final smooth = progress * progress * (3 - 2 * progress);
        effect = Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: (1.0 - smooth).clamp(0.0, 1.0), child: outgoing),
            Opacity(opacity: smooth.clamp(0.0, 1.0), child: incoming),
          ],
        );
        break;

      case TransitionType.blackFade:
        if (progress < 0.5) {
          final outOpacity = (1.0 - (progress * 2.0)).clamp(0.0, 1.0);
          effect = Container(
            color: Colors.black,
            child: Opacity(opacity: outOpacity, child: outgoing),
          );
        } else {
          final inOpacity = ((progress - 0.5) * 2.0).clamp(0.0, 1.0);
          effect = Container(
            color: Colors.black,
            child: Opacity(opacity: inOpacity, child: incoming),
          );
        }
        break;

      case TransitionType.whiteFade:
        if (progress < 0.5) {
          final outOpacity = (1.0 - (progress * 2.0)).clamp(0.0, 1.0);
          effect = Container(
            color: Colors.white,
            child: Opacity(opacity: outOpacity, child: outgoing),
          );
        } else {
          final inOpacity = ((progress - 0.5) * 2.0).clamp(0.0, 1.0);
          effect = Container(
            color: Colors.white,
            child: Opacity(opacity: inOpacity, child: incoming),
          );
        }
        break;

      case TransitionType.slideLeft:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: Offset(-progress, 0.0),
              child: outgoing,
            ),
            FractionalTranslation(
              translation: Offset(1.0 - progress, 0.0),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.slideRight:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: Offset(progress, 0.0),
              child: outgoing,
            ),
            FractionalTranslation(
              translation: Offset(progress - 1.0, 0.0),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.slideUp:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: Offset(0.0, -progress),
              child: outgoing,
            ),
            FractionalTranslation(
              translation: Offset(0.0, 1.0 - progress),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.slideDown:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: Offset(0.0, progress),
              child: outgoing,
            ),
            FractionalTranslation(
              translation: Offset(0.0, progress - 1.0),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.wipeLeft:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: progress.clamp(0.0, 1.0),
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.wipeRight:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.zoomIn:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            Transform.scale(
              scale: progress.clamp(0.01, 1.0),
              child: Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.zoomOut:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            incoming,
            Transform.scale(
              scale: (1.0 - progress).clamp(0.01, 1.0),
              child: Opacity(
                opacity: (1.0 - progress).clamp(0.0, 1.0),
                child: outgoing,
              ),
            ),
          ],
        );
        break;

      case TransitionType.wipeUp:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: progress.clamp(0.0, 1.0),
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.wipeDown:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: progress.clamp(0.0, 1.0),
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.circle:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipOval(
              clipper: _CircleTransitionClipper(progress.clamp(0.0, 1.0)),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.radial:
        effect = Stack(
          fit: StackFit.expand,
          children: [
            outgoing,
            ClipPath(
              clipper: _RadialTransitionClipper(progress.clamp(0.0, 1.0)),
              child: incoming,
            ),
          ],
        );
        break;

      case TransitionType.blur:
        final blurSigma = (1.0 - (progress - 0.5).abs() * 2.0) * 15.0;
        effect = Stack(
          fit: StackFit.expand,
          children: [
            if (blurSigma > 0.1)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Opacity(opacity: (1.0 - progress).clamp(0.0, 1.0), child: outgoing),
              )
            else
              Opacity(opacity: (1.0 - progress).clamp(0.0, 1.0), child: outgoing),
            if (blurSigma > 0.1)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Opacity(opacity: progress.clamp(0.0, 1.0), child: incoming),
              )
            else
              Opacity(opacity: progress.clamp(0.0, 1.0), child: incoming),
          ],
        );
        break;

      case TransitionType.pixelate:
        final peak = (1.0 - (progress - 0.5).abs() * 2.0);
        effect = Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: (1.0 - progress).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.0 + peak * 0.05,
                child: outgoing,
              ),
            ),
            Opacity(
              opacity: progress.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.0 + peak * 0.05,
                child: incoming,
              ),
            ),
          ],
        );
        break;

      case TransitionType.none:
        effect = progress < 0.5 ? outgoing : incoming;
        break;
    }

    Widget videoContent = effect;
    if (filter != null) {
      videoContent = ColorFiltered(colorFilter: filter, child: videoContent);
    }
    if (adjustments != null) {
      videoContent = ColorFiltered(colorFilter: adjustments, child: videoContent);
    }
    if (viewModel.canvasBlurSigma > 0.0) {
      videoContent = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: viewModel.canvasBlurSigma,
          sigmaY: viewModel.canvasBlurSigma,
        ),
        child: videoContent,
      );
    }

    return videoContent;
  }

  Widget _buildSingleClipVisual(VideoClip clip) {
    final asset = viewModel.getAssetById(clip.assetId);
    final localPath = asset?.localPath;
    final thumbnailPath = asset?.thumbnailPath;
    final isPhoto = asset?.isPhoto ?? false;

    final hasLocalFile = localPath != null &&
        !localPath.startsWith('content://') &&
        !kIsWeb &&
        File(localPath).existsSync();

    final hasThumbnail = thumbnailPath != null &&
        !thumbnailPath.startsWith('content://') &&
        !kIsWeb &&
        File(thumbnailPath).existsSync();

    final isMissingMedia = localPath != null &&
        !localPath.startsWith('content://') &&
        !kIsWeb &&
        !hasLocalFile &&
        !hasThumbnail;

    Widget canvasChild;
    if (hasLocalFile) {
      if (isPhoto) {
        canvasChild = Image.file(
          File(localPath),
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stack) => _buildPlaceholderGraphic(clip),
        );
      } else {
        final isSessionA = (_lastActiveClipId == clip.id || viewModel.currentActiveClipAtPlayhead?.id == clip.id) &&
            _session != null &&
            _session!.isInitialized;
        final isSessionB = _secondaryClipId == clip.id &&
            _secondarySession != null &&
            _secondarySession!.isInitialized;

        if (isSessionA) {
          final liveTexture = Center(
            child: AspectRatio(
              aspectRatio: _session!.aspectRatio > 0 ? _session!.aspectRatio : 16 / 9,
              child: Texture(
                textureId: _session!.textureId,
                filterQuality: FilterQuality.medium,
              ),
            ),
          );

          if (hasThumbnail) {
            canvasChild = Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _session!.aspectRatio > 0 ? _session!.aspectRatio : 16 / 9,
                    child: Image.file(
                      File(thumbnailPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                liveTexture,
              ],
            );
          } else {
            canvasChild = liveTexture;
          }
        } else if (isSessionB) {
          canvasChild = Center(
            child: AspectRatio(
              aspectRatio: _secondarySession!.aspectRatio > 0 ? _secondarySession!.aspectRatio : 16 / 9,
              child: Texture(
                textureId: _secondarySession!.textureId,
                filterQuality: FilterQuality.medium,
              ),
            ),
          );
        } else if (hasThumbnail) {
          canvasChild = Image.file(
            File(thumbnailPath),
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => _buildPlaceholderGraphic(clip),
          );
        } else {
          canvasChild = _buildPlaceholderGraphic(clip);
        }
      }
    } else if (isMissingMedia) {
      canvasChild = _buildMissingMediaGraphic(clip);
    } else {
      canvasChild = _buildPlaceholderGraphic(clip);
    }

    final transform = ClipSpatialTransform.fromClip(clip);
    return Opacity(
      opacity: clip.opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: transform.toMatrix4(
          legacyRotationDegrees: clip.rotationDegrees,
          flipHorizontal: clip.flipHorizontal,
          flipVertical: clip.flipVertical,
        ),
        child: canvasChild,
      ),
    );
  }

  Widget _buildMainVideoCanvas(dynamic activeClip, ColorFilter? filter, ColorFilter? adjustments) {
    MediaAsset? asset;
    String? localPath;
    String? thumbnailPath;
    bool isPhoto = false;

    if (activeClip is VideoClip) {
      asset = viewModel.getAssetById(activeClip.assetId);
      localPath = asset?.localPath;
      thumbnailPath = asset?.thumbnailPath;
      isPhoto = asset?.isPhoto ?? false;
    }

    final hasLocalFile = localPath != null &&
        !localPath.startsWith('content://') &&
        !kIsWeb &&
        File(localPath).existsSync();

    final hasThumbnail = thumbnailPath != null &&
        !thumbnailPath.startsWith('content://') &&
        !kIsWeb &&
        File(thumbnailPath).existsSync();

    // Diagnostic logging for media resolution
    if (activeClip is VideoClip) {
      debugPrint(
        '[VideoPreviewSection] Clip "${activeClip.title}" (id: ${activeClip.id}, assetId: ${activeClip.assetId}) -> '
        'MediaAsset: ${asset?.name}, type: ${asset?.type}, localPath: $localPath (exists: $hasLocalFile), '
        'thumbnailPath: $thumbnailPath (exists: $hasThumbnail), isPlaying: ${viewModel.isPlaying}',
      );
    }

    final isMissingMedia = localPath != null &&
        !localPath.startsWith('content://') &&
        !kIsWeb &&
        !hasLocalFile &&
        !hasThumbnail;

    Widget canvasChild;

    if (hasLocalFile) {
      if (isPhoto) {
        // Still photo rendering
        canvasChild = Image.file(
          File(localPath),
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stack) => _buildPlaceholderGraphic(activeClip),
        );
      } else {
        // Real Video rendering: Uses native hardware decoded Flutter Texture when session is active,
        // and falls back seamlessly to extracted frame 0 thumbnail while attaching.
        Widget videoPlayerWidget;

        if (_session != null && _session!.isInitialized) {
          final liveTexture = Center(
            child: AspectRatio(
              aspectRatio: _session!.aspectRatio > 0 ? _session!.aspectRatio : 16 / 9,
              child: Texture(
                textureId: _session!.textureId,
                filterQuality: FilterQuality.medium,
              ),
            ),
          );

          if (hasThumbnail) {
            // Live hardware texture on top; thumbnail image underneath so that
            // while paused or seeking, the video canvas is never black.
            videoPlayerWidget = Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _session!.aspectRatio > 0 ? _session!.aspectRatio : 16 / 9,
                    child: Image.file(
                      File(thumbnailPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                liveTexture,
              ],
            );
          } else {
            videoPlayerWidget = liveTexture;
          }
        } else if (hasThumbnail) {
          videoPlayerWidget = Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.file(
                File(thumbnailPath),
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => _buildVideoPlaybackSurface(activeClip, localPath),
              ),
            ),
          );
        } else {
          videoPlayerWidget = _buildVideoPlaybackSurface(activeClip, localPath);
        }

        canvasChild = Stack(
          fit: StackFit.expand,
          children: [
            videoPlayerWidget,

            // Live Playback Indicator
            if (viewModel.isPlaying)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    border: Border.all(color: AppColors.primary, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'HARDWARE DECODED',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }
    } else if (isMissingMedia) {
      canvasChild = _buildMissingMediaGraphic(activeClip);
    } else {
      canvasChild = _buildPlaceholderGraphic(activeClip);
    }

    double clipTime = 0.0;
    if (activeClip is VideoClip) {
      final activeClipStart = viewModel.activeClipStartTimeAtPlayhead;
      clipTime = (viewModel.playheadPosition - activeClipStart).clamp(0.0, activeClip.durationInSeconds);
    }
    final VideoKeyframe? keyframe = activeClip is VideoClip ? viewModel.getInterpolatedKeyframe(activeClip, clipTime) : null;
    final animScale = keyframe?.scale ?? 1.0;
    final animRotation = keyframe?.rotationDegrees ?? (activeClip.rotationDegrees as num).toDouble();
    final animPosX = keyframe?.positionX ?? 0.0;
    final animPosY = keyframe?.positionY ?? 0.0;
    final animOpacity = (keyframe?.opacity ?? (activeClip.opacity as num).toDouble()).clamp(0.0, 1.0);

    final ClipSpatialTransform? keyframeTransform = (activeClip is VideoClip && activeClip.keyframes.isNotEmpty && keyframe != null)
        ? ClipSpatialTransform(
            clipId: activeClip.id,
            xPos: animPosX,
            yPos: animPosY,
            scale: animScale,
            rotationAngle: animRotation * math.pi / 180.0,
          )
        : null;

    Widget visualChild = Opacity(
      opacity: animOpacity,
      child: canvasChild,
    );

    // Apply color filter LUT & adjustments
    if (filter != null) {
      visualChild = ColorFiltered(colorFilter: filter, child: visualChild);
    }
    if (adjustments != null) {
      visualChild = ColorFiltered(colorFilter: adjustments, child: visualChild);
    }

    if (viewModel.canvasBlurSigma > 0.0) {
      visualChild = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: viewModel.canvasBlurSigma,
          sigmaY: viewModel.canvasBlurSigma,
        ),
        child: visualChild,
      );
    }

    final isSelected = activeClip is VideoClip && activeClip.id == viewModel.selectedClipId;

    Widget videoContent;
    if (activeClip is VideoClip) {
      videoContent = InteractiveTransformCanvas(
        key: ValueKey('clip_canvas_${activeClip.id}'),
        clip: activeClip,
        isSelected: isSelected,
        viewModel: viewModel,
        overrideTransform: keyframeTransform,
        child: visualChild,
      );
    } else {
      videoContent = Transform(
        alignment: Alignment.center,
        transform: ClipSpatialTransform.fromClip(activeClip).toMatrix4(
          legacyRotationDegrees: activeClip.rotationDegrees,
          flipHorizontal: activeClip.flipHorizontal,
          flipVertical: activeClip.flipVertical,
        ),
        child: visualChild,
      );
    }

    if (activeClip is VideoClip && activeClip.mask != null) {
      videoContent = ClipPath(
        clipper: MaskPathClipper(activeClip.mask!),
        child: videoContent,
      );
    }

    if (activeClip is VideoClip && activeClip.blendMode != BlendMode.srcOver) {
      videoContent = CanvasBlendLayer(
        blendMode: activeClip.blendMode,
        child: videoContent,
      );
    }

    return videoContent;
  }

  Widget _buildMissingMediaGraphic(dynamic activeClip) {
    final title = activeClip is VideoClip ? activeClip.title : 'Clip';
    return Container(
      color: const Color(0xFF161212),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
              ),
              child: const Icon(
                Icons.broken_image_rounded,
                size: 36,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Media Offline',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'File not found: $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderGraphic(dynamic activeClip) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: activeClip.previewGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeClip.previewIcon,
              size: 48,
              color: Colors.white.withOpacity(0.85),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeClip.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (activeClip.isReversed)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Icon(Icons.fast_rewind_rounded, size: 12, color: AppColors.secondary),
                        ),
                      if (activeClip.isFrozen)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Icon(Icons.ac_unit_rounded, size: 12, color: AppColors.primary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaybackSurface(dynamic activeClip, String? localPath) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F141C),
        gradient: LinearGradient(
          colors: [
            Color(0xFF141E30),
            Color(0xFF243B55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.15),
                border: Border.all(color: AppColors.primary.withOpacity(0.6), width: 1.5),
              ),
              child: Icon(
                viewModel.isPlaying ? Icons.play_circle_filled_rounded : Icons.videocam_rounded,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              activeClip.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                viewModel.isPlaying
                    ? 'PLAYING • ${TimeFormatter.formatSeconds(viewModel.playheadPosition)}'
                    : 'PAUSED • ${TimeFormatter.formatSeconds(activeClip.durationInSeconds)}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: viewModel.isPlaying ? AppColors.primary : AppColors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayLayer(dynamic overlay) {
    double effScale = (overlay.scale as num).toDouble();
    Offset effPos = overlay.position is Offset ? overlay.position as Offset : const Offset(0.7, 0.25);
    double effOpacity = overlay.opacity != null ? (overlay.opacity as num).toDouble() : 1.0;
    double effRotation = overlay.rotation != null ? (overlay.rotation as num).toDouble() : 0.0;

    if (overlay is OverlayClip && overlay.keyframes.isNotEmpty) {
      final overlayTime = (viewModel.currentTimeInSeconds - overlay.startTimeInSeconds).clamp(0.0, overlay.durationInSeconds);
      final kf = viewModel.getInterpolatedOverlayKeyframe(overlay, overlayTime);
      if (kf != null) {
        effScale = kf.scale;
        effOpacity = kf.opacity;
        effRotation = kf.rotationDegrees * math.pi / 180.0;
        effPos = Offset(
          (overlay.position.dx + kf.positionX / 300.0).clamp(0.0, 1.0),
          (overlay.position.dy + kf.positionY / 300.0).clamp(0.0, 1.0),
        );
      }
    }

    Widget visualBody;
    if (overlay is OverlayClip && overlay.localPath != null && File(overlay.localPath!).existsSync()) {
      visualBody = Image.file(
        File(overlay.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholderOverlayGradient(overlay),
      );
    } else {
      visualBody = _buildPlaceholderOverlayGradient(overlay);
    }

    Widget overlayCard = Container(
      width: 140,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.secondary, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm - 1.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            visualBody,
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('PIP', style: TextStyle(fontSize: 8, color: AppColors.secondary, fontWeight: FontWeight.bold)),
                    if (overlay is OverlayClip && overlay.enableChromaKey) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.auto_fix_high_rounded, size: 8, color: Color(0xFF00FF00)),
                    ],
                    if (overlay is OverlayClip && overlay.blendMode != BlendMode.srcOver) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.layers_rounded, size: 8, color: Colors.cyanAccent),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Apply Chroma Key (Green / Blue Screen Removal)
    if (overlay is OverlayClip && overlay.enableChromaKey) {
      overlayCard = ColorFiltered(
        colorFilter: ChromaKeyHelper.createColorFilter(
          keyColor: overlay.chromaKeyColor,
          similarity: overlay.chromaSimilarity,
          smoothness: overlay.chromaSmoothness,
          spill: overlay.chromaSpill,
        ),
        child: overlayCard,
      );
    }

    // Apply Spatial Positioning, Scaling & Opacity
    Widget overlayContent = Align(
      alignment: FractionalOffset(effPos.dx, effPos.dy),
      child: Transform.rotate(
        angle: effRotation,
        child: Transform.scale(
          scale: effScale,
          child: Opacity(
            opacity: effOpacity.clamp(0.0, 1.0),
            child: overlayCard,
          ),
        ),
      ),
    );

    if (overlay is OverlayClip) {
      if (overlay.mask != null) {
        overlayContent = ClipPath(
          clipper: MaskPathClipper(overlay.mask!),
          child: overlayContent,
        );
      }
      if (overlay.blendMode != BlendMode.srcOver) {
        overlayContent = CanvasBlendLayer(
          blendMode: overlay.blendMode,
          child: overlayContent,
        );
      }
    }

    return overlayContent;
  }

  Widget _buildPlaceholderOverlayGradient(dynamic overlay) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: overlay.previewGradient is List<Color>
              ? overlay.previewGradient as List<Color>
              : const [Color(0xFF8A2387), Color(0xFFE94057)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          overlay.previewIcon is IconData ? overlay.previewIcon as IconData : Icons.layers_rounded,
          color: Colors.white70,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildStickerOverlay(dynamic sticker) {
    return Align(
      alignment: FractionalOffset(sticker.position.dx, sticker.position.dy),
      child: Transform.scale(
        scale: sticker.scale,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: sticker.preset.isEmoji
              ? Text(
                  sticker.preset.content,
                  style: const TextStyle(fontSize: 36),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (sticker.preset.color ?? AppColors.primary).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sticker.preset.icon != null)
                        Icon(sticker.preset.icon, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        sticker.preset.content,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildEffectOverlay(VideoEffect effect) {
    switch (effect.type) {
      case VideoEffectType.glitch:
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.primary.withOpacity(0.12),
                  AppColors.secondary.withOpacity(0.12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 0.55, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        );
      case VideoEffectType.vhs:
        return IgnorePointer(
          child: Container(
            color: Colors.transparent,
            child: CustomPaint(
              painter: _VhsScanlinePainter(),
            ),
          ),
        );
      case VideoEffectType.rgbSplit:
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 3),
            ),
          ),
        );
      case VideoEffectType.sparkle:
        return const IgnorePointer(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 28),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextOverlay(
    TextOverlay text, {
    double canvasWidth = 360.0,
    double canvasHeight = 640.0,
  }) {
    final isSelected = viewModel.selectedTextId == text.id;
    final elapsedSec = viewModel.currentTimeInSeconds - text.startTimeInSeconds;

    return InteractiveTextOverlayWidget(
      key: ValueKey('text_ov_${text.id}'),
      text: text,
      isSelected: isSelected,
      viewModel: viewModel,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      canvasKey: _canvasKey,
      captionChild: _buildCaptionContent(text, elapsedSec),
    );
  }

  Widget _buildCaptionContent(TextOverlay text, double elapsedSec) {
    if (text.animationType == TextAnimationType.karaoke) {
      final words = text.effectiveWords;
      if (words.isNotEmpty) {
        final activeIdx = text.getActiveWordIndex(elapsedSec);
        final wrapAlignment = text.textAlign == TextAlign.left
            ? WrapAlignment.start
            : (text.textAlign == TextAlign.right ? WrapAlignment.end : WrapAlignment.center);

        return SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: wrapAlignment,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6.0,
            runSpacing: 4.0,
            children: List.generate(words.length, (i) {
              final w = words[i];
              final isActive = i == activeIdx;
              final isSpoken = i < activeIdx;
              final activeColor = text.highlightColor ?? const Color(0xFFFFEB3B);
              final wordColor = isActive
                  ? activeColor
                  : (isSpoken ? text.color : text.color.withOpacity(0.88));

              final wordText = _buildStrokedWord(
                word: w.word,
                textColor: wordColor,
                strokeWidth: text.strokeWidth,
                strokeColor: text.strokeColor ?? Colors.black,
                fontSize: text.fontSize,
                fontFamily: text.fontFamily,
                isBold: text.isBold,
                isItalic: text.isItalic,
                isUnderline: text.isUnderline,
                textAlign: text.textAlign,
                isActive: isActive,
                activeGlowColor: activeColor,
              );

              if (isActive) {
                return Transform.scale(
                  scale: 1.12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: wordText,
                  ),
                );
              }

              return wordText;
            }),
          ),
        );
      }
    }

    if (text.animationType == TextAnimationType.typewriter) {
      final totalLen = text.text.length;
      final progress = (elapsedSec / text.durationInSeconds).clamp(0.0, 1.0);
      final visibleChars = (progress * totalLen).ceil().clamp(0, totalLen);
      final displayText = text.text.substring(0, visibleChars);
      return _buildStrokedWord(
        word: displayText,
        textColor: text.color,
        strokeWidth: text.strokeWidth,
        strokeColor: text.strokeColor ?? Colors.black,
        fontSize: text.fontSize,
        fontFamily: text.fontFamily,
        isBold: text.isBold,
        isItalic: text.isItalic,
        isUnderline: text.isUnderline,
        textAlign: text.textAlign,
        isActive: false,
      );
    }

    // Default static or styled text
    return _buildStrokedWord(
      word: text.text,
      textColor: text.color,
      strokeWidth: text.strokeWidth,
      strokeColor: text.strokeColor ?? Colors.black,
      fontSize: text.fontSize,
      fontFamily: text.fontFamily,
      isBold: text.isBold,
      isItalic: text.isItalic,
      isUnderline: text.isUnderline,
      textAlign: text.textAlign,
      isActive: false,
    );
  }

  Widget _buildStrokedWord({
    required String word,
    required Color textColor,
    required double strokeWidth,
    required Color strokeColor,
    required double fontSize,
    String? fontFamily,
    required bool isBold,
    required bool isItalic,
    bool isUnderline = false,
    TextAlign textAlign = TextAlign.center,
    required bool isActive,
    Color? activeGlowColor,
  }) {
    final style = FontHelper.getTextStyle(
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
      letterSpacing: 0.5,
    );

    final alignment = textAlign == TextAlign.left
        ? Alignment.centerLeft
        : (textAlign == TextAlign.right ? Alignment.centerRight : Alignment.center);

    if (strokeWidth > 0.0) {
      return SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: alignment,
          children: [
            // Background stroke outline
            SizedBox(
              width: double.infinity,
              child: Text(
                word,
                textAlign: textAlign,
                softWrap: true,
                style: style.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = strokeWidth * 2
                    ..color = strokeColor,
                  decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: strokeColor,
                ),
              ),
            ),
            // Foreground fill text
            SizedBox(
              width: double.infinity,
              child: Text(
                word,
                textAlign: textAlign,
                softWrap: true,
                style: style.copyWith(
                  color: textColor,
                  decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: textColor,
                  shadows: isActive && activeGlowColor != null
                      ? [
                          Shadow(
                            color: activeGlowColor.withOpacity(0.85),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Text(
        word,
        textAlign: textAlign,
        softWrap: true,
        style: style.copyWith(
          color: textColor,
          decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
          decorationColor: textColor,
          shadows: [
            if (isActive && activeGlowColor != null)
              Shadow(
                color: activeGlowColor.withOpacity(0.85),
                blurRadius: 10,
              )
            else
              const Shadow(
                blurRadius: 4,
                color: Colors.black87,
                offset: Offset(1, 1),
              ),
          ],
        ),
      ),
    );
  }
}

class _VhsScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CircleTransitionClipper extends CustomClipper<Rect> {
  final double progress;
  _CircleTransitionClipper(this.progress);

  @override
  Rect getClip(Size size) {
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2.0;
    final radius = maxRadius * progress;
    final center = Offset(size.width / 2.0, size.height / 2.0);
    return Rect.fromCircle(center: center, radius: radius);
  }

  @override
  bool shouldReclip(_CircleTransitionClipper oldClipper) => oldClipper.progress != progress;
}

class _RadialTransitionClipper extends CustomClipper<Path> {
  final double progress;
  _RadialTransitionClipper(this.progress);

  @override
  Path getClip(Size size) {
    final path = Path();
    if (progress <= 0.0) return path;
    if (progress >= 1.0) {
      path.addRect(Offset.zero & size);
      return path;
    }
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    path.moveTo(center.dx, center.dy);
    path.lineTo(center.dx, center.dy - maxRadius);
    final sweepAngle = progress * 2.0 * math.pi;
    path.arcTo(
      Rect.fromCircle(center: center, radius: maxRadius),
      -math.pi / 2.0,
      sweepAngle,
      false,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_RadialTransitionClipper oldClipper) => oldClipper.progress != progress;
}

class CanvasBlendLayer extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const CanvasBlendLayer({super.key, required this.blendMode, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCanvasBlendLayer(blendMode);

  @override
  void updateRenderObject(BuildContext context, covariant RenderCanvasBlendLayer renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class RenderCanvasBlendLayer extends RenderProxyBox {
  BlendMode _blendMode;
  RenderCanvasBlendLayer(this._blendMode);

  set blendMode(BlendMode value) {
    if (_blendMode != value) {
      _blendMode = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_blendMode == BlendMode.srcOver) {
      context.paintChild(child!, offset);
    } else {
      final bounds = offset & size;
      final paint = Paint()..blendMode = _blendMode;
      context.canvas.saveLayer(bounds, paint);
      context.paintChild(child!, offset);
      context.canvas.restore();
    }
  }
}

/// CapCut-like Interactive Text Overlay Widget with Fluent Touch Direct Manipulation.
///
/// Provides:
/// - Immediate 1:1 translation with center snapping (zero slop delay)
/// - Direct two-finger pinch-to-zoom scaling on the text body with focal point tracking
/// - Seamless pointer count transitions (1 -> 2 and 2 -> 1 without jumps)
/// - Explicit corner resize handle for secondary control
/// - Isolated local rebuild path (zero global app or timeline rebuilds during gestures)
/// - Single undo snapshot commit on gesture completion
class InteractiveTextOverlayWidget extends StatefulWidget {
  final TextOverlay text;
  final bool isSelected;
  final EditorViewModel viewModel;
  final double canvasWidth;
  final double canvasHeight;
  final GlobalKey canvasKey;
  final Widget captionChild;

  const InteractiveTextOverlayWidget({
    super.key,
    required this.text,
    required this.isSelected,
    required this.viewModel,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.canvasKey,
    required this.captionChild,
  });

  @override
  State<InteractiveTextOverlayWidget> createState() => _InteractiveTextOverlayWidgetState();
}

class _InteractiveTextOverlayWidgetState extends State<InteractiveTextOverlayWidget> {
  late Offset _livePosition;
  late double _liveScale;
  late double _liveBoxWidth;
  bool _isGestureActive = false;

  final Map<int, Offset> _activePointers = {}; // pointerId -> global screen position
  InteractionMode _mode = InteractionMode.none;

  // 1-Finger translation baseline
  Offset _dragStartPointerNorm = Offset.zero;
  Offset _dragStartTextPos = Offset.zero;

  // Gesture snapshot baseline for single undo commit
  Offset _gestureStartTextPos = Offset.zero;
  double _gestureStartTextScale = 1.0;

  // 2-Finger pinch zoom baseline
  double _initialPinchDistance = 1.0;
  double _initialPinchScale = 1.0;
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialPinchTextPos = Offset.zero;

  // Corner resize handle baseline
  Offset _startCornerDragPos = Offset.zero;
  double _startCornerDragScale = 1.0;
  Offset _startCornerTextPos = Offset.zero;

  // Horizontal box width drag baseline
  double _startWidthDragPos = 0.0;
  double _startWidthDragWidth = 260.0;

  @override
  void initState() {
    super.initState();
    _livePosition = widget.text.position;
    _liveScale = widget.text.scale;
    _liveBoxWidth = widget.text.getEffectiveBoxWidth(widget.canvasWidth);
  }

  @override
  void didUpdateWidget(covariant InteractiveTextOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isGestureActive) {
      if (widget.text.position != _livePosition || widget.text.scale != _liveScale) {
        _livePosition = widget.text.position;
        _liveScale = widget.text.scale;
      }
      final targetBoxW = widget.text.getEffectiveBoxWidth(widget.canvasWidth);
      if (targetBoxW != _liveBoxWidth) {
        _liveBoxWidth = targetBoxW;
      }
    }
  }

  Offset _getCanvasLocal(Offset globalPos) {
    final renderBox = widget.canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.globalToLocal(globalPos);
    }
    return globalPos;
  }

  Offset _getNormalizedCanvasPos(Offset globalPos) {
    final local = _getCanvasLocal(globalPos);
    final w = widget.canvasWidth > 0 ? widget.canvasWidth : 360.0;
    final h = widget.canvasHeight > 0 ? widget.canvasHeight : 640.0;
    return Offset(local.dx / w, local.dy / h);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.viewModel.isCropModeActive && widget.viewModel.selectedTextId == null) {
      return;
    }

    if (!widget.isSelected) {
      widget.viewModel.selectText(widget.text.id);
    }

    _activePointers[event.pointer] = event.position;

    if (!_isGestureActive) {
      _isGestureActive = true;
      _gestureStartTextPos = _livePosition;
      _gestureStartTextScale = _liveScale;
    }

    final canvasNorm = _getNormalizedCanvasPos(event.position);

    if (_activePointers.length == 1) {
      _mode = InteractionMode.textMove;
      _dragStartPointerNorm = canvasNorm;
      _dragStartTextPos = _livePosition;
    } else if (_activePointers.length >= 2) {
      _mode = InteractionMode.textPinch;
      final entries = _activePointers.values.toList();
      final p1 = _getCanvasLocal(entries[0]);
      final p2 = _getCanvasLocal(entries[1]);
      final dist = (p1 - p2).distance;

      _initialPinchDistance = dist > 5.0 ? dist : 5.0;
      _initialPinchScale = _liveScale;
      _initialFocalPoint = (p1 + p2) / 2.0;
      _initialPinchTextPos = _livePosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;

    final w = widget.canvasWidth > 0 ? widget.canvasWidth : 360.0;
    final h = widget.canvasHeight > 0 ? widget.canvasHeight : 640.0;

    if (_mode == InteractionMode.textMove && _activePointers.length == 1) {
      final currentNorm = _getNormalizedCanvasPos(event.position);
      final delta = currentNorm - _dragStartPointerNorm;
      var targetX = _dragStartTextPos.dx + delta.dx;
      var targetY = _dragStartTextPos.dy + delta.dy;

      // Gentle center snap with 1.8% threshold
      if ((targetX - 0.5).abs() < 0.018) targetX = 0.5;
      if ((targetY - 0.5).abs() < 0.018) targetY = 0.5;

      targetX = targetX.clamp(0.0, 1.0);
      targetY = targetY.clamp(0.0, 1.0);

      setState(() {
        _livePosition = TextOverlay.sanitizePosition(
          Offset(targetX, targetY),
          fallback: _livePosition,
        );
      });
    } else if (_mode == InteractionMode.textPinch && _activePointers.length >= 2) {
      final entries = _activePointers.values.toList();
      final p1 = _getCanvasLocal(entries[0]);
      final p2 = _getCanvasLocal(entries[1]);
      final currentDist = (p1 - p2).distance;

      if (_initialPinchDistance > 1.0 && !currentDist.isNaN && !currentDist.isInfinite && currentDist > 0.0) {
        final scaleFactor = currentDist / _initialPinchDistance;
        final rawScale = _initialPinchScale * scaleFactor;
        final newScale = TextOverlay.sanitizeScale(rawScale, fallback: _liveScale);

        final currentFocal = (p1 + p2) / 2.0;
        final focalDelta = currentFocal - _initialFocalPoint;
        final normFocalDelta = Offset(focalDelta.dx / w, focalDelta.dy / h);
        final newPos = TextOverlay.sanitizePosition(
          _initialPinchTextPos + normFocalDelta,
          fallback: _livePosition,
        );

        setState(() {
          _liveScale = newScale;
          _livePosition = newPos;
        });
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_activePointers.length == 1) {
      _mode = InteractionMode.textMove;
      final remainingGlobal = _activePointers.values.first;
      _dragStartPointerNorm = _getNormalizedCanvasPos(remainingGlobal);
      _dragStartTextPos = _livePosition;
    } else if (_activePointers.isEmpty) {
      _finalizeGesture();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _finalizeGesture();
    }
  }

  void _finalizeGesture() {
    _mode = InteractionMode.none;
    _isGestureActive = false;

    widget.viewModel.updateTextTransform(
      widget.text.id,
      position: _livePosition,
      scale: _liveScale,
    );
    widget.viewModel.commitTextTransform(
      widget.text.id,
      oldPosition: _gestureStartTextPos,
      oldScale: _gestureStartTextScale,
    );
  }

  void _handleCornerPanStart(DragStartDetails details) {
    _mode = InteractionMode.textResize;
    _isGestureActive = true;
    _startCornerDragPos = details.globalPosition;
    _startCornerDragScale = _liveScale;
    _startCornerTextPos = _livePosition;
    _gestureStartTextPos = _livePosition;
    _gestureStartTextScale = _liveScale;
  }

  void _handleCornerPanUpdate(DragUpdateDetails details) {
    final dragDistance = (details.globalPosition.dx - _startCornerDragPos.dx) +
        (details.globalPosition.dy - _startCornerDragPos.dy);
    final scaleMultiplier = 1.0 + (dragDistance / 180.0);
    final rawScale = _startCornerDragScale * scaleMultiplier;
    final newScale = TextOverlay.sanitizeScale(rawScale, fallback: _liveScale);
    setState(() {
      _liveScale = newScale;
    });
  }

  void _handleCornerPanEnd(DragEndDetails details) {
    _mode = InteractionMode.none;
    _isGestureActive = false;
    widget.viewModel.updateTextTransform(
      widget.text.id,
      position: _livePosition,
      scale: _liveScale,
    );
    widget.viewModel.commitTextTransform(
      widget.text.id,
      oldPosition: _startCornerTextPos,
      oldScale: _startCornerDragScale,
    );
  }

  void _handleRightWidthPanStart(DragStartDetails details) {
    _mode = InteractionMode.textResize;
    _isGestureActive = true;
    _startWidthDragPos = details.globalPosition.dx;
    _startWidthDragWidth = _liveBoxWidth;
  }

  void _handleRightWidthPanUpdate(DragUpdateDetails details) {
    final scale = _liveScale > 0 ? _liveScale : 1.0;
    final deltaX = (details.globalPosition.dx - _startWidthDragPos) / scale;
    final newWidth = (_startWidthDragWidth + deltaX * 2).clamp(80.0, 1000.0);
    setState(() {
      _liveBoxWidth = newWidth;
    });
  }

  void _handleLeftWidthPanStart(DragStartDetails details) {
    _mode = InteractionMode.textResize;
    _isGestureActive = true;
    _startWidthDragPos = details.globalPosition.dx;
    _startWidthDragWidth = _liveBoxWidth;
  }

  void _handleLeftWidthPanUpdate(DragUpdateDetails details) {
    final scale = _liveScale > 0 ? _liveScale : 1.0;
    final deltaX = (_startWidthDragPos - details.globalPosition.dx) / scale;
    final newWidth = (_startWidthDragWidth + deltaX * 2).clamp(80.0, 1000.0);
    setState(() {
      _liveBoxWidth = newWidth;
    });
  }

  void _handleWidthPanEnd(DragEndDetails details) {
    _mode = InteractionMode.none;
    _isGestureActive = false;
    widget.viewModel.updateTextOverlay(
      widget.text.copyWith(boxWidth: _liveBoxWidth),
      saveSnapshot: true,
      notify: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final isSelected = widget.isSelected;
    final elapsedSec = widget.viewModel.currentTimeInSeconds - text.startTimeInSeconds;
    final durationSec = text.durationInSeconds;
    final remainingSec = (durationSec - elapsedSec).clamp(0.0, double.infinity);

    double animScale = 1.0;
    double slideY = 0.0;
    double opacity = 1.0;

    if (text.animationType == TextAnimationType.fade) {
      if (elapsedSec < 0.35) {
        opacity = (elapsedSec / 0.35).clamp(0.0, 1.0);
      } else if (remainingSec < 0.35) {
        opacity = (remainingSec / 0.35).clamp(0.0, 1.0);
      }
    } else if (text.animationType == TextAnimationType.zoom) {
      if (elapsedSec < 0.35) {
        final t = (elapsedSec / 0.35).clamp(0.0, 1.0);
        animScale = 0.2 + 0.8 * t;
        opacity = t;
      } else if (remainingSec < 0.35) {
        final t = (remainingSec / 0.35).clamp(0.0, 1.0);
        animScale = 0.2 + 0.8 * t;
        opacity = t;
      }
    } else if (text.animationType == TextAnimationType.pop) {
      final t = (elapsedSec / 0.22).clamp(0.0, 1.0);
      animScale = t < 1.0 ? (0.75 + 0.35 * math.sin(t * math.pi)) : 1.0;
      if (remainingSec < 0.22) {
        final rt = (remainingSec / 0.22).clamp(0.0, 1.0);
        animScale *= rt;
        opacity = rt;
      }
    } else if (text.animationType == TextAnimationType.slideUp) {
      if (elapsedSec < 0.35) {
        final t = (elapsedSec / 0.35).clamp(0.0, 1.0);
        slideY = (1.0 - t) * 35.0;
        opacity = t;
      } else if (remainingSec < 0.35) {
        final t = (remainingSec / 0.35).clamp(0.0, 1.0);
        slideY = -(1.0 - t) * 35.0;
        opacity = t;
      }
    } else if (text.animationType == TextAnimationType.slideDown) {
      if (elapsedSec < 0.35) {
        final t = (elapsedSec / 0.35).clamp(0.0, 1.0);
        slideY = -(1.0 - t) * 35.0;
        opacity = t;
      } else if (remainingSec < 0.35) {
        final t = (remainingSec / 0.35).clamp(0.0, 1.0);
        slideY = (1.0 - t) * 35.0;
        opacity = t;
      }
    } else if (text.animationType == TextAnimationType.fadeSlide) {
      if (elapsedSec < 0.28) {
        final t = (elapsedSec / 0.28).clamp(0.0, 1.0);
        slideY = (1.0 - t) * 16.0;
        opacity = t;
      } else if (remainingSec < 0.28) {
        final t = (remainingSec / 0.28).clamp(0.0, 1.0);
        slideY = -(1.0 - t) * 16.0;
        opacity = t;
      }
    } else if (text.animationType == TextAnimationType.glowPulse) {
      animScale = 1.0 + 0.04 * math.sin(elapsedSec * 6.0);
    }

    final effScale = _liveScale * animScale;

    final posX = _livePosition.dx.clamp(0.0, 1.0) * widget.canvasWidth;
    final posY = _livePosition.dy.clamp(0.0, 1.0) * widget.canvasHeight;

    return Positioned(
      left: posX,
      top: posY,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.translate(
        offset: Offset(0, slideY),
        child: Transform.scale(
          scale: effScale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 1. Text Content with 1-finger Move and direct 2-finger Pinch
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerCancel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!isSelected) {
                          widget.viewModel.selectText(text.id);
                        }
                      },
                      onDoubleTap: () =>
                          TextDrawer.showAddOrEditModal(context, widget.viewModel, existing: text),
                      child: Container(
                        width: _liveBoxWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: text.backgroundColor ??
                              (text.strokeWidth > 0 ? Colors.transparent : Colors.black.withOpacity(0.65)),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : Colors.transparent,
                            width: isSelected ? 2.0 : 0.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: RepaintBoundary(
                          child: widget.captionChild,
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Interactive Bounding Box Handles (when selected)
                if (isSelected) ...[
                  // Top-Left: Edit text & font button
                  Positioned(
                    top: 0,
                    left: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => TextDrawer.showAddOrEditModal(context, widget.viewModel, existing: text),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        color: Colors.transparent,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.edit_rounded, size: 14, color: Colors.black),
                        ),
                      ),
                    ),
                  ),

                  // Top-Right: Delete button
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.viewModel.removeTextOverlay(text.id),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        color: Colors.transparent,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  // Bottom-Right: Corner drag-to-resize handle (Retained for explicit resize control)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _handleCornerPanStart,
                      onPanUpdate: _handleCornerPanUpdate,
                      onPanEnd: _handleCornerPanEnd,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        color: Colors.transparent,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.open_in_full_rounded, size: 14, color: Colors.black),
                        ),
                      ),
                    ),
                  ),

                  // Middle-Right: Width resize handle (drags text box width horizontally)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _handleRightWidthPanStart,
                        onPanUpdate: _handleRightWidthPanUpdate,
                        onPanEnd: _handleWidthPanEnd,
                        child: Container(
                          width: 36,
                          height: 40,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Container(
                            width: 6,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Middle-Left: Width resize handle (drags text box width horizontally)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _handleLeftWidthPanStart,
                        onPanUpdate: _handleLeftWidthPanUpdate,
                        onPanEnd: _handleWidthPanEnd,
                        child: Container(
                          width: 36,
                          height: 40,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Container(
                            width: 6,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom-Left: Font family indicator badge
                  if (text.fontFamily != null)
                    Positioned(
                      bottom: 4,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.7),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          text.fontFamily!,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

/// Interactive Crop Area Touch Handles Overlay for direct manipulation of video masks.
class _CropAreaHandlesOverlay extends StatefulWidget {
  final EditorViewModel viewModel;
  final double canvasWidth;
  final double canvasHeight;
  final GlobalKey canvasKey;

  const _CropAreaHandlesOverlay({
    required this.viewModel,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.canvasKey,
  });

  @override
  State<_CropAreaHandlesOverlay> createState() => _CropAreaHandlesOverlayState();
}

class _CropAreaHandlesOverlayState extends State<_CropAreaHandlesOverlay> {
  late Rect _liveRect;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _liveRect = widget.viewModel.activeCropRect;
  }

  @override
  void didUpdateWidget(covariant _CropAreaHandlesOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _liveRect = widget.viewModel.activeCropRect;
    }
  }

  void _onHandlePanStart() {
    _isDragging = true;
  }

  void _onHandlePanEnd() {
    _isDragging = false;
    widget.viewModel.updateCropRect(_liveRect);
  }

  void _updateDelta({
    double? dLeft,
    double? dTop,
    double? dRight,
    double? dBottom,
  }) {
    const minSize = 0.1;
    final w = widget.canvasWidth > 0 ? widget.canvasWidth : 360.0;
    final h = widget.canvasHeight > 0 ? widget.canvasHeight : 640.0;

    var newL = _liveRect.left + (dLeft != null ? dLeft / w : 0.0);
    var newT = _liveRect.top + (dTop != null ? dTop / h : 0.0);
    var newR = _liveRect.right + (dRight != null ? dRight / w : 0.0);
    var newB = _liveRect.bottom + (dBottom != null ? dBottom / h : 0.0);

    if (dLeft != null) newL = newL.clamp(0.0, newR - minSize);
    if (dRight != null) newR = newR.clamp(newL + minSize, 1.0);
    if (dTop != null) newT = newT.clamp(0.0, newB - minSize);
    if (dBottom != null) newB = newB.clamp(newT + minSize, 1.0);

    final clamped = Rect.fromLTRB(newL, newT, newR, newB);
    if (clamped.left.isFinite && clamped.top.isFinite && clamped.right.isFinite && clamped.bottom.isFinite) {
      setState(() {
        _liveRect = clamped;
      });
      widget.viewModel.updateCropRect(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.canvasWidth > 0 ? widget.canvasWidth : 360.0;
    final h = widget.canvasHeight > 0 ? widget.canvasHeight : 640.0;

    final leftPx = _liveRect.left * w;
    final topPx = _liveRect.top * h;
    final widthPx = _liveRect.width * w;
    final heightPx = _liveRect.height * h;
    final rightPx = leftPx + widthPx;
    final bottomPx = topPx + heightPx;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Bounding box border
        Positioned(
          left: leftPx,
          top: topPx,
          width: widthPx,
          height: heightPx,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2.0),
              ),
            ),
          ),
        ),

        // Left Edge Handle
        Positioned(
          left: leftPx - 18,
          top: topPx + (heightPx / 2) - 20,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dLeft: d.delta.dx),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 40,
              alignment: Alignment.center,
              child: Container(
                width: 6,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Right Edge Handle
        Positioned(
          left: rightPx - 18,
          top: topPx + (heightPx / 2) - 20,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dRight: d.delta.dx),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 40,
              alignment: Alignment.center,
              child: Container(
                width: 6,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Top Edge Handle
        Positioned(
          left: leftPx + (widthPx / 2) - 20,
          top: topPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dTop: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 40,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Bottom Edge Handle
        Positioned(
          left: leftPx + (widthPx / 2) - 20,
          top: bottomPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dBottom: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 40,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Top-Left Corner Handle
        Positioned(
          left: leftPx - 18,
          top: topPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dLeft: d.delta.dx, dTop: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Top-Right Corner Handle
        Positioned(
          left: rightPx - 18,
          top: topPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dRight: d.delta.dx, dTop: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Bottom-Left Corner Handle
        Positioned(
          left: leftPx - 18,
          top: bottomPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dLeft: d.delta.dx, dBottom: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),

        // Bottom-Right Corner Handle
        Positioned(
          left: rightPx - 18,
          top: bottomPx - 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _onHandlePanStart(),
            onPanUpdate: (d) => _updateDelta(dRight: d.delta.dx, dBottom: d.delta.dy),
            onPanEnd: (_) => _onHandlePanEnd(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MaskPathClipper extends CustomClipper<Path> {
  final VideoMask mask;

  MaskPathClipper(this.mask);

  @override
  Path getClip(Size size) {
    final Path path = Path();
    final center = Offset(
      size.width / 2 + (mask.positionX * size.width / 2),
      size.height / 2 + (mask.positionY * size.height / 2),
    );
    final w = size.width * (mask.rectWidth ?? mask.size);
    final h = size.height * (mask.rectHeight ?? mask.size);

    switch (mask.type) {
      case MaskType.none:
        path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
        break;

      case MaskType.split:
        path.addRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.5 * mask.size + size.height * 0.25));
        break;

      case MaskType.filmstrip:
        final barHeight = (size.height * (1.0 - mask.size.clamp(0.2, 0.9))) / 2;
        path.addRect(Rect.fromLTWH(0, barHeight, size.width, size.height - barHeight * 2));
        break;

      case MaskType.rectangle:
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: w, height: h),
            Radius.circular(mask.feather > 0 ? mask.feather * 2 : 8),
          ),
        );
        break;

      case MaskType.circle:
        path.addOval(Rect.fromCenter(center: center, width: w, height: h));
        break;

      case MaskType.heart:
        final scale = mask.size;
        final hw = size.width / 2;
        final hh = size.height / 2;
        path.moveTo(hw, hh + 40 * scale);
        path.cubicTo(hw - 60 * scale, hh, hw - 60 * scale, hh - 40 * scale, hw, hh - 15 * scale);
        path.cubicTo(hw + 60 * scale, hh - 40 * scale, hw + 60 * scale, hh, hw, hh + 40 * scale);
        path.close();
        break;

      case MaskType.star:
        final outerR = (w / 2);
        final innerR = outerR * 0.45;
        for (int i = 0; i < 5; i++) {
          final outerAngle = -math.pi / 2 + (i * 2 * math.pi / 5);
          final innerAngle = outerAngle + math.pi / 5;
          final ox = center.dx + outerR * math.cos(outerAngle);
          final oy = center.dy + outerR * math.sin(outerAngle);
          final ix = center.dx + innerR * math.cos(innerAngle);
          final iy = center.dy + innerR * math.sin(innerAngle);
          if (i == 0) {
            path.moveTo(ox, oy);
          } else {
            path.lineTo(ox, oy);
          }
          path.lineTo(ix, iy);
        }
        path.close();
        break;
    }

    if (mask.inverted) {
      final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      return Path.combine(PathOperation.difference, full, path);
    }

    return path;
  }

  @override
  bool shouldReclip(covariant MaskPathClipper oldClipper) =>
      oldClipper.mask.type != mask.type ||
      oldClipper.mask.size != mask.size ||
      oldClipper.mask.feather != mask.feather ||
      oldClipper.mask.positionX != mask.positionX ||
      oldClipper.mask.positionY != mask.positionY ||
      oldClipper.mask.rotation != mask.rotation ||
      oldClipper.mask.inverted != mask.inverted ||
      oldClipper.mask.rectWidth != mask.rectWidth ||
      oldClipper.mask.rectHeight != mask.rectHeight;
}
