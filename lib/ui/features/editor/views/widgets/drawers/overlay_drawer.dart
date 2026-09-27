import 'dart:io';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class OverlayDrawer extends StatefulWidget {
  final EditorViewModel viewModel;
  final bool isDesktop;

  const OverlayDrawer({
    super.key,
    required this.viewModel,
    this.isDesktop = false,
  });

  @override
  State<OverlayDrawer> createState() => _OverlayDrawerState();
}

class _OverlayDrawerState extends State<OverlayDrawer> {
  double? _dragStartOpacity;
  bool _isPickingMedia = false;

  Future<void> _pickAndAddOverlay() {
    return _pickMedia();
  }

  Future<void> _pickMedia() async {
    if (_isPickingMedia) return;
    setState(() => _isPickingMedia = true);
    try {
      final asset = await DeviceMediaService.pickMediaAsset(type: 'media');
      if (asset != null && mounted) {
        widget.viewModel.addOverlayFromMediaAsset(asset);
      }
    } catch (e) {
      debugPrint('[OverlayDrawer] Error picking media: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingMedia = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final selectedOverlay = widget.viewModel.selectedOverlay;

        return Container(
          height: widget.isDesktop ? double.infinity : 220,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF141418),
                  border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.picture_in_picture_alt_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          selectedOverlay != null ? 'Edit Overlay: ${selectedOverlay.title}' : 'PIP Overlay',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (selectedOverlay != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.viewModel.selectOverlay(null),
                            child: const Text('Back to List', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Done',
                          onPressed: widget.viewModel.closeDrawer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Body content
              Expanded(
                child: selectedOverlay != null
                    ? _buildSelectedOverlayControls(selectedOverlay)
                    : _buildOverlayListView(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedOverlayControls(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Opacity Slider
          Row(
            children: [
              const Icon(Icons.opacity_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Opacity', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${(overlay.opacity * 100).round()}%',
                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceLight,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: overlay.opacity,
              min: 0.0,
              max: 1.0,
              onChangeStart: (val) {
                _dragStartOpacity = overlay.opacity;
              },
              onChanged: (val) {
                widget.viewModel.updateOverlayOpacity(overlay.id, val, notify: true);
              },
              onChangeEnd: (val) {
                if (_dragStartOpacity != null) {
                  widget.viewModel.commitOverlayOpacity(overlay.id, oldOpacity: _dragStartOpacity!);
                  _dragStartOpacity = null;
                }
              },
            ),
          ),
          const SizedBox(height: 6),

          // Quick Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.flip_rounded,
                label: 'Flip H',
                isActive: overlay.flipHorizontal,
                onTap: () => widget.viewModel.toggleOverlayFlipHorizontal(overlay.id),
              ),
              _buildActionButton(
                icon: Icons.swap_vert_rounded,
                label: 'Flip V',
                isActive: overlay.flipVertical,
                onTap: () => widget.viewModel.toggleOverlayFlipVertical(overlay.id),
              ),
              _buildActionButton(
                icon: Icons.center_focus_strong_rounded,
                label: 'Center',
                isActive: false,
                onTap: () {
                  final idx = widget.viewModel.selectedOverlayIndex;
                  if (idx != null) {
                    final oldPos = overlay.position;
                    final oldScale = overlay.scale;
                    final oldRot = overlay.rotation;
                    widget.viewModel.updateOverlayTransform(overlay.id, position: const Offset(0.5, 0.5));
                    widget.viewModel.commitOverlayTransform(overlay.id, oldPosition: oldPos, oldScale: oldScale, oldRotation: oldRot);
                  }
                },
              ),
              _buildActionButton(
                icon: Icons.aspect_ratio_rounded,
                label: 'Reset',
                isActive: false,
                onTap: () {
                  final oldPos = overlay.position;
                  final oldScale = overlay.scale;
                  final oldRot = overlay.rotation;
                  widget.viewModel.updateOverlayTransform(
                    overlay.id,
                    position: const Offset(0.5, 0.5),
                    scale: 0.5,
                    rotation: 0.0,
                  );
                  widget.viewModel.commitOverlayTransform(overlay.id, oldPosition: oldPos, oldScale: oldScale, oldRotation: oldRot);
                },
              ),
              _buildActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                isActive: false,
                isDanger: true,
                onTap: () => widget.viewModel.deleteSelectedOverlay(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    bool isDanger = false,
    required VoidCallback onTap,
  }) {
    final color = isDanger
        ? Colors.redAccent
        : (isActive ? AppColors.primary : AppColors.textPrimary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.divider,
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayListView() {
    final overlays = widget.viewModel.overlayClips;

    return Column(
      children: [
        // Add overlay prominent button
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDimensions.md, 10, AppDimensions.md, 6),
          child: SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _isPickingMedia ? null : _pickAndAddOverlay,
              icon: _isPickingMedia
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: Text(
                _isPickingMedia ? 'Selecting Media...' : '+ Add Overlay Media',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ),

        // List of current overlays
        Expanded(
          child: overlays.isEmpty
              ? const Center(
                  child: Text(
                    'No overlays added yet.\nTap above to import a photo or video overlay.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: overlays.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = overlays[index];
                    final isSelected = widget.viewModel.selectedOverlayIndex == index;

                    return InkWell(
                      onTap: () => widget.viewModel.selectOverlay(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.divider,
                            width: isSelected ? 1.5 : 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: double.infinity,
                                  color: const Color(0xFF1E1E24),
                                  child: _buildItemThumbnail(item),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${item.startTimeInSeconds.toStringAsFixed(1)}s - ${item.endTimeInSeconds.toStringAsFixed(1)}s',
                              style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildItemThumbnail(OverlayClip item) {
    final thumbPath = item.thumbnailPath ?? (item.isPhoto ? item.localPath : null);
    if (thumbPath != null && thumbPath.isNotEmpty && File(thumbPath).existsSync()) {
      return Image.file(
        File(thumbPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(item),
      );
    }
    return _buildFallbackIcon(item);
  }

  Widget _buildFallbackIcon(OverlayClip item) {
    return Center(
      child: Icon(
        item.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
        size: 24,
        color: AppColors.primary.withValues(alpha: 0.7),
      ),
    );
  }
}
