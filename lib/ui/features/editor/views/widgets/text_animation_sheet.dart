import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Modal bottom sheet for browsing, previewing, and customizing dynamic text animations
/// including entrance/exit effects (Fade, Zoom, Pop, Slide) and kinetic text styles.
class TextAnimationSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const TextAnimationSheet({
    super.key,
    required this.viewModel,
  });

  static Future<void> show(BuildContext context, EditorViewModel viewModel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TextAnimationSheet(viewModel: viewModel),
    );
  }

  @override
  State<TextAnimationSheet> createState() => _TextAnimationSheetState();
}

class _TextAnimationSheetState extends State<TextAnimationSheet> with SingleTickerProviderStateMixin {
  late AnimationController _previewController;
  late TextAnimationType _currentAnimation;
  Color? _highlightColor;
  double _animationSpeed = 1.0;
  int _selectedCategoryIndex = 0; // 0: All, 1: Entrance/Exit, 2: Kinetic & Creative

  final List<String> _categories = const ['All Effects', 'Entrance & Exit', 'Kinetic & Viral'];

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Default to selected text overlay or first text overlay
    final text = widget.viewModel.selectedTextOverlay ??
        (widget.viewModel.textOverlays.isNotEmpty ? widget.viewModel.textOverlays.first : null);

    _currentAnimation = text?.animationType ?? TextAnimationType.fade;
    _highlightColor = text?.highlightColor ?? const Color(0xFFFFEB3B);
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  TextOverlay? get _targetText {
    final vm = widget.viewModel;
    if (vm.selectedTextOverlay != null) return vm.selectedTextOverlay;
    if (vm.textOverlays.isNotEmpty) return vm.textOverlays.first;
    return null;
  }

  List<TextAnimationType> get _filteredAnimations {
    switch (_selectedCategoryIndex) {
      case 1: // Entrance & Exit
        return [
          TextAnimationType.fade,
          TextAnimationType.zoom,
          TextAnimationType.pop,
          TextAnimationType.slideUp,
          TextAnimationType.slideDown,
          TextAnimationType.fadeSlide,
        ];
      case 2: // Kinetic & Viral
        return [
          TextAnimationType.karaoke,
          TextAnimationType.typewriter,
          TextAnimationType.glowPulse,
          TextAnimationType.none,
        ];
      default:
        return TextAnimationType.values;
    }
  }

  void _applyAnimation(TextAnimationType type) {
    setState(() {
      _currentAnimation = type;
    });

    final target = _targetText;
    if (target != null) {
      widget.viewModel.updateTextAnimation(
        target.id,
        type,
        highlightColor: _highlightColor,
      );
    } else {
      // Auto-create a default text layer if none exists
      final playhead = widget.viewModel.playheadPosition;
      widget.viewModel.addTextOverlay(
        TextOverlay(
          id: 'text_${DateTime.now().millisecondsSinceEpoch}',
          text: 'Animated Title',
          startTime: Duration(milliseconds: (playhead * 1000).round()),
          duration: const Duration(seconds: 4),
          color: Colors.white,
          fontSize: 26.0,
          animationType: type,
          highlightColor: _highlightColor,
        ),
      );
    }
  }

