import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'audio_track_item.dart';
import 'timeline_clip_item.dart';
import 'timeline_ruler.dart';

/// Full interactive timeline section containing time ruler, video track,
/// audio track, text track, fixed center playhead needle, and zoom controller.
class TimelineSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const TimelineSection({super.key, required this.viewModel});

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
    // Synchronize scroll position ONLY during active playback if user isn't manually dragging
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
                    if (notification is ScrollStartNotification) {
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
                            totalDurationSeconds: viewModel.totalDurationInSeconds,
                            pixelsPerSecond: viewModel.pixelsPerSecond,
                          ),

                          const SizedBox(height: 6),

                          // Main Video Clip Track
                          _buildVideoTrack(viewModel),

                          const SizedBox(height: 6),

                          // Background Audio Track
                          if (viewModel.audioTrack != null)
                            AudioTrackItem(
                              audioTrack: viewModel.audioTrack!,
                              pixelsPerSecond: viewModel.pixelsPerSecond,
                            ),

                          const SizedBox(height: 6),

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
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.accentAmber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Clip: ${viewModel.selectedClip!.durationInSeconds.toStringAsFixed(2)}s',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentAmber),
                ),
              ],
            )
          else
            const Text(
              'Tap clip to edit',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),

          // Right: Fast Forward / Rewind 1 sec
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.replay_5_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: () => viewModel.seekBy(-1.0),
                tooltip: 'Back 1s',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.forward_5_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: () => viewModel.seekBy(1.0),
                tooltip: 'Forward 1s',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
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
            final index = entry.key;
            final clip = entry.value;
            final isSelected = viewModel.selectedClipIndex == index;

            return TimelineClipItem(
              clip: clip,
              index: index,
              isSelected: isSelected,
              pixelsPerSecond: viewModel.pixelsPerSecond,
              onTap: () => viewModel.selectClip(index),
              onTrimChanged: (newStart, newEnd) {
                viewModel.updateClipTrim(index, newStart, newEnd);
              },
            );
          }),

          // Inline Add Button (+) at end of track
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
              icon: const Icon(Icons.add_rounded, color: AppColors.primary, size: 24),
              onPressed: viewModel.addNewClip,
              tooltip: 'Add Video Clip',
            ),
          ),
        ],
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
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
