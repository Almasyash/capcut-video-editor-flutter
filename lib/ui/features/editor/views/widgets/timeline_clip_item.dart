import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';

/// Interactive CapCut timeline video clip widget with filmstrip preview,
/// yellow selection border, and draggable left/right trim handles.
class TimelineClipItem extends StatelessWidget {
  final VideoClip clip;
  final String? localPath;
  final String? thumbnailPath;
  final bool isPhoto;
  final int index;
  final bool isSelected;
  final double pixelsPerSecond;
  final VoidCallback onTap;
  final Function(Duration newTrimStart, Duration newTrimEnd) onTrimChanged;

  const TimelineClipItem({
    super.key,
    required this.clip,
    this.localPath,
    this.thumbnailPath,
    this.isPhoto = false,
    required this.index,
    required this.isSelected,
    required this.pixelsPerSecond,
    required this.onTap,
    required this.onTrimChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clipWidth = clip.durationInSeconds * pixelsPerSecond;
    final hasLocalFile = localPath != null &&
        !localPath!.startsWith('content://') &&
        !kIsWeb &&
        File(localPath!).existsSync();

    final displayImagePath = isPhoto ? localPath : thumbnailPath;
    final hasDisplayImage = displayImagePath != null &&
        !displayImagePath.startsWith('content://') &&
        !kIsWeb &&
        File(displayImagePath).existsSync();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: math.max(clipWidth, 24.0),
        height: AppDimensions.videoTrackHeight,
        margin: const EdgeInsets.symmetric(horizontal: 1.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Filmstrip Body Container
            Positioned.fill(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(
                    color: isSelected ? AppColors.selectionBorder : AppColors.videoTrackBorder,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  gradient: LinearGradient(
                    colors: clip.previewGradient,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Real image thumbnail if displayImagePath is available
                    if (hasDisplayImage)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.6,
                          child: Image.file(
                            File(displayImagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                          ),
                        ),
                      ),

                    // Simulated Filmstrip frame dividers
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FilmstripPainter(),
                      ),
                    ),

                    // Top-Left: Clip Title & Duration Pill
                    Positioned(
                      top: 4,
                      left: isSelected ? AppDimensions.trimHandleWidth + 2 : 6,
                      right: isSelected ? AppDimensions.trimHandleWidth + 2 : 6,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 30) {
                            return const SizedBox.shrink();
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(clip.previewIcon, size: 10, color: Colors.white70),
                              if (constraints.maxWidth > 70) ...[
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    clip.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                                    ),
                                  ),
                                ),
                              ],
                              if (constraints.maxWidth > 50)
                                Container(
                                  margin: const EdgeInsets.only(left: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    TimeFormatter.formatSeconds(clip.durationInSeconds, showMilliseconds: false),
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Bottom-Left: Real File Source Badge if local file
                    if (hasLocalFile)
                      Positioned(
                        bottom: 3,
                        left: isSelected ? AppDimensions.trimHandleWidth + 4 : 6,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (clipWidth < 60) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 0.5),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_open_rounded, size: 8, color: AppColors.primary),
                                  SizedBox(width: 2),
                                  Text('LOCAL FILE', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    // Bottom-Right: Speed Badge if != 1.0
                    if ((clip.speed - 1.0).abs() > 0.05)
                      Positioned(
                        bottom: 4,
                        right: isSelected ? AppDimensions.trimHandleWidth + 4 : 6,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (clipWidth < 40) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${clip.speed.toStringAsFixed(1)}x',
                                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 2. Left Draggable Trim Handle (Visible when selected)
            if (isSelected)
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: AppDimensions.trimHandleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final deltaSeconds = details.delta.dx / pixelsPerSecond;
                    final deltaMs = (deltaSeconds * clip.speed * 1000).round();
                    final proposedTrimStartMs = clip.trimStart.inMilliseconds + deltaMs;

                    if (proposedTrimStartMs >= 0 &&
                        (clip.trimEnd.inMilliseconds - proposedTrimStartMs) >= 300) {
                      onTrimChanged(
                        Duration(milliseconds: proposedTrimStartMs),
                        clip.trimEnd,
                      );
                    }
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.trimHandle,
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(AppDimensions.radiusSm)),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 3. Right Draggable Trim Handle (Visible when selected)
            if (isSelected)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: AppDimensions.trimHandleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final deltaSeconds = details.delta.dx / pixelsPerSecond;
                    final deltaMs = (deltaSeconds * clip.speed * 1000).round();
                    final proposedTrimEndMs = clip.trimEnd.inMilliseconds + deltaMs;

                    if (proposedTrimEndMs <= clip.originalDuration.inMilliseconds &&
                        (proposedTrimEndMs - clip.trimStart.inMilliseconds) >= 300) {
                      onTrimChanged(
                        clip.trimStart,
                        Duration(milliseconds: proposedTrimEndMs),
                      );
                    }
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.trimHandle,
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(AppDimensions.radiusSm)),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilmstripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const frameWidth = 40.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;

    for (double x = frameWidth; x < size.width; x += frameWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
