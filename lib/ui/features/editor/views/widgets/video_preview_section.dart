import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Top Video Preview Screen containing the live video canvas, aspect-ratio viewport,
/// color grading LUT filters, adjustments, Picture-in-Picture (PIP) layers,
/// active stickers, subtitles, and hardware-accelerated playback surface.
class VideoPreviewSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const VideoPreviewSection({super.key, required this.viewModel});

  @override
  State<VideoPreviewSection> createState() => _VideoPreviewSectionState();
}

class _VideoPreviewSectionState extends State<VideoPreviewSection> {
  EditorViewModel get viewModel => widget.viewModel;

  VideoPlayerSession? _session;
  String? _loadedPath;
  String? _lastActiveClipId;
  bool _isPlaying = false;
  double _lastPlayheadPosition = -1.0;

  @override
  void initState() {
    super.initState();
    _syncPlayerWithModel();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayerWithModel();
  }

  @override
  void dispose() {
    if (_session != null) {
      VideoPlaybackService.instance.disposeSession(_session!.textureId);
      _session = null;
    }
    super.dispose();
  }

  void _syncPlayerWithModel() {
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
        ? (activeClip.trimStart.inMilliseconds / 1000.0) + (deltaInClipSec * activeClip.speed)
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
              VideoPlaybackService.instance.setVolume(session.textureId, activeClip.volume);
              if (activeClip.speed != 1.0) {
                VideoPlaybackService.instance.setSpeed(session.textureId, activeClip.speed);
              }
              if (widget.viewModel.isPlaying) {
                debugPrint('[AUTO_PLAY_TRACE] VideoPreviewSection calling play because viewModel.isPlaying is TRUE (pos=${sourceOffsetMs}ms)');
                VideoPlaybackService.instance.play(session.textureId, position: Duration(milliseconds: sourceOffsetMs));
                _isPlaying = true;
              } else {
                VideoPlaybackService.instance.seekTo(session.textureId, Duration(milliseconds: sourceOffsetMs));
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
      VideoPlaybackService.instance.setVolume(_session!.textureId, activeClip.volume);
      if (activeClip.speed != 1.0) {
        VideoPlaybackService.instance.setSpeed(_session!.textureId, activeClip.speed);
      }
    }

    // 3. Handle clip boundary switches on the same media file (e.g. split clips)
    if (_session != null && _session!.isInitialized && activeClip != null && activeClip.id != _lastActiveClipId) {
      _lastActiveClipId = activeClip.id;
      if (!widget.viewModel.isPlaying) {
        VideoPlaybackService.instance.seekTo(_session!.textureId, Duration(milliseconds: sourceOffsetMs));
      }
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

  @override
  Widget build(BuildContext context) {
    final activeClip = viewModel.currentActiveClipAtPlayhead;
    final activeTransition = viewModel.activeTransitionAtPlayhead;
    final activeOverlays = viewModel.activeOverlayClipsAtPlayhead;
    final activeStickers = viewModel.activeStickersAtPlayhead;
    final activeTexts = viewModel.activeTextOverlaysAtPlayhead;
    final targetRatio = viewModel.aspectRatio.ratio ?? (9 / 16);

    final filter = viewModel.activeFilter.getColorFilter();
    final adjustments = viewModel.colorAdjustments.getColorFilter();

    return Container(
      width: double.infinity,
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.sm),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 360 / targetRatio,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: viewModel.canvasBackgroundColor,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  border: Border.all(color: AppColors.surfaceHighlight, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
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

                    // 5. Tap to Play / Pause Gesture Overlay
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: viewModel.togglePlayPause,
                      child: AnimatedOpacity(
                        opacity: viewModel.isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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

                    // 6. Active Text / Subtitle Overlays (Positioned on top for drag and interaction)
                    ...activeTexts.map((text) => _buildTextOverlay(text)),

                    // 7. Top-Left: Badges (Aspect Ratio & Active Filter)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
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
                                color: AppColors.secondary.withValues(alpha: 0.8),
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
                                color: AppColors.accentPurple.withValues(alpha: 0.85),
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

                    // 8. Bottom-Center: Live Timecode Pill
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
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

    Widget canvasChild;
    if (hasLocalFile) {
      if (isPhoto) {
        canvasChild = Image.file(
          File(localPath),
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, stack) => _buildPlaceholderGraphic(clip),
        );
      } else {
        final isActiveClip = viewModel.currentActiveClipAtPlayhead?.id == clip.id;
        if (isActiveClip && _session != null && _session!.isInitialized) {
          canvasChild = Center(
            child: AspectRatio(
              aspectRatio: _session!.aspectRatio,
              child: Texture(textureId: _session!.textureId),
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
    } else {
      canvasChild = _buildPlaceholderGraphic(clip);
    }

    return Opacity(
      opacity: clip.opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(clip.rotationDegrees * math.pi / 180)
          ..scaleByDouble(
            clip.flipHorizontal ? -1.0 : 1.0,
            clip.flipVertical ? -1.0 : 1.0,
            1.0,
            1.0,
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
          videoPlayerWidget = Center(
            child: AspectRatio(
              aspectRatio: _session!.aspectRatio,
              child: Texture(textureId: _session!.textureId),
            ),
          );
        } else if (hasThumbnail) {
          videoPlayerWidget = Image.file(
            File(thumbnailPath),
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => _buildVideoPlaybackSurface(activeClip, localPath),
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
                    color: Colors.black.withValues(alpha: 0.7),
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
    } else {
      canvasChild = _buildPlaceholderGraphic(activeClip);
    }

    Widget videoContent = Opacity(
      opacity: activeClip.opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(activeClip.rotationDegrees * math.pi / 180)
          ..scaleByDouble(
            activeClip.flipHorizontal ? -1.0 : 1.0,
            activeClip.flipVertical ? -1.0 : 1.0,
            1.0,
            1.0,
          ),
        child: canvasChild,
      ),
    );

    // Apply color filter LUT & adjustments
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
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
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
                color: AppColors.primary.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
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
                color: Colors.black.withValues(alpha: 0.5),
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
    return Align(
      alignment: FractionalOffset(overlay.position.dx, overlay.position.dy),
      child: Transform.scale(
        scale: overlay.scale,
        child: Container(
          width: 140,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(color: AppColors.secondary, width: 1.5),
            gradient: LinearGradient(
              colors: overlay.previewGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(overlay.previewIcon, color: Colors.white70, size: 28),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('PIP', style: TextStyle(fontSize: 8, color: AppColors.secondary, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
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
                    color: (sticker.preset.color ?? AppColors.primary).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
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
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.secondary.withValues(alpha: 0.12),
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
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 3),
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

  Widget _buildTextOverlay(TextOverlay text) {
    final isSelected = viewModel.selectedTextId == text.id;

    return Align(
      alignment: FractionalOffset(
        text.position.dx.clamp(0.05, 0.95),
        text.position.dy.clamp(0.05, 0.95),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => viewModel.selectText(text.id),
        onPanUpdate: (details) {
          final newX = (text.position.dx + details.delta.dx / 300.0).clamp(0.05, 0.95);
          final newY = (text.position.dy + details.delta.dy / 400.0).clamp(0.05, 0.95);
          viewModel.updateTextPosition(text.id, Offset(newX, newY));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: text.backgroundColor ?? Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.primary : text.color.withValues(alpha: 0.6),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                text.text,
                textAlign: text.textAlign,
                style: TextStyle(
                  fontSize: text.fontSize,
                  fontFamily: text.fontFamily,
                  fontWeight: text.isBold ? FontWeight.w900 : FontWeight.w600,
                  fontStyle: text.isItalic ? FontStyle.italic : FontStyle.normal,
                  decoration: text.isUnderline ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: text.color,
                  color: text.color,
                  shadows: [
                    Shadow(
                      blurRadius: 6,
                      color: text.shadowColor ?? Colors.black,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  top: -14,
                  right: -14,
                  child: GestureDetector(
                    onTap: () => viewModel.removeTextOverlay(text.id),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VhsScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
