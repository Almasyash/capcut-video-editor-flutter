import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/audio_track_item.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_clip_item.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_ruler.dart';

/// Multi-track timeline section containing Ruler, Main Video Track,
/// Overlay/PIP Layer Track, Audio Track, Subtitles Track, Sticker Track, and fixed Playhead.
class TimelineSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const TimelineSection({
    super.key,
    required this.viewModel,
  });

  @override
  State<TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<TimelineSection> {
  final ScrollController _scrollController = ScrollController();
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelUpdated);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onViewModelUpdated() {
    // Synchronize scroll position during active playback ONLY when user isn't manually dragging
    if (widget.viewModel.isPlaying && !_isUserScrolling && _scrollController.hasClients) {
      final targetScroll = widget.viewModel.playheadPosition * widget.viewModel.pixelsPerSecond;
      if ((_scrollController.offset - targetScroll).abs() > 2.0) {
        _scrollController.jumpTo(targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final screenWidth = MediaQuery.of(context).size.width;
    final halfScreenWidth = screenWidth / 2;

    return Container(
      color: AppColors.timelineTrackBg,
      child: Column(
        children: [
          // 1. Timeline Top Bar (Duration, Zoom buttons, Clear selection)
          _buildTimelineHeader(viewModel),

          // 2. Interactive Scrollable Multi-Track Canvas with Fixed Playhead Needle
          Expanded(
            child: Stack(
              children: [
                // Scrollable Tracks Area
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Only pause when USER drags (dragDetails != null), not on programmatic jumpTo
                    if (notification is ScrollStartNotification && notification.dragDetails != null) {
                      _isUserScrolling = true;
                      if (viewModel.isPlaying) {
                        viewModel.pause();
                      }
                    } else if (notification is ScrollUpdateNotification) {
                      if (_scrollController.hasClients && _isUserScrolling) {
                        final newPosSeconds = _scrollController.offset / viewModel.pixelsPerSecond;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            viewModel.seekTo(newPosSeconds);
                          }
                        });
                      }
                    } else if (notification is ScrollEndNotification) {
                      _isUserScrolling = false;
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: halfScreenWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ruler Track
                          TimelineRuler(
                            totalDurationSeconds: math.max(viewModel.totalDurationInSeconds, 1.0),
                            pixelsPerSecond: viewModel.pixelsPerSecond,
                          ),

                          const SizedBox(height: 6),

                          // Main Video Clip Track
                          _buildVideoTrack(viewModel),

                          // Secondary Overlay (PIP) Track
                          if (viewModel.overlayClips.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildOverlayTrack(viewModel),
                          ],

                          const SizedBox(height: 4),

                          // Background Audio Track
                          if (viewModel.audioTrack != null)
                            AudioTrackItem(
                              audioTrack: viewModel.audioTrack!,
                              pixelsPerSecond: viewModel.pixelsPerSecond,
                            ),

                          // Stickers Track
                          if (viewModel.stickerOverlays.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildStickerTrack(viewModel),
                          ],

                          const SizedBox(height: 4),

                          // Text / Subtitle Track
                          _buildTextTrack(viewModel),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Fixed Center Playhead Needle (White Line + Cyan Marker)
                _buildPlayheadNeedle(screenWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader(EditorViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Zoom In / Out Controls
          Row(
            children: [
              const Icon(Icons.zoom_out_rounded, size: 16, color: AppColors.textMuted),
              SizedBox(
                width: 110,
                child: ExcludeSemantics(
                  child: Slider(
                    value: viewModel.pixelsPerSecond,
                    min: AppDimensions.minPixelsPerSecond,
                    max: AppDimensions.maxPixelsPerSecond,
                    onChanged: (val) => viewModel.setZoomScale(val),
                  ),
                ),
              ),
              const Icon(Icons.zoom_in_rounded, size: 16, color: AppColors.textMuted),
            ],
          ),

          // Center-Right: Selected Clip Duration or Helper
          if (viewModel.selectedClip != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.selectionBorder, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.content_cut_rounded, size: 11, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        TimeFormatter.formatSeconds(viewModel.selectedClip!.durationInSeconds),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: viewModel.clearSelection,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                  ),
                ),
              ],
            )
          else if (viewModel.selectedOverlay != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.secondary, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.layers_rounded, size: 11, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Text(
                        'PIP: ${TimeFormatter.formatSeconds(viewModel.selectedOverlay!.durationInSeconds)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: viewModel.clearSelection,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                  ),
                ),
              ],
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

  Widget _buildVideoTrack(EditorViewModel viewModel) {
    return SizedBox(
      height: AppDimensions.videoTrackHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...viewModel.videoClips.asMap().entries.map((entry) {
            final idx = entry.key;
            final clip = entry.value;
            final isSelected = viewModel.selectedClipIndex == idx;

            return TimelineClipItem(
              key: ValueKey(clip.id),
              clip: clip,
              index: idx,
              isSelected: isSelected,
              pixelsPerSecond: viewModel.pixelsPerSecond,
              onTap: () => viewModel.selectClip(idx),
              onTrimChanged: (newStart, newEnd) {
                viewModel.updateClipTrim(idx, newStart, newEnd);
              },
            );
          }),

          // + Add Clip Button on Timeline
          Container(
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
              tooltip: 'Add Video Clip from Gallery',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayTrack(EditorViewModel viewModel) {
    final totalTrackWidth = (viewModel.totalDurationInSeconds + 5.0) * viewModel.pixelsPerSecond;

    return SizedBox(
      width: totalTrackWidth,
      height: 38,
      child: Stack(
        children: viewModel.overlayClips.asMap().entries.map((entry) {
          final idx = entry.key;
          final overlay = entry.value;
          final isSelected = viewModel.selectedOverlayIndex == idx;
          final width = math.max(overlay.durationInSeconds * viewModel.pixelsPerSecond, 30.0);
          final startOffset = overlay.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: GestureDetector(
              onTap: () => viewModel.selectOverlay(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(
                    color: isSelected ? AppColors.secondary : AppColors.secondary.withOpacity(0.4),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.layers_rounded, size: 12, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Expanded(
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
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStickerTrack(EditorViewModel viewModel) {
    final totalTrackWidth = (viewModel.totalDurationInSeconds + 5.0) * viewModel.pixelsPerSecond;

    return SizedBox(
      width: totalTrackWidth,
      height: 30,
      child: Stack(
        children: viewModel.stickerOverlays.map((sticker) {
          final width = math.max(sticker.durationInSeconds * viewModel.pixelsPerSecond, 24.0);
          final startOffset = sticker.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  if (sticker.preset.isEmoji)
                    Text(sticker.preset.content, style: const TextStyle(fontSize: 12))
                  else
                    Icon(sticker.preset.icon ?? Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sticker.preset.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Colors.white70),
                    ),
                  ),
                  InkWell(
                    onTap: () => viewModel.removeSticker(sticker.id),
                    child: const Icon(Icons.close, size: 10, color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextTrack(EditorViewModel viewModel) {
    if (viewModel.textOverlays.isEmpty) return const SizedBox.shrink();

    final totalTrackWidth = (viewModel.totalDurationInSeconds + 5.0) * viewModel.pixelsPerSecond;

    return SizedBox(
      width: totalTrackWidth,
      height: AppDimensions.textTrackHeight,
      child: Stack(
        children: viewModel.textOverlays.map((text) {
          final width = text.durationInSeconds * viewModel.pixelsPerSecond;
          final startOffset = text.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: AppColors.textTrackBg,
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                border: Border.all(color: AppColors.textTrackAccent.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.title_rounded, size: 12, color: AppColors.textTrackAccent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      text.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: text.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlayheadNeedle(double screenWidth) {
    return Positioned(
      left: (screenWidth / 2) - (AppDimensions.playheadNeedleWidth / 2),
      top: 0,
      bottom: 0,
      width: AppDimensions.playheadNeedleWidth,
      child: IgnorePointer(
        child: Column(
          children: [
            // Playhead Header Indicator Cap
            Container(
              width: 14,
              height: 12,
              decoration: const BoxDecoration(
                color: AppColors.playheadHandle,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
              child: const Center(
                child: Icon(Icons.arrow_drop_down, size: 12, color: Colors.black),
              ),
            ),

            // Vertical White Playhead Line
            Expanded(
              child: Container(
                width: AppDimensions.playheadNeedleWidth,
                color: AppColors.playheadLine,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
