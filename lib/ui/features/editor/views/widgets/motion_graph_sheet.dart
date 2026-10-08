import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/core/services/tts_service.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Professional Motion Graph and Easing Editor Bottom Sheet
/// Provides high-precision visual curve preview, keyframe time/value editing,
/// and deterministic easing mode selection (Linear, Ease In, Ease Out, Ease In Out, Hold, Cubic Bézier).
class MotionGraphSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const MotionGraphSheet({
    super.key,
    required this.viewModel,
  });

  static Future<void> show(BuildContext context, EditorViewModel viewModel) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MotionGraphSheet(viewModel: viewModel),
    );
  }

  @override
  State<MotionGraphSheet> createState() => _MotionGraphSheetState();
}

class _MotionGraphSheetState extends State<MotionGraphSheet> {
  AnimatableProperty _selectedProperty = AnimatableProperty.scale;

  @override
  void initState() {
    super.initState();
    // Default to the first property that has keyframes if available
    final tracks = _getActiveTrackGroup();
    if (tracks != null && tracks.tracks.isNotEmpty) {
      _selectedProperty = tracks.tracks.keys.first;
    }
  }

  KeyframeTrackGroup? _getActiveTrackGroup() {
    final vm = widget.viewModel;
    if (vm.selectedClip != null) {
      return vm.selectedClip?.effectiveKeyframeTracks;
    } else if (vm.selectedOverlay != null) {
      return vm.selectedOverlay?.effectiveKeyframeTracks;
    } else if (vm.selectedTextOverlay != null) {
      return vm.selectedTextOverlay?.effectiveKeyframeTracks;
    } else if (vm.selectedAudioTrack != null) {
      return vm.selectedAudioTrack?.effectiveKeyframeTracks;
    }
    return null;
  }

  double _getLayerDurationSec() {
    final vm = widget.viewModel;
    if (vm.selectedClip != null) {
      return vm.selectedClip?.durationInSeconds ?? 5.0;
    } else if (vm.selectedOverlay != null) {
      return vm.selectedOverlay?.durationInSeconds ?? 5.0;
    } else if (vm.selectedTextOverlay != null) {
      return vm.selectedTextOverlay?.durationInSeconds ?? 5.0;
    } else if (vm.selectedAudioTrack != null) {
      return vm.selectedAudioTrack?.durationInSeconds ?? 5.0;
    }
    return 5.0;
  }

  double _getLayerRelativePlayheadSec() {
    final vm = widget.viewModel;
    if (vm.selectedClip != null) {
      final start = vm.activeClipStartTimeAtPlayhead;
      return (vm.playheadPosition - start).clamp(0.0, _getLayerDurationSec());
    } else if (vm.selectedOverlay != null) {
      return (vm.playheadPosition - vm.selectedOverlay!.startTimeInSeconds).clamp(0.0, _getLayerDurationSec());
    } else if (vm.selectedTextOverlay != null) {
      return (vm.playheadPosition - vm.selectedTextOverlay!.startTimeInSeconds).clamp(0.0, _getLayerDurationSec());
    } else if (vm.selectedAudioTrack != null) {
      return (vm.playheadPosition - vm.selectedAudioTrack!.startTimeInSeconds).clamp(0.0, _getLayerDurationSec());
    }
    return 0.0;
  }

  List<AnimatableProperty> _getAvailableProperties() {
    final vm = widget.viewModel;
    if (vm.selectedAudioTrack != null) {
      return [AnimatableProperty.volume];
    } else if (vm.selectedTextOverlay != null) {
      return [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
      ];
    } else if (vm.selectedOverlay != null) {
      return [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
      ];
    } else {
      return [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
        AnimatableProperty.brightness,
        AnimatableProperty.contrast,
        AnimatableProperty.saturation,
        AnimatableProperty.exposure,
        AnimatableProperty.temperature,
        AnimatableProperty.vignette,
        AnimatableProperty.sharpness,
      ];
    }
  }

