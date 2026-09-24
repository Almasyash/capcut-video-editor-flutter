import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/chroma_key_helper.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Modal bottom sheet for controlling secondary Picture-in-Picture (PIP) Overlays:
/// - Chroma Key (Green / Blue Screen removal, Similarity, Smoothness, Spill)
/// - Blending Modes (Screen, Multiply, Overlay, Color Dodge, etc.)
/// - Opacity & Spatial Presets
/// - Shape Masking (Circle, Rectangle, Star, Heart)
class PipOverlaySheet extends StatefulWidget {
  final EditorViewModel viewModel;
  final int initialTabIndex;

  const PipOverlaySheet({
    super.key,
    required this.viewModel,
    this.initialTabIndex = 0,
  });

  static Future<void> show(
    BuildContext context,
    EditorViewModel viewModel, {
    int initialTab = 0,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PipOverlaySheet(
        viewModel: viewModel,
        initialTabIndex: initialTab,
      ),
    );
  }

  @override
  State<PipOverlaySheet> createState() => _PipOverlaySheetState();
}

class _PipOverlaySheetState extends State<PipOverlaySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<(BlendMode, String, String)> _supportedBlendModes = [
    (BlendMode.srcOver, 'Normal', 'Standard opacity compositing'),
    (BlendMode.screen, 'Screen', 'Lightens base; removes black backgrounds'),
    (BlendMode.multiply, 'Multiply', 'Darkens base; removes white backgrounds'),
    (BlendMode.overlay, 'Overlay', 'Multiplies darks and screens highlights'),
    (BlendMode.lighten, 'Lighten', 'Selects lightest pixel of each channel'),
    (BlendMode.darken, 'Darken', 'Selects darkest pixel of each channel'),
    (BlendMode.colorDodge, 'Color Dodge', 'Vibrant neon brightening'),
    (BlendMode.softLight, 'Soft Light', 'Gentle contrast boost'),
    (BlendMode.hardLight, 'Hard Light', 'Intense punchy contrast'),
    (BlendMode.difference, 'Difference', 'Inverts colors based on base layer'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final overlay = widget.viewModel.selectedOverlay;

        return Container(
          height: 440,
          decoration: const BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 4),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Sheet Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          overlay != null ? 'PIP: ${overlay.title}' : 'Picture-in-Picture Settings',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Done',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Tab Navigation Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.secondary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.textMuted,
                    labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(icon: Icon(Icons.auto_fix_high_rounded, size: 16), text: 'Chroma Key'),
                      Tab(icon: Icon(Icons.layers_rounded, size: 16), text: 'Blend'),
                      Tab(icon: Icon(Icons.opacity_rounded, size: 16), text: 'Opacity'),
                      Tab(icon: Icon(Icons.crop_free_rounded, size: 16), text: 'Mask'),
                    ],
                  ),
                ),

                // Tab Content
                Expanded(
                  child: overlay == null
                      ? const Center(
                          child: Text(
                            'Select an overlay layer on the timeline',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildChromaKeyTab(overlay),
                            _buildBlendTab(overlay),
                            _buildOpacityTab(overlay),
                            _buildMaskTab(overlay),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 1: CHROMA KEY ---
  Widget _buildChromaKeyTab(OverlayClip overlay) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 8),
      children: [
        // Chroma Key Toggle Switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(
              color: overlay.enableChromaKey ? AppColors.secondary : Colors.white10,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                color: overlay.enableChromaKey ? AppColors.secondary : AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chroma Key (Green/Blue Screen)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Cut out background color automatically', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Switch(
                value: overlay.enableChromaKey,
                activeColor: AppColors.secondary,
                onChanged: (val) {
                  widget.viewModel.updateSelectedOverlayChromaKey(enable: val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (overlay.enableChromaKey) ...[
          // Color Presets
          const Text('Key Color Target', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ChromaKeyHelper.presets.map((preset) {
                final isSelected = overlay.chromaKeyColor.value == preset.color.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(Icons.circle, color: preset.color, size: 14),
                    label: Text(preset.name, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textSecondary)),
                    selected: isSelected,
                    selectedColor: AppColors.surfaceLight,
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      side: BorderSide(
                        color: isSelected ? preset.color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        widget.viewModel.updateSelectedOverlayChromaKey(color: preset.color);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Similarity Slider
          _buildSliderTile(
            title: 'Similarity',
            subtitle: 'How broad of the color range to make transparent',
            value: overlay.chromaSimilarity,
            displayValue: '${(overlay.chromaSimilarity * 100).round()}%',
            min: 0.05,
            max: 0.95,
            onChanged: (val) {
              widget.viewModel.updateSelectedOverlayChromaKey(similarity: val);
            },
          ),

          const SizedBox(height: 8),

          // Smoothness Slider
          _buildSliderTile(
            title: 'Smoothness',
            subtitle: 'Edge softness and feathering',
            value: overlay.chromaSmoothness,
            displayValue: '${(overlay.chromaSmoothness * 100).round()}%',
            min: 0.0,
            max: 0.50,
            onChanged: (val) {
              widget.viewModel.updateSelectedOverlayChromaKey(smoothness: val);
            },
          ),

          const SizedBox(height: 8),

          // Spill Reduction Slider
          _buildSliderTile(
            title: 'Spill Reduction',
            subtitle: 'Neutralize green/blue tint reflections on edges',
            value: overlay.chromaSpill,
            displayValue: '${(overlay.chromaSpill * 100).round()}%',
            min: 0.0,
            max: 0.70,
            onChanged: (val) {
              widget.viewModel.updateSelectedOverlayChromaKey(spill: val);
            },
          ),

          const SizedBox(height: 8),

          // Quick Reset Defaults Button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.secondary),
              label: const Text('Reset Chroma Defaults', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
              onPressed: () {
                widget.viewModel.updateSelectedOverlayChromaKey(
                  color: const Color(0xFF00FF00),
                  similarity: 0.40,
                  smoothness: 0.10,
                  spill: 0.15,
                );
              },
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: const Column(
              children: [
                Icon(Icons.video_library_rounded, size: 36, color: AppColors.textMuted),
                SizedBox(height: 8),
                Text(
                  'Green Screen & Blue Screen Removal',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'Switch Chroma Key ON above to extract green screen footage and composite it seamlessly over the primary video track.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // --- TAB 2: BLEND MODES ---
  Widget _buildBlendTab(OverlayClip overlay) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 8),
      itemCount: _supportedBlendModes.length,
      itemBuilder: (context, idx) {
        final (mode, name, desc) = _supportedBlendModes[idx];
        final isSelected = overlay.blendMode == mode;

        return InkWell(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          onTap: () {
            widget.viewModel.updateSelectedOverlayBlendMode(mode);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.symmetric(vertical: 2.5),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.secondary.withOpacity(0.15) : AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: Border.all(
                color: isSelected ? AppColors.secondary : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isSelected ? AppColors.secondary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppColors.secondary : Colors.white,
                        ),
                      ),
                      Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_rounded, size: 16, color: AppColors.secondary),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 3: OPACITY & TRANSFORM ---
  Widget _buildOpacityTab(OverlayClip overlay) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 8),
      children: [
        _buildSliderTile(
          title: 'Layer Opacity',
          subtitle: 'Transparency level of this PIP layer',
          value: overlay.opacity,
          displayValue: '${(overlay.opacity * 100).round()}%',
          min: 0.0,
          max: 1.0,
          onChanged: (val) {
            widget.viewModel.updateSelectedOverlayOpacity(val);
          },
        ),

        const SizedBox(height: 16),

        const Text('Spatial Layout Presets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildLayoutPresetButton(
              label: 'Corner PIP',
              icon: Icons.picture_in_picture_rounded,
              onTap: () {
                final idx = widget.viewModel.selectedOverlayIndex;
                if (idx != null) {
                  widget.viewModel.updateOverlayPosition(idx, const Offset(0.75, 0.20));
                  widget.viewModel.updateOverlayScale(idx, 0.40);
                }
              },
            ),
            _buildLayoutPresetButton(
              label: 'Center PIP',
              icon: Icons.filter_center_focus_rounded,
              onTap: () {
                final idx = widget.viewModel.selectedOverlayIndex;
                if (idx != null) {
                  widget.viewModel.updateOverlayPosition(idx, const Offset(0.50, 0.50));
                  widget.viewModel.updateOverlayScale(idx, 0.55);
                }
              },
            ),
            _buildLayoutPresetButton(
              label: 'Full Screen',
              icon: Icons.fullscreen_rounded,
              onTap: () {
                final idx = widget.viewModel.selectedOverlayIndex;
                if (idx != null) {
                  widget.viewModel.updateOverlayPosition(idx, const Offset(0.50, 0.50));
                  widget.viewModel.updateOverlayScale(idx, 1.0);
                }
              },
            ),
            _buildLayoutPresetButton(
              label: 'Bottom-Right',
              icon: Icons.south_east_rounded,
              onTap: () {
                final idx = widget.viewModel.selectedOverlayIndex;
                if (idx != null) {
                  widget.viewModel.updateOverlayPosition(idx, const Offset(0.75, 0.80));
                  widget.viewModel.updateOverlayScale(idx, 0.40);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // --- TAB 4: MASKING ---
  Widget _buildMaskTab(OverlayClip overlay) {
    const masks = [
      (MaskType.none, 'None', Icons.block_rounded),
      (MaskType.circle, 'Circle', Icons.circle_outlined),
      (MaskType.rectangle, 'Rectangle', Icons.crop_square_rounded),
      (MaskType.star, 'Star', Icons.star_border_rounded),
      (MaskType.heart, 'Heart', Icons.favorite_border_rounded),
    ];

    final currentType = overlay.mask?.type ?? MaskType.none;
    final isInverted = overlay.mask?.inverted ?? false;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 8),
      children: [
        const Text('Shape Mask', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: masks.map((m) {
            final (type, label, icon) = m;
            final isSelected = currentType == type;

            return ChoiceChip(
              avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.textMuted),
              label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textSecondary)),
              selected: isSelected,
              selectedColor: AppColors.secondary,
              backgroundColor: AppColors.surface,
              onSelected: (selected) {
                if (selected) {
                  if (type == MaskType.none) {
                    widget.viewModel.updateSelectedOverlayMask(null);
                  } else {
                    widget.viewModel.updateSelectedOverlayMask(
                      VideoMask(
                        type: type,
                        size: 1.0,
                        feather: 5.0,
                        inverted: isInverted,
                      ),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),

        if (currentType != MaskType.none) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Invert Mask', style: TextStyle(fontSize: 13, color: Colors.white)),
            subtitle: const Text('Punch hole or inverse cutout', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            value: isInverted,
            activeColor: AppColors.secondary,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              if (overlay.mask != null) {
                widget.viewModel.updateSelectedOverlayMask(
                  overlay.mask!.copyWith(inverted: val),
                );
              }
            },
          ),
        ],
      ],
    );
  }

  // --- REUSABLE SLIDER TILE ---
  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required String displayValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              Text(displayValue, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.secondary)),
            ],
          ),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.secondary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutPresetButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
