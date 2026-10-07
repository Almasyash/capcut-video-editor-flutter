import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// CapCut-style timeline PIP overlay track clip widget with primary cyan/blue selection border,
/// dedicated left/right draggable trim handles with generous touch targets,
/// direct timeline slide translation, and single-snapshot undo history.
class TimelineOverlayTrackItem extends StatefulWidget {
  final OverlayClip overlay;
  final int overlayIndex;
  final bool isSelected;
  final double width;
  final double startOffset;
  final EditorViewModel viewModel;
  final ScrollController? scrollController;

  const TimelineOverlayTrackItem({
    super.key,
    required this.overlay,
    required this.overlayIndex,
    required this.isSelected,
    required this.width,
    required this.startOffset,
    required this.viewModel,
    this.scrollController,
  });

  static double getMaxProjectDuration(EditorViewModel viewModel, OverlayClip overlay) {
    if (viewModel.videoClips.isNotEmpty) {
      final videoDuration = viewModel.videoClips.fold(0.0, (sum, c) => sum + c.durationInSeconds);
      return math.max(videoDuration, math.max(viewModel.totalDurationInSeconds, overlay.startTimeInSeconds + overlay.durationInSeconds));
    }
    return math.max(600.0, math.max(viewModel.totalDurationInSeconds + 60.0, overlay.startTimeInSeconds + overlay.durationInSeconds + 60.0));
  }

  @override
  State<TimelineOverlayTrackItem> createState() => _TimelineOverlayTrackItemState();
}

class _TimelineOverlayTrackItemState extends State<TimelineOverlayTrackItem> {
  double _dragStartGlobalX = 0.0;
  double _dragStartScrollOffset = 0.0;
  Duration _initialStart = Duration.zero;
  Duration _initialDuration = Duration.zero;
  bool _isDraggingLeft = false;
  bool _isDraggingRight = false;
  bool _isDraggingBody = false;

  void _checkAutoScroll(double globalX) {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    const edgeMargin = 44.0;
    final maxScroll = sc.position.maxScrollExtent;
    final currentOffset = sc.offset;

    if (globalX > screenWidth - edgeMargin && currentOffset < maxScroll) {
      final intensity = ((globalX - (screenWidth - edgeMargin)) / edgeMargin).clamp(0.0, 1.0);
      final scrollStep = 8.0 + 16.0 * intensity;
      final newOffset = (currentOffset + scrollStep).clamp(0.0, maxScroll);
      sc.jumpTo(newOffset);
    } else if (globalX < edgeMargin && currentOffset > 0.0) {
      final intensity = ((edgeMargin - globalX) / edgeMargin).clamp(0.0, 1.0);
      final scrollStep = 8.0 + 16.0 * intensity;
      final newOffset = (currentOffset - scrollStep).clamp(0.0, maxScroll);
      sc.jumpTo(newOffset);
    }
  }

  void _onLeftHandleDragStart(DragStartDetails details) {
    if (widget.overlay.isLocked) return;
    _isDraggingLeft = true;
    _dragStartGlobalX = details.globalPosition.dx;
    _dragStartScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    _initialStart = widget.overlay.startTime;
    _initialDuration = widget.overlay.duration;
  }

