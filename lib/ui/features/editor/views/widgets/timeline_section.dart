import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'audio_track_item.dart';
import 'media_picker_sheet.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'timeline_clip_item.dart';
import 'timeline_ruler.dart';
import 'timeline_text_track_item.dart';
import 'transition_selection_sheet.dart';

/// CapCut-style Multi-Layer Interactive Timeline with universal vertical layer scrolling,
/// pinned horizontal ruler, dynamic multi-layer rows, auto-scroll to newly created layers,
/// and complete elimination of RenderFlex pixel overflows.
class TimelineSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const TimelineSection({super.key, required this.viewModel});

  @override
  State<TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<TimelineSection> {
  late final ScrollController _horizontalScrollController;
  late final ScrollController _rulerScrollController;
  late final ScrollController _verticalScrollController;

  bool _isUserScrollingHorizontal = false;

  // Track counts to detect newly added layers for auto-scroll
  int _prevAudioTrackCount = 0;
  int _prevOverlayClipCount = 0;
  int _prevTextOverlayCount = 0;
  int _prevStickerOverlayCount = 0;
  VideoEffectType _prevEffectType = VideoEffectType.none;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _rulerScrollController = ScrollController();
    _verticalScrollController = ScrollController();

    _prevAudioTrackCount = widget.viewModel.audioTracks.length;
    _prevOverlayClipCount = widget.viewModel.overlayClips.length;
    _prevTextOverlayCount = widget.viewModel.textOverlays.length;
    _prevStickerOverlayCount = widget.viewModel.stickerOverlays.length;
    _prevEffectType = widget.viewModel.activeEffect.type;

    _horizontalScrollController.addListener(_syncRulerScroll);
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant TimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
    }
    _onViewModelChanged();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _horizontalScrollController.removeListener(_syncRulerScroll);

    _horizontalScrollController.dispose();
    _rulerScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _syncRulerScroll() {
    if (_rulerScrollController.hasClients && _horizontalScrollController.hasClients) {
      if (_rulerScrollController.position.hasContentDimensions && _horizontalScrollController.position.hasContentDimensions) {
        final targetOffset = _horizontalScrollController.offset.clamp(0.0, _rulerScrollController.position.maxScrollExtent);
        if ((_rulerScrollController.offset - targetOffset).abs() > 0.5) {
          _rulerScrollController.jumpTo(targetOffset);
        }
      }
    }
  }

  double _lastSyncedPlayhead = -1.0;

  void _onViewModelChanged() {
    if (!mounted) return;

    final vm = widget.viewModel;

    // 1. Synchronize horizontal timeline scrolling with playhead position
    if (!_isUserScrollingHorizontal && _horizontalScrollController.hasClients) {
      if (vm.isPlaying || (vm.playheadPosition - _lastSyncedPlayhead).abs() > 0.001) {
        _lastSyncedPlayhead = vm.playheadPosition;
        final targetScroll = vm.playheadPosition * vm.pixelsPerSecond;
        if (_horizontalScrollController.position.hasContentDimensions) {
          _horizontalScrollController.jumpTo(
            targetScroll.clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
          );
        }
      }
    }

    // 2. Auto-scroll vertically when a new layer is created
    _checkAndAutoScrollToNewLayer(vm);

    setState(() {});

    // 3. Post-frame verification to ensure timeline and ruler accurately reflect restored layout bounds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isUserScrollingHorizontal && _horizontalScrollController.hasClients) {
        if (_horizontalScrollController.position.hasContentDimensions) {
          final targetScroll = widget.viewModel.playheadPosition * widget.viewModel.pixelsPerSecond;
          final clamped = targetScroll.clamp(0.0, _horizontalScrollController.position.maxScrollExtent);
          if ((_horizontalScrollController.offset - clamped).abs() > 0.5) {
            _horizontalScrollController.jumpTo(clamped);
          }
        }
      }
      _syncRulerScroll();
    });
  }

  void _checkAndAutoScrollToNewLayer(EditorViewModel vm) {
    if (!_verticalScrollController.hasClients) return;

    final hasNewAudio = vm.audioTracks.length > _prevAudioTrackCount;
    final hasNewOverlay = vm.overlayClips.length > _prevOverlayClipCount;
    final hasNewText = vm.textOverlays.length > _prevTextOverlayCount;
    final hasNewSticker = vm.stickerOverlays.length > _prevStickerOverlayCount;
    final hasNewEffect = vm.activeEffect.type != VideoEffectType.none && _prevEffectType == VideoEffectType.none;

    _prevAudioTrackCount = vm.audioTracks.length;
    _prevOverlayClipCount = vm.overlayClips.length;
    _prevTextOverlayCount = vm.textOverlays.length;
    _prevStickerOverlayCount = vm.stickerOverlays.length;
    _prevEffectType = vm.activeEffect.type;

    if (hasNewAudio || hasNewOverlay || hasNewText || hasNewSticker || hasNewEffect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_verticalScrollController.hasClients) return;

        // Calculate approximate vertical target offset
        double targetY = 0.0;
        targetY += AppDimensions.videoTrackHeight + 6; // Video track

        if (hasNewOverlay) {
          targetY += (vm.overlayClips.length - 1) * 42.0;
        } else {
          targetY += vm.overlayClips.length * 42.0;
        }

        if (hasNewEffect) {
          targetY += 38.0;
        } else if (vm.activeEffect.type != VideoEffectType.none) {
          targetY += 38.0;
        }

        if (hasNewText) {
          targetY += (vm.textOverlays.length - 1) * 40.0;
        } else {
          targetY += vm.textOverlays.length * 40.0;
        }

        if (hasNewSticker) {
          targetY += (vm.stickerOverlays.length - 1) * 36.0;
        } else {
          targetY += vm.stickerOverlays.length * 36.0;
        }

        if (hasNewAudio) {
          targetY += (vm.audioTracks.length - 1) * 48.0;
        }

        final maxScroll = _verticalScrollController.position.maxScrollExtent;
        final clampedTarget = targetY.clamp(0.0, maxScroll);

        _verticalScrollController.animateTo(
          clampedTarget,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final screenWidth = MediaQuery.of(context).size.width;
    final halfScreenWidth = screenWidth / 2;
    final totalDuration = viewModel.totalDurationInSeconds;
    final baseTrackWidth = totalDuration > 0.0
        ? totalDuration * viewModel.pixelsPerSecond
        : 5.0 * viewModel.pixelsPerSecond;
    double rawVideoTrackWidth = 0.0;
    for (int i = 0; i < viewModel.videoClips.length; i++) {
      rawVideoTrackWidth += viewModel.videoClips[i].durationInSeconds * viewModel.pixelsPerSecond + 4.0;
      if (i < viewModel.videoClips.length - 1) {
        final clip = viewModel.videoClips[i];
        final nextClip = viewModel.videoClips[i + 1];
        final hasTrans = viewModel.transitions.any(
          (t) => t.leftClipId == clip.id && t.rightClipId == nextClip.id && t.enabled && t.type != TransitionType.none,
        );
        rawVideoTrackWidth += hasTrans ? 84.0 : 44.0;
      }
    }
    rawVideoTrackWidth += 120.0;
    final totalTrackWidth = math.max(baseTrackWidth, rawVideoTrackWidth);

    return Container(
      width: double.infinity,
      color: AppColors.timelineTrackBg,
      child: Column(
        children: [
          // 1. Timeline Top Control Bar (Zoom slider, Duration badge, Clear Selection)
          _buildTimelineControlBar(viewModel),

          // 2. Pinned Timeline Ruler (Fixed at top of track canvas, click to seek & drag to scrub)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (viewModel.isPlaying) viewModel.pause();
              final localX = details.localPosition.dx;
              final targetTime = ((_rulerScrollController.hasClients ? _rulerScrollController.offset : 0.0) +
                      localX -
                      halfScreenWidth) /
                  viewModel.pixelsPerSecond;
              final clampedTime = targetTime.clamp(0.0, viewModel.totalDurationInSeconds);
              final snappedTime = viewModel.snapToNearestBeat(clampedTime);
              viewModel.seekTo(snappedTime);
              if (_horizontalScrollController.hasClients) {
                _horizontalScrollController.jumpTo(
                  (snappedTime * viewModel.pixelsPerSecond)
                      .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                );
              }
            },
            onHorizontalDragStart: (details) {
              if (viewModel.isPlaying) viewModel.pause();
              _isUserScrollingHorizontal = true;
            },
            onHorizontalDragUpdate: (details) {
              final deltaSec = (details.primaryDelta ?? 0.0) / viewModel.pixelsPerSecond;
              final newPlayhead = (viewModel.playheadPosition + deltaSec)
                  .clamp(0.0, viewModel.totalDurationInSeconds);
              final snappedPlayhead = viewModel.snapToNearestBeat(newPlayhead);
              viewModel.seekTo(snappedPlayhead);
              if (_horizontalScrollController.hasClients) {
                _horizontalScrollController.jumpTo(
                  (snappedPlayhead * viewModel.pixelsPerSecond)
                      .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                );
              }
            },
            onHorizontalDragEnd: (details) {
              _isUserScrollingHorizontal = false;
              _lastSyncedPlayhead = viewModel.playheadPosition;
            },
            onHorizontalDragCancel: () {
              _isUserScrollingHorizontal = false;
              _lastSyncedPlayhead = viewModel.playheadPosition;
            },
            child: Container(
              height: AppDimensions.timelineRulerHeight,
              width: double.infinity,
              color: AppColors.timelineRulerBg,
              child: SingleChildScrollView(
                controller: _rulerScrollController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: halfScreenWidth),
                  child: TimelineRuler(
                    totalDurationSeconds: totalDuration,
                    pixelsPerSecond: viewModel.pixelsPerSecond,
                  ),
                ),
              ),
            ),
          ),

          // 3. Multi-Track Vertically & Horizontally Scrollable Timeline Canvas
          Expanded(
            child: Stack(
              children: [
                // Two-Axis Coordinated Canvas
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Strictly isolate horizontal scrubbing from vertical layer navigation
                    if (notification.metrics.axis == Axis.horizontal) {
                      if (notification is ScrollStartNotification && notification.dragDetails != null) {
                        _isUserScrollingHorizontal = true;
                        if (viewModel.isPlaying) {
                          viewModel.pause();
                        }
                      } else if (notification is ScrollUpdateNotification && _isUserScrollingHorizontal) {
                        final rawPlayhead = (_horizontalScrollController.offset / viewModel.pixelsPerSecond)
                            .clamp(0.0, viewModel.totalDurationInSeconds);
                        final snappedPlayhead = viewModel.snapToNearestBeat(rawPlayhead);
                        viewModel.seekTo(snappedPlayhead);
                      } else if (notification is ScrollEndNotification) {
                        _isUserScrollingHorizontal = false;
                      }
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: halfScreenWidth),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: (details) {
                          if (viewModel.isPlaying) viewModel.pause();
                          final rawTapSec = (details.localPosition.dx / viewModel.pixelsPerSecond)
                              .clamp(0.0, viewModel.totalDurationInSeconds);
                          final snappedSec = viewModel.snapToNearestBeat(rawTapSec);
                          viewModel.seekTo(snappedSec);
                          if (_horizontalScrollController.hasClients) {
                            _horizontalScrollController.jumpTo(
                              (snappedSec * viewModel.pixelsPerSecond)
                                  .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                            );
                          }
                        },
                        child: SizedBox(
                          width: math.max(totalTrackWidth, 1.0),
                          child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          scrollDirection: Axis.vertical,
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 6),

                              // Track 1: Main Video Clips Track
                              _buildVideoTrack(viewModel),

                              // Track 2+: Secondary Overlay (PIP) Tracks
                              if (viewModel.overlayClips.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _buildOverlayTrackRows(viewModel, totalTrackWidth),
                              ],

                              // Track 3: Video Effects Track
                              if (viewModel.activeEffect.type != VideoEffectType.none) ...[
                                const SizedBox(height: 4),
                                _buildEffectsTrack(viewModel, totalTrackWidth),
                              ],

                              // Track 4+: Text / Subtitle Tracks
                              if (viewModel.textOverlays.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _buildTextTrackRows(viewModel, totalTrackWidth),
                              ],

                              // Track 5+: Stickers Tracks
                              if (viewModel.stickerOverlays.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _buildStickerTrackRows(viewModel, totalTrackWidth),
                              ],

                              // Track 6+: Background Audio & Sound Effect Tracks & Real-time Voice Recording
                              if (viewModel.audioTracks.isNotEmpty || viewModel.isRecordingVoice) ...[
                                const SizedBox(height: 4),
                                _buildAudioTrackRows(viewModel, totalTrackWidth),
                              ],

                              // Bottom padding to ensure comfortable scrolling of bottom layers
                              const SizedBox(height: 56),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),

                // 4. Fixed Center Playhead Needle (White Line + Cyan Marker spanning the canvas)
                _buildPlayheadNeedle(screenWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineControlBar(EditorViewModel viewModel) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
      decoration: const BoxDecoration(
        color: AppColors.timelineRulerBg,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Zoom Scale Slider
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_out_rounded, size: 16, color: AppColors.textMuted),
              SizedBox(
                width: 80,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.surfaceHighlight,
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: viewModel.pixelsPerSecond,
                    min: AppDimensions.minPixelsPerSecond,
                    max: AppDimensions.maxPixelsPerSecond,
                    onChanged: (val) => viewModel.setZoomScale(val),
                  ),
                ),
              ),
              const Icon(Icons.zoom_in_rounded, size: 16, color: AppColors.textMuted),
              if (viewModel.audioTracks.any((t) => t.beats.isNotEmpty)) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => viewModel.toggleSnapToBeat(),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: viewModel.isSnapToBeatEnabled
                          ? const Color(0xFFFFD600).withOpacity(0.18)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: viewModel.isSnapToBeatEnabled
                            ? const Color(0xFFFFD600)
                            : AppColors.divider,
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 11,
                          color: viewModel.isSnapToBeatEnabled
                              ? const Color(0xFFFFD600)
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'SNAP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: viewModel.isSnapToBeatEnabled
                                ? const Color(0xFFFFD600)
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Center-Right: Selected Element Duration or Helper
          if (viewModel.selectedClip != null)
            _buildSelectionBadge(
              icon: Icons.content_cut_rounded,
              color: AppColors.selectionBorder,
              text: 'Clip: ${TimeFormatter.formatSeconds(viewModel.selectedClip!.durationInSeconds)}',
              onClear: viewModel.clearSelection,
            )
          else if (viewModel.selectedOverlay != null)
            _buildSelectionBadge(
              icon: Icons.layers_rounded,
              color: AppColors.secondary,
              text: 'PIP: ${TimeFormatter.formatSeconds(viewModel.selectedOverlay!.durationInSeconds)}',
              onClear: viewModel.clearSelection,
            )
          else if (viewModel.isAudioSelected && viewModel.selectedAudioTrack != null)
            _buildSelectionBadge(
              icon: Icons.music_note_rounded,
              color: AppColors.secondary,
              text: 'Audio: ${TimeFormatter.formatSeconds(viewModel.selectedAudioTrack!.durationInSeconds)}',
              onClear: viewModel.clearSelection,
            )
          else if (viewModel.selectedTextId != null && viewModel.selectedTextOverlay != null)
            _buildSelectionBadge(
              icon: Icons.title_rounded,
              color: AppColors.accentPurple,
              text: 'Text: "${viewModel.selectedTextOverlay!.text.length > 12 ? '${viewModel.selectedTextOverlay!.text.substring(0, 10)}...' : viewModel.selectedTextOverlay!.text}" (${TimeFormatter.formatSeconds(viewModel.selectedTextOverlay!.durationInSeconds)})',
              onClear: viewModel.clearSelection,
            )
          else if (viewModel.selectedStickerId != null)
            _buildSelectionBadge(
              icon: Icons.star_rounded,
              color: Colors.amber,
              text: 'Sticker Selected',
              onClear: viewModel.clearSelection,
            )
          else
            Text(
              'Total: ${TimeFormatter.formatSeconds(viewModel.totalDurationInSeconds)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBadge({
    required IconData icon,
    required Color color,
    required String text,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: onClear,
          child: const Padding(
            padding: EdgeInsets.all(4.0),
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoTrack(EditorViewModel viewModel) {
    double runningStart = 0.0;
    return SizedBox(
      height: AppDimensions.videoTrackHeight,
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0.0,
        maxWidth: double.infinity,
        minHeight: AppDimensions.videoTrackHeight,
        maxHeight: AppDimensions.videoTrackHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int idx = 0; idx < viewModel.videoClips.length; idx++) ...[
              Builder(
                key: ValueKey('main_track_clip_builder_${viewModel.videoClips[idx].id}'),
                builder: (ctx) {
                  final clip = viewModel.videoClips[idx];
                  final clipStart = runningStart;
                  runningStart += clip.durationInSeconds;
                  final isSelected = viewModel.selectedClipIndex == idx;
                  final asset = viewModel.getAssetById(clip.assetId);

                  return TimelineClipItem(
                    key: ValueKey(clip.id),
                    clip: clip,
                    localPath: asset?.localPath,
                    thumbnailPath: asset?.thumbnailPath,
                    isPhoto: asset?.isPhoto ?? false,
                    index: idx,
                    isSelected: isSelected,
                    pixelsPerSecond: viewModel.pixelsPerSecond,
                    clipStartTime: clipStart,
                    currentPlayheadTime: viewModel.currentTimeInSeconds,
                    onKeyframeTap: (kf) {
                      if (viewModel.isPlaying) viewModel.pause();
                      final targetTime = (clipStart + kf.timeInSeconds).clamp(0.0, viewModel.totalDurationInSeconds);
                      viewModel.seekTo(targetTime);
                      if (_horizontalScrollController.hasClients) {
                        _horizontalScrollController.jumpTo(
                          (targetTime * viewModel.pixelsPerSecond)
                              .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                        );
                      }
                    },
                    onTap: () => viewModel.selectClip(idx),
                    onTapDown: (details) {
                      if (viewModel.isPlaying) viewModel.pause();
                      viewModel.selectClip(idx);
                      final offsetInClip = details.localPosition.dx / viewModel.pixelsPerSecond;
                      final targetTime = (clipStart + offsetInClip).clamp(0.0, viewModel.totalDurationInSeconds);
                      viewModel.seekTo(targetTime);
                      if (_horizontalScrollController.hasClients) {
                        _horizontalScrollController.jumpTo(
                          (targetTime * viewModel.pixelsPerSecond)
                              .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                        );
                      }
                    },
                    onTrimChanged: (newStart, newEnd) {
                      viewModel.updateClipTrim(idx, newStart, newEnd);
                    },
                  );
                },
              ),
              if (idx < viewModel.videoClips.length - 1)
                _buildTransitionButton(viewModel, idx),
            ],

            // + Add Clip Button on Timeline
            Container(
              key: const ValueKey('timeline_add_clip_button'),
              height: AppDimensions.videoTrackHeight,
              width: 44,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                border: Border.all(color: AppColors.divider),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_photo_alternate_rounded, color: AppColors.primary, size: 22),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => MediaPickerSheet(viewModel: viewModel),
                  );
                },
                tooltip: 'Add Media from Gallery or Device',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitionButton(EditorViewModel viewModel, int idx) {
    final clip = viewModel.videoClips[idx];
    final nextClip = viewModel.videoClips[idx + 1];
    Transition? existingTransition;
    try {
      existingTransition = viewModel.transitions.firstWhere(
        (t) => t.leftClipId == clip.id && t.rightClipId == nextClip.id && t.enabled && t.type != TransitionType.none,
      );
    } catch (_) {}

    final isSelected = viewModel.selectedTransitionBoundaryIndex == idx;

    return GestureDetector(
      key: ValueKey('transition_boundary_${clip.id}_${nextClip.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        viewModel.selectTransitionBoundary(idx);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => TransitionSelectionSheet(
            viewModel: viewModel,
            leftClipId: clip.id,
            rightClipId: nextClip.id,
            existingTransition: existingTransition,
          ),
        ).whenComplete(() {
          viewModel.selectTransitionBoundary(null);
        });
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        alignment: Alignment.center,
        child: existingTransition != null
            ? Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : AppColors.primary,
                    width: isSelected ? 1.8 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.5)
                          : Colors.black45,
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: isSelected ? Colors.black : AppColors.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${existingTransition.duration.toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.black : Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                width: 18,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.3)
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.divider,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    )
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.textMuted,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildOverlayTrackRows(EditorViewModel viewModel, double totalTrackWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: viewModel.overlayClips.asMap().entries.map((entry) {
        final idx = entry.key;
        final overlay = entry.value;
        final isSelected = viewModel.selectedOverlayIndex == idx;
        final width = math.max(overlay.durationInSeconds * viewModel.pixelsPerSecond, 40.0);
        final startOffset = overlay.startTimeInSeconds * viewModel.pixelsPerSecond;

        return Container(
          width: totalTrackWidth,
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 2.0),
          child: Stack(
            children: [
              Positioned(
                left: startOffset,
                top: 2,
                bottom: 2,
                width: width,
                child: GestureDetector(
                  onTap: () => viewModel.selectOverlay(idx),
                  onTapDown: (details) {
                    if (viewModel.isPlaying) viewModel.pause();
                    viewModel.selectOverlay(idx);
                    final targetTime = (overlay.startTimeInSeconds + (details.localPosition.dx / viewModel.pixelsPerSecond))
                        .clamp(0.0, viewModel.totalDurationInSeconds);
                    viewModel.seekTo(targetTime);
                    if (_horizontalScrollController.hasClients) {
                      _horizontalScrollController.jumpTo(
                        (targetTime * viewModel.pixelsPerSecond)
                            .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                      );
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    final deltaSec = details.primaryDelta! / viewModel.pixelsPerSecond;
                    final newStartSec = math.max(0.0, overlay.startTimeInSeconds + deltaSec);
                    viewModel.updateOverlayClipTiming(
                      overlay.id,
                      Duration(milliseconds: (newStartSec * 1000).round()),
                      overlay.duration,
                    );
                  },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      border: Border.all(
                        color: isSelected ? AppColors.secondary : AppColors.secondary.withOpacity(0.4),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.layers_rounded, size: 12, color: AppColors.secondary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  overlay.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected) ...[
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: _buildHandle(
                              isLeft: true,
                              color: AppColors.secondary,
                              onDrag: (dx) {
                                final deltaSec = dx / viewModel.pixelsPerSecond;
                                final curStart = overlay.startTimeInSeconds;
                                final curDur = overlay.durationInSeconds;
                                final newStart = math.max(0.0, curStart + deltaSec);
                                final newDur = curDur - (newStart - curStart);
                                if (newDur >= 0.4) {
                                  viewModel.updateOverlayClipTiming(
                                    overlay.id,
                                    Duration(milliseconds: (newStart * 1000).round()),
                                    Duration(milliseconds: (newDur * 1000).round()),
                                  );
                                }
                              },
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: _buildHandle(
                              isLeft: false,
                              color: AppColors.secondary,
                              onDrag: (dx) {
                                final deltaSec = dx / viewModel.pixelsPerSecond;
                                final newDur = math.max(0.4, overlay.durationInSeconds + deltaSec);
                                viewModel.updateOverlayClipTiming(
                                  overlay.id,
                                  overlay.startTime,
                                  Duration(milliseconds: (newDur * 1000).round()),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEffectsTrack(EditorViewModel viewModel, double totalTrackWidth) {
    final effect = viewModel.activeEffect;
    final width = totalTrackWidth;

    return Container(
      width: totalTrackWidth,
      height: 34,
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            bottom: 2,
            width: width,
            child: GestureDetector(
              onTap: () {
                viewModel.openDrawer(EditorCategory.effects);
              },
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: effect.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(color: effect.color, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(effect.icon, size: 14, color: effect.color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Effect: ${effect.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: effect.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: effect.color.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextTrackRows(EditorViewModel viewModel, double totalTrackWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: viewModel.textOverlays.map((text) {
        final isSelected = viewModel.selectedTextId == text.id;
        final width = math.max(text.durationInSeconds * viewModel.pixelsPerSecond, 36.0);
        final startOffset = text.startTimeInSeconds * viewModel.pixelsPerSecond;

        return Container(
          width: totalTrackWidth,
          height: AppDimensions.textTrackHeight,
          margin: const EdgeInsets.symmetric(vertical: 2.0),
          child: Stack(
            children: [
              Positioned(
                left: startOffset,
                top: 2,
                bottom: 2,
                width: width,
                child: TimelineTextTrackItem(
                  key: ValueKey(text.id),
                  text: text,
                  isSelected: isSelected,
                  width: width,
                  startOffset: startOffset,
                  viewModel: viewModel,
                  scrollController: _horizontalScrollController,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStickerTrackRows(EditorViewModel viewModel, double totalTrackWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: viewModel.stickerOverlays.map((sticker) {
        final isSelected = viewModel.selectedStickerId == sticker.id;
        final width = math.max(sticker.durationInSeconds * viewModel.pixelsPerSecond, 36.0);
        final startOffset = sticker.startTimeInSeconds * viewModel.pixelsPerSecond;

        return Container(
          width: totalTrackWidth,
          height: 32,
          margin: const EdgeInsets.symmetric(vertical: 2.0),
          child: Stack(
            children: [
              Positioned(
                left: startOffset,
                top: 2,
                bottom: 2,
                width: width,
                child: GestureDetector(
                  onTap: () => viewModel.selectSticker(sticker.id),
                  onTapDown: (details) {
                    if (viewModel.isPlaying) viewModel.pause();
                    viewModel.selectSticker(sticker.id);
                    final targetTime = (sticker.startTimeInSeconds + (details.localPosition.dx / viewModel.pixelsPerSecond))
                        .clamp(0.0, viewModel.totalDurationInSeconds);
                    viewModel.seekTo(targetTime);
                    if (_horizontalScrollController.hasClients) {
                      _horizontalScrollController.jumpTo(
                        (targetTime * viewModel.pixelsPerSecond)
                            .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                      );
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    final deltaSec = details.primaryDelta! / viewModel.pixelsPerSecond;
                    final newStartSec = math.max(0.0, sticker.startTimeInSeconds + deltaSec);
                    viewModel.updateStickerTiming(
                      sticker.id,
                      Duration(milliseconds: (newStartSec * 1000).round()),
                      sticker.duration,
                    );
                  },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.amber.withOpacity(0.5),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (sticker.preset.isEmoji)
                                Text(sticker.preset.content, style: const TextStyle(fontSize: 12))
                              else
                                Icon(sticker.preset.icon ?? Icons.star, size: 12, color: Colors.amber),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  sticker.preset.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected) ...[
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: _buildHandle(
                              isLeft: true,
                              color: Colors.amber,
                              onDrag: (dx) {
                                final deltaSec = dx / viewModel.pixelsPerSecond;
                                final curStart = sticker.startTimeInSeconds;
                                final curDur = sticker.durationInSeconds;
                                final newStart = math.max(0.0, curStart + deltaSec);
                                final newDur = curDur - (newStart - curStart);
                                if (newDur >= 0.3) {
                                  viewModel.updateStickerTiming(
                                    sticker.id,
                                    Duration(milliseconds: (newStart * 1000).round()),
                                    Duration(milliseconds: (newDur * 1000).round()),
                                  );
                                }
                              },
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: _buildHandle(
                              isLeft: false,
                              color: Colors.amber,
                              onDrag: (dx) {
                                final deltaSec = dx / viewModel.pixelsPerSecond;
                                final newDur = math.max(0.3, sticker.durationInSeconds + deltaSec);
                                viewModel.updateStickerTiming(
                                  sticker.id,
                                  sticker.startTime,
                                  Duration(milliseconds: (newDur * 1000).round()),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAudioTrackRows(EditorViewModel viewModel, double totalTrackWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...viewModel.audioTracks.map((track) {
          return AudioTrackItem(
            key: ValueKey(track.id),
            audioTrack: track,
            pixelsPerSecond: viewModel.pixelsPerSecond,
            viewModel: viewModel,
          );
        }),

        // Real-time Voice Recording Progress Track
        if (viewModel.isRecordingVoice)
          Container(
            width: totalTrackWidth,
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 2.0),
            child: Stack(
              children: [
                Positioned(
                  left: viewModel.recordingStartPlayhead * viewModel.pixelsPerSecond,
                  top: 2,
                  bottom: 2,
                  width: math.max(20.0, viewModel.currentRecordingSeconds * viewModel.pixelsPerSecond),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '● REC ${viewModel.currentRecordingSeconds.toStringAsFixed(1)}s',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHandle({required bool isLeft, required Color color, required ValueChanged<double> onDrag}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        onDrag(details.primaryDelta ?? 0.0);
      },
      child: Container(
        width: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(AppDimensions.radiusSm) : Radius.zero,
            right: !isLeft ? const Radius.circular(AppDimensions.radiusSm) : Radius.zero,
          ),
        ),
        child: Center(
          child: Container(
            width: 1.5,
            height: 10,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayheadNeedle(double screenWidth) {
    return Positioned(
      left: (screenWidth / 2) - 10,
      top: 0,
      bottom: 0,
      width: 20,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          if (widget.viewModel.isPlaying) widget.viewModel.pause();
          _isUserScrollingHorizontal = true;
        },
        onHorizontalDragUpdate: (details) {
          final deltaSec = (details.primaryDelta ?? 0.0) / widget.viewModel.pixelsPerSecond;
          final newPlayhead = (widget.viewModel.playheadPosition + deltaSec)
              .clamp(0.0, widget.viewModel.totalDurationInSeconds);
          widget.viewModel.seekTo(newPlayhead);
          if (_horizontalScrollController.hasClients) {
            _horizontalScrollController.jumpTo(
              (newPlayhead * widget.viewModel.pixelsPerSecond)
                  .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
            );
          }
        },
        onHorizontalDragEnd: (details) {
          _isUserScrollingHorizontal = false;
          _lastSyncedPlayhead = widget.viewModel.playheadPosition;
        },
        onHorizontalDragCancel: () {
          _isUserScrollingHorizontal = false;
          _lastSyncedPlayhead = widget.viewModel.playheadPosition;
        },
        child: Column(
          children: [
            // Playhead Header Indicator Cap (Mouse draggable handle)
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 16,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.playheadHandle,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.arrow_drop_down, size: 14, color: Colors.black),
                ),
              ),
            ),

            // Vertical White Playhead Line
            Expanded(
              child: Center(
                child: Container(
                  width: AppDimensions.playheadNeedleWidth,
                  color: AppColors.playheadLine,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