  void _applyToAllSubtitles() {
    final target = _targetText;
    if (target == null) return;

    for (final text in widget.viewModel.textOverlays) {
      widget.viewModel.updateTextAnimation(
        text.id,
        _currentAnimation,
        highlightColor: _highlightColor,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ Applied ${_currentAnimation.displayName} to all ${widget.viewModel.textOverlays.length} text overlays!'),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetText;
    final sampleText = target?.text.isNotEmpty == true ? target!.text : 'Sample Title Animation';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
        border: Border(top: BorderSide(color: AppColors.divider, width: 1.0)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Drag Handle & Title
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 4),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.animation_rounded, size: 20, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text(
                            'Text Animation',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: AppColors.divider, height: 1),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2. Real-Time Animated Preview Box
                    Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.0),
                      ),
                      alignment: Alignment.center,
                      child: AnimatedBuilder(
                        animation: _previewController,
                        builder: (context, child) {
                          return _buildAnimatedPreviewText(sampleText, target);
                        },
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 3. Category Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_categories.length, (idx) {
                          final isSelected = _selectedCategoryIndex == idx;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(_categories[idx]),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedCategoryIndex = idx),
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surfaceLight,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? Colors.black : Colors.white70,
                              ),
                              side: BorderSide(
                                color: isSelected ? AppColors.primary : AppColors.divider,
                                width: 0.8,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 4. Animation Selection Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.6,
                      ),
                      itemCount: _filteredAnimations.length,
                      itemBuilder: (context, idx) {
                        final anim = _filteredAnimations[idx];
                        final isSelected = _currentAnimation == anim;

                        return InkWell(
                          onTap: () => _applyAnimation(anim),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.15)
                                  : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.divider,
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.surfaceHighlight,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    anim.icon,
                                    size: 18,
                                    color: isSelected ? Colors.black : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        anim.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          color: isSelected ? AppColors.primary : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _getAnimationTag(anim),
                                        style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // 5. Speed / Pacing Slider
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Pacing Speed (${_animationSpeed.toStringAsFixed(1)}x)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor: AppColors.surfaceHighlight,
                              thumbColor: AppColors.primary,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            ),
                            child: Slider(
                              value: _animationSpeed,
                              min: 0.5,
                              max: 2.0,
                              divisions: 6,
                              onChanged: (val) {
                                setState(() {
                                  _animationSpeed = val;
                                  _previewController.duration = Duration(
                                    milliseconds: (2000 / val).round(),
                                  );
                                });
                                final t = _targetText;
                                if (t != null) {
                                  widget.viewModel.updateTextSpeed(t.id, val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 6. Highlight Palette for Karaoke / Glow Pulse
                    if (_currentAnimation == TextAnimationType.karaoke || _currentAnimation == TextAnimationType.glowPulse) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Highlight Glow Color:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Color(0xFFFFEB3B), // Yellow
                          const Color(0xFF00E676), // Neon Green
                          const Color(0xFFFF1744), // Crimson
                          const Color(0xFF00E5FF), // Cyan
                          const Color(0xFFE040FB), // Magenta
                          const Color(0xFFFF9100), // Orange
                        ].map((c) {
                          final isPicked = _highlightColor == c;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _highlightColor = c);
                              final t = _targetText;
                              if (t != null) {
                                widget.viewModel.updateTextAnimation(t.id, _currentAnimation, highlightColor: c);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isPicked ? Colors.white : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // 7. Action Buttons
                    Row(
                      children: [
                        if (widget.viewModel.textOverlays.length > 1) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary),
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _applyToAllSubtitles,
                              child: const Text('Apply to All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedPreviewText(String sampleText, TextOverlay? target) {
    final t = _previewController.value; // 0.0 -> 1.0 (looping)
    double scale = 1.0;
    double slideY = 0.0;
    double opacity = 1.0;
    String displayText = sampleText;

    switch (_currentAnimation) {
      case TextAnimationType.fade:
        // Sine wave fade in and out
        opacity = 0.15 + 0.85 * math.sin(t * math.pi);
        break;
      case TextAnimationType.zoom:
        // Smooth zoom in with bounce ease
        scale = 0.6 + 0.5 * math.sin(t * math.pi);
        opacity = (math.sin(t * math.pi) * 1.5).clamp(0.0, 1.0);
        break;
      case TextAnimationType.pop:
        scale = 0.8 + 0.3 * math.sin(t * math.pi * 2).abs();
        break;
      case TextAnimationType.slideUp:
        slideY = math.cos(t * math.pi * 2) * 16.0;
        opacity = (math.sin(t * math.pi) * 1.5).clamp(0.0, 1.0);
        break;
      case TextAnimationType.slideDown:
        slideY = -math.cos(t * math.pi * 2) * 16.0;
        opacity = (math.sin(t * math.pi) * 1.5).clamp(0.0, 1.0);
        break;
      case TextAnimationType.fadeSlide:
        slideY = (0.5 - (t % 0.5)) * 30.0;
        opacity = ((0.5 - (0.5 - (t % 0.5)).abs()) * 4).clamp(0.0, 1.0);
        break;
      case TextAnimationType.typewriter:
        final visibleLen = (t * sampleText.length).ceil().clamp(1, sampleText.length);
        displayText = sampleText.substring(0, visibleLen);
        break;
      case TextAnimationType.glowPulse:
        scale = 1.0 + 0.06 * math.sin(t * math.pi * 4);
        break;
      case TextAnimationType.karaoke:
      case TextAnimationType.none:
        break;
    }

    final textColor = target?.color ?? Colors.white;
    final fontFamily = target?.fontFamily;

    return Transform.translate(
      offset: Offset(0, slideY),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _currentAnimation == TextAnimationType.glowPulse
                  ? (_highlightColor ?? AppColors.primary).withOpacity(0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: _currentAnimation == TextAnimationType.glowPulse
                  ? Border.all(color: _highlightColor ?? AppColors.primary, width: 1.2)
                  : null,
            ),
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontFamily: fontFamily,
                fontWeight: FontWeight.bold,
                color: _currentAnimation == TextAnimationType.karaoke
                    ? (_highlightColor ?? const Color(0xFFFFEB3B))
                    : textColor,
                shadows: [
                  Shadow(
                    color: _currentAnimation == TextAnimationType.glowPulse
                        ? (_highlightColor ?? AppColors.primary).withOpacity(0.8)
                        : Colors.black87,
                    blurRadius: _currentAnimation == TextAnimationType.glowPulse ? 14 : 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getAnimationTag(TextAnimationType anim) {
    switch (anim) {
      case TextAnimationType.none:
        return 'Fixed Position';
      case TextAnimationType.fade:
        return 'Smooth Entrance & Exit';
      case TextAnimationType.zoom:
        return 'Dynamic Scale In/Out';
      case TextAnimationType.pop:
        return 'Playful Bouncy Pop';
      case TextAnimationType.slideUp:
        return 'Upward Motion';
      case TextAnimationType.slideDown:
        return 'Downward Motion';
      case TextAnimationType.fadeSlide:
        return 'Angle Slide & Fade';
      case TextAnimationType.typewriter:
        return 'Letter-by-Letter';
      case TextAnimationType.karaoke:
        return 'Beat-Synced Highlight';
      case TextAnimationType.glowPulse:
        return 'Radiant Pulsing Aura';
    }
  }
}