  void _onLeftHandleDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingLeft) return;
    _checkAutoScroll(details.globalPosition.dx);

    final pps = widget.viewModel.pixelsPerSecond;
    final currentScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    final deltaPx = (details.globalPosition.dx - _dragStartGlobalX) +
        (currentScrollOffset - _dragStartScrollOffset);
    final deltaSec = deltaPx / pps;
    final initialStartSec = _initialStart.inMilliseconds / 1000.0;
    final initialDurSec = _initialDuration.inMilliseconds / 1000.0;
    final initialEndSec = initialStartSec + initialDurSec;

    final proposedStartSec = initialStartSec + deltaSec;
    const minStart = 0.0;
    final maxStart = initialEndSec - 0.3; // Minimum duration 0.3s
    final newStartSec = proposedStartSec.clamp(minStart, math.max(minStart, maxStart));
    final newDurSec = initialEndSec - newStartSec;

    widget.viewModel.updateOverlayClipTiming(
      widget.overlay.id,
      Duration(milliseconds: (newStartSec * 1000).round()),
      Duration(milliseconds: (newDurSec * 1000).round()),
      saveSnapshot: false,
      notify: true,
    );
  }

  void _onLeftHandleDragEnd(DragEndDetails details) {
    if (!_isDraggingLeft) return;
    _isDraggingLeft = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  void _onLeftHandleDragCancel() {
    if (!_isDraggingLeft) return;
    _isDraggingLeft = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  void _onRightHandleDragStart(DragStartDetails details) {
    if (widget.overlay.isLocked) return;
    _isDraggingRight = true;
    _dragStartGlobalX = details.globalPosition.dx;
    _dragStartScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    _initialStart = widget.overlay.startTime;
    _initialDuration = widget.overlay.duration;
  }

  void _onRightHandleDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingRight) return;
    _checkAutoScroll(details.globalPosition.dx);

    final pps = widget.viewModel.pixelsPerSecond;
    final currentScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    final deltaPx = (details.globalPosition.dx - _dragStartGlobalX) +
        (currentScrollOffset - _dragStartScrollOffset);
    final deltaSec = deltaPx / pps;
    final maxProjectDuration = TimelineOverlayTrackItem.getMaxProjectDuration(widget.viewModel, widget.overlay);
    final initialStartSec = _initialStart.inMilliseconds / 1000.0;
    final initialDurSec = _initialDuration.inMilliseconds / 1000.0;

    final proposedEndSec = initialStartSec + initialDurSec + deltaSec;
    final minEndSec = initialStartSec + 0.3; // Minimum duration 0.3s
    final maxEndSec = maxProjectDuration;
    final newEndSec = proposedEndSec.clamp(minEndSec, math.max(minEndSec, maxEndSec));
    final newDurSec = newEndSec - initialStartSec;

    widget.viewModel.updateOverlayClipTiming(
      widget.overlay.id,
      _initialStart,
      Duration(milliseconds: (newDurSec * 1000).round()),
      saveSnapshot: false,
      notify: true,
    );
  }

  void _onRightHandleDragEnd(DragEndDetails details) {
    if (!_isDraggingRight) return;
    _isDraggingRight = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  void _onRightHandleDragCancel() {
    if (!_isDraggingRight) return;
    _isDraggingRight = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  void _onBodyDragStart(DragStartDetails details) {
    if (widget.overlay.isLocked) return;
    _isDraggingBody = true;
    _dragStartGlobalX = details.globalPosition.dx;
    _dragStartScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    _initialStart = widget.overlay.startTime;
    _initialDuration = widget.overlay.duration;
  }

  void _onBodyDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingBody) return;
    _checkAutoScroll(details.globalPosition.dx);

    final pps = widget.viewModel.pixelsPerSecond;
    final currentScrollOffset = (widget.scrollController?.hasClients == true)
        ? widget.scrollController!.offset
        : 0.0;
    final deltaPx = (details.globalPosition.dx - _dragStartGlobalX) +
        (currentScrollOffset - _dragStartScrollOffset);
    final deltaSec = deltaPx / pps;
    final maxProjectDuration = TimelineOverlayTrackItem.getMaxProjectDuration(widget.viewModel, widget.overlay);
    final initialStartSec = _initialStart.inMilliseconds / 1000.0;
    final initialDurSec = _initialDuration.inMilliseconds / 1000.0;

    final proposedStartSec = initialStartSec + deltaSec;
    const minStart = 0.0;
    final maxStart = math.max(0.0, maxProjectDuration - initialDurSec);
    final newStartSec = proposedStartSec.clamp(minStart, maxStart);

    widget.viewModel.updateOverlayClipTiming(
      widget.overlay.id,
      Duration(milliseconds: (newStartSec * 1000).round()),
      _initialDuration,
      saveSnapshot: false,
      notify: true,
    );
  }

  void _onBodyDragEnd(DragEndDetails details) {
    if (!_isDraggingBody) return;
    _isDraggingBody = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  void _onBodyDragCancel() {
    if (!_isDraggingBody) return;
    _isDraggingBody = false;
    widget.viewModel.commitOverlayTiming(
      widget.overlay.id,
      oldStart: _initialStart,
      oldDuration: _initialDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final overlay = widget.overlay;
    final handleHitWidth = math.min(32.0, widget.width / 2.2);
    final visualHandleWidth = math.min(14.0, handleHitWidth);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(
          color: isSelected ? AppColors.primary : const Color(0xFF0072FF).withValues(alpha: 0.5),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Stack(
        children: [
          // 1. Clip Body: Tap to select & seek; Drag to slide across timeline
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.viewModel.selectOverlay(widget.overlayIndex),
              onTapDown: (details) {
                if (widget.viewModel.isPlaying) widget.viewModel.pause();
                widget.viewModel.selectOverlay(widget.overlayIndex);
                final targetTime = (overlay.startTimeInSeconds + (details.localPosition.dx / widget.viewModel.pixelsPerSecond))
                    .clamp(0.0, widget.viewModel.totalDurationInSeconds);
                widget.viewModel.seekTo(targetTime);
                if (widget.scrollController?.hasClients ?? false) {
                  widget.scrollController!.jumpTo(
                    (targetTime * widget.viewModel.pixelsPerSecond)
                        .clamp(0.0, widget.scrollController!.position.maxScrollExtent),
                  );
                }
              },
              onHorizontalDragStart: _onBodyDragStart,
              onHorizontalDragUpdate: _onBodyDragUpdate,
              onHorizontalDragEnd: _onBodyDragEnd,
              onHorizontalDragCancel: _onBodyDragCancel,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? visualHandleWidth + 4.0 : 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildThumbPreview(overlay),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          overlay.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (overlay.isLocked)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.lock_rounded, size: 11, color: Color(0xFFFFB300)),
                        ),
                      if (!overlay.isVisible)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.visibility_off_rounded, size: 11, color: Colors.white54),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Left Trim Handle
          if (isSelected && !overlay.isLocked)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: handleHitWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onLeftHandleDragStart,
                onHorizontalDragUpdate: _onLeftHandleDragUpdate,
                onHorizontalDragEnd: _onLeftHandleDragEnd,
                onHorizontalDragCancel: _onLeftHandleDragCancel,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: visualHandleWidth,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(AppDimensions.radiusSm),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 1.5,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. Right Trim Handle
          if (isSelected && !overlay.isLocked)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: handleHitWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onRightHandleDragStart,
                onHorizontalDragUpdate: _onRightHandleDragUpdate,
                onHorizontalDragEnd: _onRightHandleDragEnd,
                onHorizontalDragCancel: _onRightHandleDragCancel,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: visualHandleWidth,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(AppDimensions.radiusSm),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 1.5,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbPreview(OverlayClip overlay) {
    final isPhoto = overlay.isPhoto || overlay.isPhotoOverlay;
    final thumb = overlay.thumbnailPath ?? (isPhoto ? overlay.localPath : null);
    if (thumb != null && thumb.isNotEmpty && File(thumb).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Image.file(
          File(thumb),
          width: 16,
          height: 16,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
            size: 12,
            color: AppColors.primary,
          ),
        ),
      );
    }
    return Icon(
      isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
      size: 12,
      color: AppColors.primary,
    );
  }
}
