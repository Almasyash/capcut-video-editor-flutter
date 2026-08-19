import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Top Video Preview Screen containing the live video canvas, aspect-ratio viewport,
/// active subtitles, timecode display, and playback overlay.
class VideoPreviewSection extends StatelessWidget {
  final EditorViewModel viewModel;

  const VideoPreviewSection({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final activeClip = viewModel.currentActiveClipAtPlayhead;
    final activeText = viewModel.activeTextOverlay;
    final targetRatio = viewModel.aspectRatio.ratio ?? (9 / 16);

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
                color: Colors.black,
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
                  // 1. Simulated Video Canvas Frame
                  if (activeClip != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
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
                              child: Text(
                                activeClip.title,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Text(
                        'No media on timeline',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),

                  // 2. Active Text / Subtitle Overlay
                  if (activeText != null)
                    Align(
                      alignment: FractionalOffset(activeText.position.dx, activeText.position.dy),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          border: Border.all(color: activeText.textColor.withOpacity(0.5)),
                        ),
                        child: Text(
                          activeText.text,
                          style: TextStyle(
                            fontSize: activeText.fontSize,
                            fontWeight: FontWeight.w900,
                            color: activeText.textColor,
                            shadows: const [
                              Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 3. Tap to Play / Pause Gesture Overlay
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

                  // 4. Top-Left: Aspect Ratio Badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
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
                  ),

                  // 5. Bottom-Center: Live Timecode Pill
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

                  // 6. Top-Right: Fullscreen Toggle
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen_rounded, size: 20, color: Colors.white70),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fullscreen preview mode'),
                            duration: Duration(milliseconds: 800),
                          ),
                        );
                      },
                      tooltip: 'Fullscreen',
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
}
