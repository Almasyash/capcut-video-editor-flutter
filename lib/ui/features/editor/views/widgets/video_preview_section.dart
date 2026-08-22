import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Top Video Preview Screen containing the live video canvas, aspect-ratio viewport,
/// color grading LUT filters, adjustments, Picture-in-Picture (PIP) layers,
/// active stickers, subtitles, and playback overlay.
class VideoPreviewSection extends StatelessWidget {
  final EditorViewModel viewModel;

  const VideoPreviewSection({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final activeClip = viewModel.currentActiveClipAtPlayhead;
    final activeOverlays = viewModel.activeOverlayClipsAtPlayhead;
    final activeStickers = viewModel.activeStickersAtPlayhead;
    final activeText = viewModel.activeTextOverlay;
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
                    if (activeClip != null)
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

                    // 5. Active Text / Subtitle Overlay
                    if (activeText != null)
                      Align(
                        alignment: FractionalOffset(activeText.position.dx, activeText.position.dy),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            border: Border.all(color: activeText.color.withOpacity(0.5)),
                          ),
                          child: Text(
                            activeText.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: activeText.fontSize,
                              fontWeight: FontWeight.w900,
                              color: activeText.color,
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1)),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 6. Tap to Play / Pause Gesture Overlay
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainVideoCanvas(dynamic activeClip, ColorFilter? filter, ColorFilter? adjustments) {
    Widget videoContent = Opacity(
      opacity: activeClip.opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(activeClip.rotationDegrees * math.pi / 180)
          ..scale(
            activeClip.flipHorizontal ? -1.0 : 1.0,
            activeClip.flipVertical ? -1.0 : 1.0,
          ),
        child: AnimatedContainer(
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
                  child: Row(
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
                ),
              ],
            ),
          ),
        ),
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
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2)),
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
                    color: Colors.black.withOpacity(0.6),
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
