import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'audio_track_item.dart';
import 'media_picker_sheet.dart';
import 'timeline_clip_item.dart';
import 'timeline_ruler.dart';

/// CapCut-style Multi-Track Interactive Timeline with universal trimming and dragging
/// for Video clips, Audio tracks, PIP Overlays, Text layers, and Stickers.
class TimelineSection extends StatefulWidget {
  final EditorViewModel viewModel;

  const TimelineSection({super.key, required this.viewModel});

  @override
  State<TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<TimelineSection> {
  late final ScrollController _scrollController;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;

    if (widget.viewModel.isPlaying && !_isUserScrolling && _scrollController.hasClients) {
      final targetScroll = widget.viewModel.playheadPosition * widget.viewModel.pixelsPerSecond;
      _scrollController.jumpTo(targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final screenWidth = MediaQuery.of(context).size.width;
    final halfScreenWidth = screenWidth / 2;

    return Container(
      width: double.infinity,
      color: AppColors.timelineTrackBg,
      child: Column(
        children: [
          // 1. Timeline Top Control Bar (Zoom slider, Duration badge, Clear Selection)
          _buildTimelineControlBar(viewModel),

          // 2. Multi-Track Scrollable Timeline Canvas
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification && notification.dragDetails != null) {
                      _isUserScrolling = true;
                      if (viewModel.isPlaying) {
                        viewModel.pause();
                      }
                    } else if (notification is ScrollUpdateNotification && _isUserScrolling) {
                      final newPlayhead = _scrollController.offset / viewModel.pixelsPerSecond;
                      viewModel.seekTo(newPlayhead);
                    } else if (notification is ScrollEndNotification) {
                      _isUserScrolling = false;
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
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

                          // Background Audio Track(s)
                          if (viewModel.audioTracks.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            ...viewModel.audioTracks.map((track) {
                              return AudioTrackItem(
                                key: ValueKey(track.id),
                                audioTrack: track,
                                pixelsPerSecond: viewModel.pixelsPerSecond,
                                viewModel: viewModel,
                              );
                            }),
                          ],

                          // Stickers Track
                          if (viewModel.stickerOverlays.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildStickerTrack(viewModel),
                          ],

                          const SizedBox(height: 4),

                          // Text / Subtitle Track
                          if (viewModel.textOverlays.isNotEmpty)
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
    return SizedBox(
      height: AppDimensions.videoTrackHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...viewModel.videoClips.asMap().entries.map((entry) {
            final idx = entry.key;
            final clip = entry.value;
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
              tooltip: 'Add Media from Gallery or Device',
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
          final width = math.max(overlay.durationInSeconds * viewModel.pixelsPerSecond, 40.0);
          final startOffset = overlay.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: GestureDetector(
              onTap: () => viewModel.selectOverlay(idx),
              onHorizontalDragUpdate: (details) {
                // Middle drag: slide position across timeline
                final deltaSec = details.primaryDelta! / viewModel.pixelsPerSecond;
                final newStartSec = math.max(0.0, overlay.startTimeInSeconds + deltaSec);
                viewModel.updateOverlayClipTiming(
                  overlay.id,
                  Duration(milliseconds: (newStartSec * 1000).round()),
                  overlay.duration,
                );
              },
              child: Container(
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
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStickerTrack(EditorViewModel viewModel) {
    final totalTrackWidth = (viewModel.totalDurationInSeconds + 5.0) * viewModel.pixelsPerSecond;

    return SizedBox(
      width: totalTrackWidth,
      height: 32,
      child: Stack(
        children: viewModel.stickerOverlays.map((sticker) {
          final isSelected = viewModel.selectedStickerId == sticker.id;
          final width = math.max(sticker.durationInSeconds * viewModel.pixelsPerSecond, 36.0);
          final startOffset = sticker.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: GestureDetector(
              onTap: () => viewModel.selectSticker(sticker.id),
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
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextTrack(EditorViewModel viewModel) {
    final totalTrackWidth = (viewModel.totalDurationInSeconds + 5.0) * viewModel.pixelsPerSecond;

    return SizedBox(
      width: totalTrackWidth,
      height: AppDimensions.textTrackHeight,
      child: Stack(
        children: viewModel.textOverlays.map((text) {
          final isSelected = viewModel.selectedTextId == text.id;
          final width = math.max(text.durationInSeconds * viewModel.pixelsPerSecond, 36.0);
          final startOffset = text.startTimeInSeconds * viewModel.pixelsPerSecond;

          return Positioned(
            left: startOffset,
            top: 2,
            bottom: 2,
            width: width,
            child: GestureDetector(
              onTap: () => viewModel.selectText(text.id),
              onHorizontalDragUpdate: (details) {
                final deltaSec = details.primaryDelta! / viewModel.pixelsPerSecond;
                final newStartSec = math.max(0.0, text.startTimeInSeconds + deltaSec);
                viewModel.updateTextOverlayTiming(
                  text.id,
                  Duration(milliseconds: (newStartSec * 1000).round()),
                  text.duration,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.textTrackBg,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(
                    color: isSelected ? AppColors.accentPurple : AppColors.textTrackAccent.withOpacity(0.5),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.title_rounded, size: 12, color: AppColors.textTrackAccent),
                          const SizedBox(width: 4),
                          Flexible(
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
                    if (isSelected) ...[
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: _buildHandle(
                          isLeft: true,
                          color: AppColors.accentPurple,
                          onDrag: (dx) {
                            final deltaSec = dx / viewModel.pixelsPerSecond;
                            final curStart = text.startTimeInSeconds;
                            final curDur = text.durationInSeconds;
                            final newStart = math.max(0.0, curStart + deltaSec);
                            final newDur = curDur - (newStart - curStart);
                            if (newDur >= 0.3) {
                              viewModel.updateTextOverlayTiming(
                                text.id,
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
                          color: AppColors.accentPurple,
                          onDrag: (dx) {
                            final deltaSec = dx / viewModel.pixelsPerSecond;
                            final newDur = math.max(0.3, text.durationInSeconds + deltaSec);
                            viewModel.updateTextOverlayTiming(
                              text.id,
                              text.startTime,
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
          );
        }).toList(),
      ),
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
