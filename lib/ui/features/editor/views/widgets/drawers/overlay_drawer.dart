import 'dart:io';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/core/services/pip_ai_provider.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

enum OverlayDrawerTab {
  basic,
  speed,
  audio,
  animation,
  crop,
  filters,
  adjust,
  blend,
  chroma,
  cornerPin,
  decorators,
  split,
  aiTools,
}

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
  OverlayDrawerTab _currentTab = OverlayDrawerTab.basic;
  double? _dragStartOpacity;
  bool _isPickingMedia = false;
  bool _isProcessingAi = false;

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
          height: widget.isDesktop ? double.infinity : 280,
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

              // Category tab bar when an overlay is selected
              if (selectedOverlay != null) _buildCategoryTabBar(),

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

  Widget _buildCategoryTabBar() {
    final tabs = [
      (OverlayDrawerTab.basic, Icons.tune_rounded, 'Basic'),
      (OverlayDrawerTab.speed, Icons.speed_rounded, 'Speed'),
      (OverlayDrawerTab.audio, Icons.volume_up_rounded, 'Audio'),
      (OverlayDrawerTab.animation, Icons.animation_rounded, 'Anim'),
      (OverlayDrawerTab.crop, Icons.crop_rounded, 'Crop'),
      (OverlayDrawerTab.filters, Icons.filter_vintage_rounded, 'Filters'),
      (OverlayDrawerTab.adjust, Icons.color_lens_rounded, 'Adjust'),
      (OverlayDrawerTab.blend, Icons.layers_rounded, 'Blend'),
      (OverlayDrawerTab.chroma, Icons.theater_comedy_rounded, 'Chroma'),
      (OverlayDrawerTab.cornerPin, Icons.crop_rotate_rounded, 'Corner Pin'),
      (OverlayDrawerTab.decorators, Icons.auto_awesome_rounded, 'Effects'),
      (OverlayDrawerTab.split, Icons.view_quilt_rounded, 'Split'),
      (OverlayDrawerTab.aiTools, Icons.psychology_rounded, 'AI Tools'),
    ];

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF18181E),
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: tabs.length,
        itemBuilder: (context, idx) {
          final tab = tabs[idx];
          final isSelected = _currentTab == tab.$1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => setState(() => _currentTab = tab.$1),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.$2, size: 14, color: isSelected ? AppColors.primary : AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      tab.$3,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedOverlayControls(OverlayClip overlay) {
    switch (_currentTab) {
      case OverlayDrawerTab.basic:
        return _buildBasicTab(overlay);
      case OverlayDrawerTab.speed:
        return _buildSpeedTab(overlay);
      case OverlayDrawerTab.audio:
        return _buildAudioTab(overlay);
      case OverlayDrawerTab.animation:
        return _buildAnimationTab(overlay);
      case OverlayDrawerTab.crop:
        return _buildCropTab(overlay);
      case OverlayDrawerTab.filters:
        return _buildFiltersTab(overlay);
      case OverlayDrawerTab.adjust:
        return _buildAdjustTab(overlay);
      case OverlayDrawerTab.blend:
        return _buildBlendTab(overlay);
      case OverlayDrawerTab.chroma:
        return _buildChromaTab(overlay);
      case OverlayDrawerTab.cornerPin:
        return _buildCornerPinTab(overlay);
      case OverlayDrawerTab.decorators:
        return _buildDecoratorsTab(overlay);
      case OverlayDrawerTab.split:
        return _buildSplitTab(overlay);
      case OverlayDrawerTab.aiTools:
        return _buildAiToolsTab(overlay);
    }
  }

  // 1. Basic Transform Tab
  Widget _buildBasicTab(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            ),
            child: Slider(
              value: overlay.opacity,
              min: 0.0,
              max: 1.0,
              onChangeStart: (val) => _dragStartOpacity = overlay.opacity,
              onChanged: (val) => widget.viewModel.updateOverlayOpacity(overlay.id, val, notify: true),
              onChangeEnd: (val) {
                if (_dragStartOpacity != null) {
                  widget.viewModel.commitOverlayOpacity(overlay.id, oldOpacity: _dragStartOpacity!);
                  _dragStartOpacity = null;
                }
              },
            ),
          ),
          const SizedBox(height: 6),
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
                  final oldPos = overlay.position;
                  widget.viewModel.updateOverlayTransform(overlay.id, position: const Offset(0.5, 0.5));
                  widget.viewModel.commitOverlayTransform(overlay.id, oldPosition: oldPos, oldScale: overlay.scale, oldRotation: overlay.rotation);
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
                  widget.viewModel.updateOverlayTransform(overlay.id, position: const Offset(0.5, 0.5), scale: 0.5, rotation: 0.0);
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

  // 2. Speed Tab
  Widget _buildSpeedTab(OverlayClip overlay) {
    final speedPresets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Playback Speed', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${overlay.speed.toStringAsFixed(2)}x',
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
            ),
            child: Slider(
              value: overlay.speed.clamp(0.25, 4.0),
              min: 0.25,
              max: 4.0,
              divisions: 15,
              onChanged: (val) => widget.viewModel.updateOverlaySpeed(overlay.id, val),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: speedPresets.map((s) {
              final isCur = (overlay.speed - s).abs() < 0.05;
              return ChoiceChip(
                label: Text('${s}x', style: TextStyle(fontSize: 11, color: isCur ? Colors.black : Colors.white)),
                selected: isCur,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => widget.viewModel.updateOverlaySpeed(overlay.id, s),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 3. Audio Tab
  Widget _buildAudioTab(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(overlay.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Volume & Audio', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                overlay.isMuted ? 'Muted' : '${(overlay.volume * 100).round()}%',
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
            ),
            child: Slider(
              value: overlay.isMuted ? 0.0 : overlay.volume.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              onChanged: (val) => widget.viewModel.updateOverlayAudio(overlay.id, volume: val, isMuted: val == 0.0),
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: overlay.isMuted ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceLight,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => widget.viewModel.updateOverlayAudio(overlay.id, isMuted: !overlay.isMuted),
                icon: Icon(overlay.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14, color: overlay.isMuted ? AppColors.primary : Colors.white),
                label: Text(overlay.isMuted ? 'Unmute' : 'Mute', style: TextStyle(fontSize: 11, color: overlay.isMuted ? AppColors.primary : Colors.white)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF242430),
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => widget.viewModel.extractAudioFromOverlay(overlay.id),
                icon: const Icon(Icons.music_note_rounded, size: 14),
                label: const Text('Extract to Timeline', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4. Animation Tab
  Widget _buildAnimationTab(OverlayClip overlay) {
    final inAnims = ['none', 'fadeIn', 'slideRight', 'slideLeft', 'slideUp', 'slideDown', 'zoomIn', 'zoomOut', 'rotateIn', 'bounce'];
    final overallAnims = ['none', 'pulse', 'float', 'spin', 'flicker', 'shake'];
    final outAnims = ['none', 'fadeOut', 'slideRight', 'slideLeft', 'slideUp', 'slideDown', 'zoomIn', 'zoomOut'];

    final curIn = overlay.inAnimation?.type ?? 'none';
    final curOverall = overlay.overallAnimation?.type ?? 'none';
    final curOut = overlay.outAnimation?.type ?? 'none';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('In-Animation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: inAnims.map((anim) {
              final sel = curIn == anim;
              return ChoiceChip(
                label: Text(anim, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  widget.viewModel.updateOverlayAnimation(
                    overlay.id,
                    inAnimation: anim == 'none' ? null : PipAnimation(type: anim, durationSec: 0.5),
                    clearInAnim: anim == 'none',
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text('Overall Animation (Looping)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: overallAnims.map((anim) {
              final sel = curOverall == anim;
              return ChoiceChip(
                label: Text(anim, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  widget.viewModel.updateOverlayAnimation(
                    overlay.id,
                    overallAnimation: anim == 'none' ? null : PipAnimation(type: anim),
                    clearOverallAnim: anim == 'none',
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text('Out-Animation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: outAnims.map((anim) {
              final sel = curOut == anim;
              return ChoiceChip(
                label: Text(anim, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  widget.viewModel.updateOverlayAnimation(
                    overlay.id,
                    outAnimation: anim == 'none' ? null : PipAnimation(type: anim, durationSec: 0.5),
                    clearOutAnim: anim == 'none',
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 5. Crop Tab
  Widget _buildCropTab(OverlayClip overlay) {
    final ratios = ['Free', '1:1', '16:9', '9:16', '4:3', '3:4'];
    final curRatio = overlay.cropAspectRatio ?? 'Free';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Aspect Ratio Preset', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.viewModel.updateOverlayCrop(overlay.id, cropRect: null, cropAspectRatio: 'Free'),
                child: const Text('Reset Crop', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: ratios.map((r) {
              final sel = curRatio == r;
              return ChoiceChip(
                label: Text(r, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  Rect? rect;
                  switch (r) {
                    case '1:1':
                      rect = const Rect.fromLTWH(0.125, 0.0, 0.75, 1.0);
                      break;
                    case '16:9':
                      rect = const Rect.fromLTWH(0.0, 0.22, 1.0, 0.56);
                      break;
                    case '9:16':
                      rect = const Rect.fromLTWH(0.22, 0.0, 0.56, 1.0);
                      break;
                    case '4:3':
                      rect = const Rect.fromLTWH(0.0, 0.125, 1.0, 0.75);
                      break;
                    case '3:4':
                      rect = const Rect.fromLTWH(0.125, 0.0, 0.75, 1.0);
                      break;
                    default:
                      rect = null;
                      break;
                  }
                  widget.viewModel.updateOverlayCrop(overlay.id, cropRect: rect, cropAspectRatio: r);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 6. Filters Tab
  Widget _buildFiltersTab(OverlayClip overlay) {
    final filters = [
      ('none', 'None'),
      ('vivid', 'Vivid'),
      ('sepia', 'Sepia'),
      ('grayscale', 'B&W'),
      ('vintage', 'Vintage'),
      ('cool', 'Cool'),
      ('warm', 'Warm'),
      ('cyberpunk', 'Cyber'),
      ('cinema', 'Cinema'),
    ];
    final curFilter = overlay.filterId ?? 'none';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filter Intensity', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const Spacer(),
              Text('${(overlay.filterIntensity * 100).round()}%', style: const TextStyle(fontSize: 11, color: AppColors.primary)),
            ],
          ),
          Slider(
            value: overlay.filterIntensity.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChanged: (val) => widget.viewModel.updateOverlayFilter(overlay.id, intensity: val),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: filters.map((f) {
              final sel = curFilter == f.$1;
              return ChoiceChip(
                label: Text(f.$2, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => widget.viewModel.updateOverlayFilter(overlay.id, filterId: f.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 7. Adjust Tab
  Widget _buildAdjustTab(OverlayClip overlay) {
    final adj = overlay.adjustments;

    Widget buildSlider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted))),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceLight,
                ),
                child: Slider(
                  value: val.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(width: 32, child: Text(val.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.white))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Color Adjustments', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.viewModel.updateOverlayAdjustments(overlay.id, const PipAdjustments()),
                child: const Text('Reset All', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
              ),
            ],
          ),
          buildSlider('Brightness', adj.brightness, -1.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(brightness: v))),
          buildSlider('Contrast', adj.contrast, -1.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(contrast: v))),
          buildSlider('Saturation', adj.saturation, -1.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(saturation: v))),
          buildSlider('Exposure', adj.exposure, -1.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(exposure: v))),
          buildSlider('Temp', adj.temperature, -1.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(temperature: v))),
          buildSlider('Vignette', adj.vignette, 0.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(vignette: v))),
          buildSlider('Sharpness', adj.sharpness, 0.0, 1.0, (v) => widget.viewModel.updateOverlayAdjustments(overlay.id, adj.copyWith(sharpness: v))),
        ],
      ),
    );
  }

  // 8. Blend Tab
  Widget _buildBlendTab(OverlayClip overlay) {
    final modes = [
      (BlendMode.srcOver, 'Normal'),
      (BlendMode.multiply, 'Multiply'),
      (BlendMode.screen, 'Screen'),
      (BlendMode.overlay, 'Overlay'),
      (BlendMode.darken, 'Darken'),
      (BlendMode.lighten, 'Lighten'),
      (BlendMode.colorDodge, 'Dodge'),
      (BlendMode.softLight, 'Soft Light'),
      (BlendMode.hardLight, 'Hard Light'),
      (BlendMode.difference, 'Difference'),
      (BlendMode.luminosity, 'Luma'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Blend Mode', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: modes.map((m) {
              final sel = overlay.blendMode == m.$1;
              return ChoiceChip(
                label: Text(m.$2, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => widget.viewModel.updateOverlayBlendMode(overlay.id, m.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 9. Chroma Key Tab
  Widget _buildChromaTab(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Enable Chroma Key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              Switch(
                value: overlay.enableChromaKey,
                activeColor: AppColors.primary,
                onChanged: (val) => widget.viewModel.updateOverlayChromaKey(overlay.id, enabled: val),
              ),
            ],
          ),
          if (overlay.enableChromaKey) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Key Color:', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                const SizedBox(width: 8),
                ...[const Color(0xFF00FF00), const Color(0xFF0000FF), Colors.black, Colors.white].map((c) {
                  final sel = overlay.chromaKeyColor.value == c.value;
                  return GestureDetector(
                    onTap: () => widget.viewModel.updateOverlayChromaKey(overlay.id, color: c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: sel ? AppColors.primary : Colors.white24, width: sel ? 2 : 1),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 70, child: Text('Similarity', style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
                Expanded(
                  child: Slider(
                    value: overlay.chromaSimilarity.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => widget.viewModel.updateOverlayChromaKey(overlay.id, similarity: v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 70, child: Text('Smoothness', style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
                Expanded(
                  child: Slider(
                    value: overlay.chromaSmoothness.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => widget.viewModel.updateOverlayChromaKey(overlay.id, smoothness: v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 10. Corner Pin Tab
  Widget _buildCornerPinTab(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('4-Point Corner Pin Perspective', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  widget.viewModel.updateOverlayCornerPin(
                    overlay.id,
                    topLeft: Offset.zero,
                    topRight: const Offset(1, 0),
                    bottomLeft: const Offset(0, 1),
                    bottomRight: const Offset(1, 1),
                  );
                },
                child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ActionChip(
                label: const Text('Left Tilt', style: TextStyle(fontSize: 10)),
                backgroundColor: AppColors.surfaceLight,
                onPressed: () {
                  widget.viewModel.updateOverlayCornerPin(
                    overlay.id,
                    topLeft: const Offset(0.0, 0.15),
                    topRight: const Offset(1.0, 0.0),
                    bottomLeft: const Offset(0.0, 0.85),
                    bottomRight: const Offset(1.0, 1.0),
                  );
                },
              ),
              ActionChip(
                label: const Text('Right Tilt', style: TextStyle(fontSize: 10)),
                backgroundColor: AppColors.surfaceLight,
                onPressed: () {
                  widget.viewModel.updateOverlayCornerPin(
                    overlay.id,
                    topLeft: const Offset(0.0, 0.0),
                    topRight: const Offset(1.0, 0.15),
                    bottomLeft: const Offset(0.0, 1.0),
                    bottomRight: const Offset(1.0, 0.85),
                  );
                },
              ),
              ActionChip(
                label: const Text('Top Squeeze', style: TextStyle(fontSize: 10)),
                backgroundColor: AppColors.surfaceLight,
                onPressed: () {
                  widget.viewModel.updateOverlayCornerPin(
                    overlay.id,
                    topLeft: const Offset(0.15, 0.0),
                    topRight: const Offset(0.85, 0.0),
                    bottomLeft: const Offset(0.0, 1.0),
                    bottomRight: const Offset(1.0, 1.0),
                  );
                },
              ),
              ActionChip(
                label: const Text('Bottom Squeeze', style: TextStyle(fontSize: 10)),
                backgroundColor: AppColors.surfaceLight,
                onPressed: () {
                  widget.viewModel.updateOverlayCornerPin(
                    overlay.id,
                    topLeft: const Offset(0.0, 0.0),
                    topRight: const Offset(1.0, 0.0),
                    bottomLeft: const Offset(0.15, 1.0),
                    bottomRight: const Offset(0.85, 1.0),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 11. Decorators Tab
  Widget _buildDecoratorsTab(OverlayClip overlay) {
    final outline = overlay.outline ?? const PipOutline();
    final shadow = overlay.shadow ?? const PipShadow();
    final glow = overlay.glow ?? const PipGlow();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Outline / Border', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              Switch(
                value: outline.enabled,
                activeColor: AppColors.primary,
                onChanged: (v) => widget.viewModel.updateOverlayEffects(overlay.id, outline: outline.copyWith(enabled: v)),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Drop Shadow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              Switch(
                value: shadow.enabled,
                activeColor: AppColors.primary,
                onChanged: (v) => widget.viewModel.updateOverlayEffects(overlay.id, shadow: shadow.copyWith(enabled: v)),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Neon Glow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              Switch(
                value: glow.enabled,
                activeColor: AppColors.primary,
                onChanged: (v) => widget.viewModel.updateOverlayEffects(overlay.id, glow: glow.copyWith(enabled: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 12. Split Screen Tab
  Widget _buildSplitTab(OverlayClip overlay) {
    final presets = [
      ('none', 'Full / Reset'),
      ('leftRight', 'Left / Right'),
      ('topBottom', 'Top / Bottom'),
      ('fourGrid', '4-Grid Split'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Split Screen Layouts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: presets.map((p) {
              final sel = overlay.splitScreenPreset == p.$1;
              return ChoiceChip(
                label: Text(p.$2, style: TextStyle(fontSize: 10, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => widget.viewModel.applySplitScreenPreset(overlay.id, p.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 13. AI Tools Tab
  Widget _buildAiToolsTab(OverlayClip overlay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Powered PIP Suite', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.closed_caption_rounded, color: AppColors.primary),
            title: const Text('Auto Subtitles / Captions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: const Text('Extract spoken audio into text overlays', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _isProcessingAi
                  ? null
                  : () async {
                      setState(() => _isProcessingAi = true);
                      await widget.viewModel.generateAutoCaptionsFromOverlay(overlay.id);
                      if (mounted) setState(() => _isProcessingAi = false);
                    },
              child: _isProcessingAi
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Generate', style: TextStyle(fontSize: 11)),
            ),
          ),
          const Divider(color: AppColors.divider, height: 12),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high_rounded, color: Colors.cyanAccent),
            title: const Text('Magic Background Remover', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text(
              DefaultPipAiProvider.isFeatureAvailable(PipAiFeature.backgroundRemoval) ? 'Ready to process' : 'Hardware capability detected',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.record_voice_over_rounded, color: Colors.amberAccent),
            title: const Text('Voice & Vocal Separation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text(
              DefaultPipAiProvider.isFeatureAvailable(PipAiFeature.voiceSeparation) ? 'Ready to process' : 'Hardware capability detected',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
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
    final isPhoto = item.isPhoto || item.isPhotoOverlay;
    final thumbPath = item.thumbnailPath ?? (isPhoto ? item.localPath : null);
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
    final isPhoto = item.isPhoto || item.isPhotoOverlay;
    return Center(
      child: Icon(
        isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
        size: 24,
        color: AppColors.primary.withValues(alpha: 0.7),
      ),
    );
  }
}