  MotionKeyframe? _getSelectedKeyframe(KeyframeTrack? track) {
    if (track == null || track.isEmpty) return null;
    final relTimeMs = (_getLayerRelativePlayheadSec() * 1000).round();
    return track.getKeyframeAt(relTimeMs, toleranceMs: 120);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final trackGroup = _getActiveTrackGroup();
        final track = trackGroup?.tracks[_selectedProperty] ??
            KeyframeTrack(property: _selectedProperty, defaultValue: _selectedProperty.defaultValue);
        final selectedKf = _getSelectedKeyframe(track);
        final layerDuration = math.max(0.1, _getLayerDurationSec());
        final relPlayheadSec = _getLayerRelativePlayheadSec();

        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: Color(0xFF141416),
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
            boxShadow: [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Drag Handle & Header
              _buildHeader(context),

              // 2. Property Selector Tabs
              _buildPropertySelector(trackGroup),

              const SizedBox(height: 8),

              // 3. Motion Graph Visualizer Canvas
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    child: Container(
                      color: const Color(0xFF0D0D0E),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          // Tap-to-seek relative to graph width
                          final box = context.findRenderObject() as RenderBox?;
                          final renderWidth = box?.size.width ?? 300.0;
                          final ratio = (details.localPosition.dx / renderWidth).clamp(0.0, 1.0);
                          final targetRelSec = ratio * layerDuration;
                          _seekToLayerRelativeTime(targetRelSec);
                        },
                        child: CustomPaint(
                          painter: _MotionGraphPainter(
                            track: track,
                            durationSec: layerDuration,
                            playheadSec: relPlayheadSec,
                            selectedKeyframe: selectedKf,
                            property: _selectedProperty,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 4. Easing Curve Selector Controls
              _buildEasingControls(selectedKf),

              const SizedBox(height: 8),

              // 5. Value Fine-Tuning & Keyframe Action Bar
              _buildValueAndActionControls(track, selectedKf),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Motion Graph & Easing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Reset Animation Button
              TextButton.icon(
                onPressed: () {
                  widget.viewModel.resetAnimationForSelectedLayer();
                  TtsService.announce('Reset animation');
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.white70),
                label: const Text('Reset', style: TextStyle(color: Colors.white70, fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPropertySelector(KeyframeTrackGroup? trackGroup) {
    final properties = _getAvailableProperties();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: properties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prop = properties[index];
          final isSelected = prop == _selectedProperty;
          final track = trackGroup?.tracks[prop];
          final count = track?.length ?? 0;

          return ChoiceChip(
            selected: isSelected,
            onSelected: (_) {
              setState(() {
                _selectedProperty = prop;
              });
              TtsService.announce('${prop.label} track');
            },
            backgroundColor: const Color(0xFF1E1E22),
            selectedColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              side: BorderSide(
                color: isSelected ? AppColors.primary : Colors.white12,
                width: 1,
              ),
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prop.label,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black26 : const Color(0xFFFFD600),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.black87,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEasingControls(MotionKeyframe? selectedKf) {
    final modes = [
      (InterpolationMode.linear, 'Linear', Icons.linear_scale_rounded),
      (InterpolationMode.easeInOut, 'Ease In-Out', Icons.waves_rounded),
      (InterpolationMode.easeIn, 'Ease In', Icons.trending_up_rounded),
      (InterpolationMode.easeOut, 'Ease Out', Icons.trending_flat_rounded),
      (InterpolationMode.hold, 'Hold', Icons.pause_rounded),
      (InterpolationMode.cubicBezier, 'Bézier', Icons.gesture_rounded),
    ];

    final currentMode = selectedKf?.easing.mode ?? InterpolationMode.easeInOut;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'EASING CURVE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (selectedKf != null)
                Text(
                  '${(selectedKf.timestampMs / 1000.0).toStringAsFixed(2)}s: ${selectedKf.value.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFFFFD600), fontSize: 11, fontWeight: FontWeight.bold),
                )
              else
                const Text(
                  'No keyframe selected',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: modes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final modeItem = modes[index];
                final isSelected = selectedKf != null && currentMode == modeItem.$1;

                return OutlinedButton.icon(
                  onPressed: selectedKf != null
                      ? () {
                          final newCurve = EasingCurve(mode: modeItem.$1);
                          widget.viewModel.updateKeyframeEasing(
                            _selectedProperty,
                            selectedKf.timestampMs,
                            newCurve,
                          );
                          TtsService.announce(modeItem.$2);
                        }
                      : null,
                  icon: Icon(modeItem.$3, size: 14, color: isSelected ? Colors.black : Colors.white70),
                  label: Text(
                    modeItem.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.black : Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isSelected ? const Color(0xFFFFD600) : const Color(0xFF1E1E22),
                    foregroundColor: isSelected ? Colors.black : Colors.white,
                    side: BorderSide(
                      color: isSelected ? const Color(0xFFFFD600) : Colors.white12,
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueAndActionControls(KeyframeTrack track, MotionKeyframe? selectedKf) {
    final hasKfAtPlayhead = widget.viewModel.hasKeyframeAtPlayhead;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          // Add / Remove Keyframe at Playhead Button
          OutlinedButton.icon(
            onPressed: () {
              if (hasKfAtPlayhead) {
                widget.viewModel.removeKeyframeAtPlayhead();
                TtsService.announce('Delete keyframe');
              } else {
                widget.viewModel.addKeyframeAtPlayhead();
                TtsService.announce('Add keyframe');
              }
            },
            icon: Icon(
              hasKfAtPlayhead ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
              size: 16,
              color: hasKfAtPlayhead ? Colors.redAccent : const Color(0xFFFFD600),
            ),
            label: Text(
              hasKfAtPlayhead ? 'Delete ◆' : 'Add ◆',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: hasKfAtPlayhead ? Colors.redAccent : const Color(0xFFFFD600),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: hasKfAtPlayhead ? Colors.redAccent.withOpacity(0.5) : const Color(0xFFFFD600).withOpacity(0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Value Fine Tuning Slider
          Expanded(
            child: selectedKf != null
                ? Row(
                    children: [
                      Text(
                        _selectedProperty.unit.isNotEmpty ? _selectedProperty.unit : 'val',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      Expanded(
                        child: Slider(
                          value: selectedKf.value.clamp(_selectedProperty.minValue, _selectedProperty.maxValue),
                          min: _selectedProperty.minValue,
                          max: _selectedProperty.maxValue,
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white12,
                          onChanged: (newVal) {
                            widget.viewModel.setKeyframePropertyValue(_selectedProperty, newVal);
                          },
                        ),
                      ),
                      Text(
                        selectedKf.value.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : const Center(
                    child: Text(
                      'Seek to keyframe to edit value',
                      style: TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _seekToLayerRelativeTime(double relSec) {
    final vm = widget.viewModel;
    double globalSec = relSec;
    if (vm.selectedClip != null) {
      globalSec = vm.activeClipStartTimeAtPlayhead + relSec;
    } else if (vm.selectedOverlay != null) {
      globalSec = vm.selectedOverlay!.startTimeInSeconds + relSec;
    } else if (vm.selectedTextOverlay != null) {
      globalSec = vm.selectedTextOverlay!.startTimeInSeconds + relSec;
    } else if (vm.selectedAudioTrack != null) {
      globalSec = vm.selectedAudioTrack!.startTimeInSeconds + relSec;
    }
    vm.seekTo(globalSec);
  }
}

/// CustomPainter rendering grid, continuous evaluated curve, keyframe diamonds, and playhead
class _MotionGraphPainter extends CustomPainter {
  final KeyframeTrack track;
  final double durationSec;
  final double playheadSec;
  final MotionKeyframe? selectedKeyframe;
  final AnimatableProperty property;

  _MotionGraphPainter({
    required this.track,
    required this.durationSec,
    required this.playheadSec,
    required this.selectedKeyframe,
    required this.property,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paintGrid = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    // 1. Draw Background Grid & Reference Lines
    const numHDivisions = 4;
    for (int i = 0; i <= numHDivisions; i++) {
      final y = size.height * (i / numHDivisions);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }
    const numVDivisions = 6;
    for (int i = 0; i <= numVDivisions; i++) {
      final x = size.width * (i / numVDivisions);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }

    // Determine value range for normalization
    double minVal = property.minValue;
    double maxVal = property.maxValue;

    if (track.isNotEmpty) {
      double tMin = track.keyframes.first.value;
      double tMax = track.keyframes.first.value;
      for (final k in track.keyframes) {
        if (k.value < tMin) tMin = k.value;
        if (k.value > tMax) tMax = k.value;
      }
      final margin = (tMax - tMin).abs() * 0.2;
      minVal = math.min(minVal, tMin - margin);
      maxVal = math.max(maxVal, tMax + margin);
    }

    if ((maxVal - minVal).abs() < 1e-4) {
      maxVal = minVal + 1.0;
    }

    double valueToY(double val) {
      final norm = ((val - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
      return size.height - (norm * (size.height - 24) + 12);
    }

    double timeToX(double tSec) {
      return ((tSec / durationSec).clamp(0.0, 1.0)) * size.width;
    }

    // 2. Draw Evaluated Motion Curve (100 sampled intervals for exact easing curvature)
    final curvePath = Path();
    const sampleCount = 100;
    for (int i = 0; i <= sampleCount; i++) {
      final t = (i / sampleCount) * durationSec;
      final val = track.isEmpty ? property.defaultValue : track.evaluate(t);
      final x = timeToX(t);
      final y = valueToY(val);
      if (i == 0) {
        curvePath.moveTo(x, y);
      } else {
        curvePath.lineTo(x, y);
      }
    }

    // Curve Glow and Main Stroke
    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.3)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, glowPaint);

    final curvePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, curvePaint);

    // 3. Draw Keyframe Diamonds on the curve
    for (final kf in track.keyframes) {
      final sec = kf.timestampMs / 1000.0;
      final kfX = timeToX(sec);
      final kfY = valueToY(kf.value);
      final isSelected = selectedKeyframe?.timestampMs == kf.timestampMs;

      canvas.save();
      canvas.translate(kfX, kfY);
      canvas.rotate(math.pi / 4);

      final diamondSize = isSelected ? 10.0 : 7.0;
      final rect = Rect.fromCenter(center: Offset.zero, width: diamondSize, height: diamondSize);

      if (isSelected) {
        final glow = Paint()
          ..color = const Color(0xFFFFD600).withOpacity(0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawRect(rect.inflate(2), glow);
      }

      final fillPaint = Paint()
        ..color = isSelected ? const Color(0xFFFFEA00) : const Color(0xFFFFD600)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.black87
        ..strokeWidth = isSelected ? 1.5 : 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      canvas.restore();
    }

    // 4. Draw Playhead Vertical Indicator Line
    final playheadX = timeToX(playheadSec);
    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);

    // Playhead top marker triangle
    final markerPath = Path()
      ..moveTo(playheadX - 5, 0)
      ..lineTo(playheadX + 5, 0)
      ..lineTo(playheadX, 8)
      ..close();
    canvas.drawPath(markerPath, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MotionGraphPainter oldDelegate) {
    return oldDelegate.track != track ||
        oldDelegate.playheadSec != playheadSec ||
        oldDelegate.selectedKeyframe != selectedKeyframe ||
        oldDelegate.durationSec != durationSec;
  }
}
