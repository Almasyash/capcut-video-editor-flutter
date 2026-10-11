import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/core/services/tts_service.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Display mode for the motion graph visualizer (Value vs. Speed/Velocity curve)
enum MotionGraphDisplayMode {
  valueCurve('Value Curve', Icons.timeline_rounded),
  speedCurve('Speed / Velocity', Icons.speed_rounded);

  final String label;
  final IconData icon;
  const MotionGraphDisplayMode(this.label, this.icon);
}

/// Active touch drag targets on the interactive canvas
enum _ActiveDragType {
  none,
  keyframePoint,
  tangentHandle1,
  tangentHandle2,
  playhead,
}

/// High-precision coordinates and math bridge for canvas rendering and touch hit-testing
class MotionGraphCoordinates {
  final Size size;
  final KeyframeTrack track;
  final double durationSec;
  final AnimatableProperty property;

  late final double minVal;
  late final double maxVal;

  MotionGraphCoordinates({
    required this.size,
    required this.track,
    required this.durationSec,
    required this.property,
  }) {
    double tMin = property.minValue;
    double tMax = property.maxValue;

    if (track.isNotEmpty) {
      double kMin = track.keyframes.first.value;
      double kMax = track.keyframes.first.value;
      for (final k in track.keyframes) {
        if (k.value < kMin) kMin = k.value;
        if (k.value > kMax) kMax = k.value;
      }
      final margin = math.max((kMax - kMin).abs() * 0.25, 0.5);
      tMin = math.min(tMin, kMin - margin);
      tMax = math.max(tMax, kMax + margin);
    }

    if ((tMax - tMin).abs() < 1e-4) {
      tMax = tMin + 1.0;
    }
    minVal = tMin;
    maxVal = tMax;
  }

  double valueToY(double val) {
    if (size.height <= 0) return 0;
    final norm = (val - minVal) / (maxVal - minVal);
    final rawY = size.height - (norm * (size.height - 36.0) + 18.0);
    return rawY.clamp(6.0, size.height - 6.0);
  }

  double yToValue(double y) {
    if (size.height <= 36.0) return property.defaultValue;
    final norm = (size.height - 18.0 - y) / (size.height - 36.0);
    final val = minVal + norm * (maxVal - minVal);
    return property.sanitize(val);
  }

  double timeToX(double tSec) {
    if (durationSec <= 0 || size.width <= 0) return 0;
    return ((tSec / durationSec).clamp(0.0, 1.0)) * size.width;
  }

  double xToTime(double x) {
    if (size.width <= 0) return 0;
    return (x / size.width).clamp(0.0, 1.0) * durationSec;
  }

  Offset keyframeOffset(MotionKeyframe kf) {
    return Offset(timeToX(kf.timeInSeconds), valueToY(kf.value));
  }

  (Offset h1, Offset h2)? getBezierHandleOffsets(MotionKeyframe k1, MotionKeyframe k2) {
    final dt = k2.timeInSeconds - k1.timeInSeconds;
    if (dt <= 0) return null;

    final curve = k1.easing;
    final dv = k2.value - k1.value;
    final effectiveDv = dv.abs() < 1e-3 ? (maxVal - minVal) * 0.35 : dv;

    final tH1 = k1.timeInSeconds + curve.x1 * dt;
    final vH1 = k1.value + curve.y1 * effectiveDv;

    final tH2 = k1.timeInSeconds + curve.x2 * dt;
    final vH2 = k1.value + curve.y2 * effectiveDv;

    return (
      Offset(timeToX(tH1), valueToY(vH1)),
      Offset(timeToX(tH2), valueToY(vH2)),
    );
  }
}

/// Professional Motion Graph and Easing Editor Bottom Sheet
/// Provides high-precision visual curve preview, keyframe time/value editing,
/// interactive Bézier tangent handle manipulation, and velocity/speed curve inspection.
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
  MotionGraphDisplayMode _displayMode = MotionGraphDisplayMode.valueCurve;
  bool _syncTransformTracks = true;

  // Active touch interaction state
  _ActiveDragType _dragType = _ActiveDragType.none;
  MotionKeyframe? _draggedKeyframe;
  MotionKeyframe? _nextKeyframe;
  String? _dragTooltipText;
  Offset? _dragTooltipPos;

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
    // Segment resolution: direct match under playhead or preceding keyframe governing the segment
    return track.getKeyframeAtOrBefore(relTimeMs);
  }

  MotionKeyframe? _getNextKeyframe(KeyframeTrack? track, MotionKeyframe? kf) {
    if (track == null || kf == null) return null;
    for (int i = 0; i < track.keyframes.length; i++) {
      if (track.keyframes[i].timestampMs == kf.timestampMs) {
        if (i + 1 < track.keyframes.length) {
          return track.keyframes[i + 1];
        }
        break;
      }
    }
    return null;
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
        final nextKf = _getNextKeyframe(track, selectedKf);
        final layerDuration = math.max(0.1, _getLayerDurationSec());
        final relPlayheadSec = _getLayerRelativePlayheadSec();

        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
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
              // 1. Drag Handle & Header (with Value vs Speed Toggle)
              _buildHeader(context),

              // 2. Property Selector Tabs
              _buildPropertySelector(trackGroup),

              const SizedBox(height: 8),

              // 3. Motion Graph Interactive Visualizer Canvas
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    child: Container(
                      color: const Color(0xFF0D0D0E),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final coords = MotionGraphCoordinates(
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                            track: track,
                            durationSec: layerDuration,
                            property: _selectedProperty,
                          );

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (details) => _handlePanStart(details, coords, track, selectedKf, nextKf),
                            onPanUpdate: (details) => _handlePanUpdate(details, coords, track, layerDuration),
                            onPanEnd: (_) => _handlePanEnd(),
                            onPanCancel: () => _handlePanEnd(),
                            onTapDown: (details) => _handleTapDown(details, coords, track, layerDuration),
                            child: CustomPaint(
                              painter: _MotionGraphPainter(
                                track: track,
                                durationSec: layerDuration,
                                playheadSec: relPlayheadSec,
                                selectedKeyframe: selectedKf,
                                nextKeyframe: nextKf,
                                property: _selectedProperty,
                                displayMode: _displayMode,
                                coords: coords,
                                dragTooltipText: _dragTooltipText,
                                dragTooltipPos: _dragTooltipPos,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // 4. Easing Curve Selector Controls & Tangent Modes
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Motion Graph',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Curve Mode Pill Toggle (Value vs Speed)
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModeButton(
                      mode: MotionGraphDisplayMode.valueCurve,
                      label: 'Value',
                      icon: Icons.timeline_rounded,
                    ),
                    _buildModeButton(
                      mode: MotionGraphDisplayMode.speedCurve,
                      label: 'Speed',
                      icon: Icons.speed_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Reset Animation Button
              IconButton(
                onPressed: () {
                  widget.viewModel.resetAnimationForSelectedLayer();
                  TtsService.announce('Reset animation');
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Colors.white70),
                tooltip: 'Reset animation',
                visualDensity: VisualDensity.compact,
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

  Widget _buildModeButton({
    required MotionGraphDisplayMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _displayMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _displayMode = mode;
        });
        HapticFeedback.selectionClick();
        TtsService.announce('$label mode');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.black : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white60,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
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
    final isBezier = currentMode == InterpolationMode.cubicBezier;
    final currentTangentMode = selectedKf?.easing.tangentMode ?? TangentMode.autoSmooth;

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
              if (_selectedProperty.isTransform) ...[
                InkWell(
                  onTap: () {
                    setState(() {
                      _syncTransformTracks = !_syncTransformTracks;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _syncTransformTracks ? Icons.link_rounded : Icons.link_off_rounded,
                          size: 13,
                          color: _syncTransformTracks ? const Color(0xFFFFD600) : Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _syncTransformTracks ? 'Sync Transforms' : 'Single Track',
                          style: TextStyle(
                            color: _syncTransformTracks ? const Color(0xFFFFD600) : Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
            height: 34,
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
                          final newCurve = modeItem.$1 == InterpolationMode.cubicBezier
                              ? EasingCurve.cubic(0.25, 0.1, 0.25, 1.0)
                              : EasingCurve(mode: modeItem.$1);
                          widget.viewModel.updateKeyframeEasing(
                            _selectedProperty,
                            selectedKf.timestampMs,
                            newCurve,
                            syncAllTransformProperties: _syncTransformTracks,
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
          if (isBezier && selectedKf != null) ...[
            const SizedBox(height: 6),
            // Tangent Handle Linking Modes (Auto Smooth / Broken / Linear)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'TANGENTS:',
                    style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  _buildTangentModeChip(selectedKf, TangentMode.autoSmooth, currentTangentMode),
                  const SizedBox(width: 4),
                  _buildTangentModeChip(selectedKf, TangentMode.broken, currentTangentMode),
                  const SizedBox(width: 4),
                  _buildTangentModeChip(selectedKf, TangentMode.linear, currentTangentMode),
                  const SizedBox(width: 12),
                  // Reset Handles to Default
                  InkWell(
                    onTap: () {
                      widget.viewModel.updateKeyframeBezierHandles(
                        _selectedProperty,
                        selectedKf.timestampMs,
                        0.42,
                        0.0,
                        0.58,
                        1.0,
                        tangentMode: TangentMode.autoSmooth,
                        syncAllTransformProperties: _syncTransformTracks,
                      );
                      HapticFeedback.lightImpact();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Reset Handles',
                        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTangentModeChip(MotionKeyframe kf, TangentMode mode, TangentMode currentMode) {
    final isSelected = mode == currentMode;
    return GestureDetector(
      onTap: () {
        final curve = kf.easing.copyWith(tangentMode: mode);
        widget.viewModel.updateKeyframeEasing(
          _selectedProperty,
          kf.timestampMs,
          curve,
          syncAllTransformProperties: _syncTransformTracks,
        );
        HapticFeedback.selectionClick();
        TtsService.announce(mode.label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E1E22),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white12),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
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
                            widget.viewModel.updateKeyframeValueAtTime(
                              _selectedProperty,
                              selectedKf.timestampMs,
                              newVal,
                            );
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

  // --- Touch Gestures Handling ---

  void _handlePanStart(
    DragStartDetails details,
    MotionGraphCoordinates coords,
    KeyframeTrack track,
    MotionKeyframe? selectedKf,
    MotionKeyframe? nextKf,
  ) {
    final pos = details.localPosition;
    const hitRadius = 28.0; // High-DPI physical touch radius

    // 1. Check Bézier Tangent Handles first if keyframe has cubic Bézier easing
    if (selectedKf != null && nextKf != null && selectedKf.easing.mode == InterpolationMode.cubicBezier) {
      final handles = coords.getBezierHandleOffsets(selectedKf, nextKf);
      if (handles != null) {
        if ((pos - handles.$1).distance <= hitRadius) {
          _dragType = _ActiveDragType.tangentHandle1;
          _draggedKeyframe = selectedKf;
          _nextKeyframe = nextKf;
          HapticFeedback.lightImpact();
          setState(() {
            _dragTooltipPos = handles.$1;
            _dragTooltipText = 'H1 (${selectedKf.easing.x1.toStringAsFixed(2)}, ${selectedKf.easing.y1.toStringAsFixed(2)})';
          });
          return;
        }
        if ((pos - handles.$2).distance <= hitRadius) {
          _dragType = _ActiveDragType.tangentHandle2;
          _draggedKeyframe = selectedKf;
          _nextKeyframe = nextKf;
          HapticFeedback.lightImpact();
          setState(() {
            _dragTooltipPos = handles.$2;
            _dragTooltipText = 'H2 (${selectedKf.easing.x2.toStringAsFixed(2)}, ${selectedKf.easing.y2.toStringAsFixed(2)})';
          });
          return;
        }
      }
    }

    // 2. Check Keyframe Diamonds
    for (final kf in track.keyframes) {
      final kfPos = coords.keyframeOffset(kf);
      if ((pos - kfPos).distance <= hitRadius) {
        _dragType = _ActiveDragType.keyframePoint;
        _draggedKeyframe = kf;
        _seekToLayerRelativeTime(kf.timeInSeconds);
        HapticFeedback.mediumImpact();
        setState(() {
          _dragTooltipPos = kfPos;
          _dragTooltipText = '${kf.timeInSeconds.toStringAsFixed(2)}s: ${kf.value.toStringAsFixed(1)}';
        });
        return;
      }
    }

    // 3. Check Playhead Line
    final playheadX = coords.timeToX(_getLayerRelativePlayheadSec());
    if ((pos.dx - playheadX).abs() <= 20.0) {
      _dragType = _ActiveDragType.playhead;
      return;
    }

    // 4. Default: Scrub to touch location
    _dragType = _ActiveDragType.playhead;
    _seekToLayerRelativeTime(coords.xToTime(pos.dx));
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    MotionGraphCoordinates coords,
    KeyframeTrack track,
    double layerDuration,
  ) {
    final pos = details.localPosition;

    switch (_dragType) {
      case _ActiveDragType.keyframePoint:
        if (_draggedKeyframe == null) return;
        final newSec = coords.xToTime(pos.dx).clamp(0.0, layerDuration);
        final newMs = (newSec * 1000).round();
        final newVal = coords.yToValue(pos.dy);

        // Update keyframe time if dragged horizontally
        if ((newMs - _draggedKeyframe!.timestampMs).abs() > 30) {
          widget.viewModel.moveSelectedKeyframe(_selectedProperty, _draggedKeyframe!.timestampMs, newMs);
          _draggedKeyframe = _draggedKeyframe!.copyWith(timestampMs: newMs);
        }
        // Update keyframe value if dragged vertically
        widget.viewModel.updateKeyframeValueAtTime(_selectedProperty, _draggedKeyframe!.timestampMs, newVal);
        _draggedKeyframe = _draggedKeyframe!.copyWith(value: newVal);

        setState(() {
          _dragTooltipPos = Offset(pos.dx, pos.dy - 24);
          _dragTooltipText = '${(newMs / 1000.0).toStringAsFixed(2)}s: ${newVal.toStringAsFixed(1)}';
        });
        break;

      case _ActiveDragType.tangentHandle1:
        if (_draggedKeyframe == null || _nextKeyframe == null) return;
        final dt = _nextKeyframe!.timeInSeconds - _draggedKeyframe!.timeInSeconds;
        if (dt <= 0) return;

        final tTouch = coords.xToTime(pos.dx);
        final relX = ((tTouch - _draggedKeyframe!.timeInSeconds) / dt).clamp(0.0, 1.0);

        final dv = _nextKeyframe!.value - _draggedKeyframe!.value;
        final effectiveDv = dv.abs() < 1e-3 ? (coords.maxVal - coords.minVal) * 0.35 : dv;
        final vTouch = coords.yToValue(pos.dy);
        final relY = ((vTouch - _draggedKeyframe!.value) / effectiveDv).clamp(-2.0, 3.0);

        widget.viewModel.updateKeyframeBezierHandles(
          _selectedProperty,
          _draggedKeyframe!.timestampMs,
          relX,
          relY,
          _draggedKeyframe!.easing.x2,
          _draggedKeyframe!.easing.y2,
          tangentMode: _draggedKeyframe!.easing.tangentMode,
          syncAllTransformProperties: _syncTransformTracks,
        );

        setState(() {
          _dragTooltipPos = Offset(pos.dx, pos.dy - 24);
          _dragTooltipText = 'H1 (${relX.toStringAsFixed(2)}, ${relY.toStringAsFixed(2)})';
        });
        break;

      case _ActiveDragType.tangentHandle2:
        if (_draggedKeyframe == null || _nextKeyframe == null) return;
        final dt = _nextKeyframe!.timeInSeconds - _draggedKeyframe!.timeInSeconds;
        if (dt <= 0) return;

        final tTouch = coords.xToTime(pos.dx);
        final relX = ((tTouch - _draggedKeyframe!.timeInSeconds) / dt).clamp(0.0, 1.0);

        final dv = _nextKeyframe!.value - _draggedKeyframe!.value;
        final effectiveDv = dv.abs() < 1e-3 ? (coords.maxVal - coords.minVal) * 0.35 : dv;
        final vTouch = coords.yToValue(pos.dy);
        final relY = ((vTouch - _draggedKeyframe!.value) / effectiveDv).clamp(-2.0, 3.0);

        widget.viewModel.updateKeyframeBezierHandles(
          _selectedProperty,
          _draggedKeyframe!.timestampMs,
          _draggedKeyframe!.easing.x1,
          _draggedKeyframe!.easing.y1,
          relX,
          relY,
          tangentMode: _draggedKeyframe!.easing.tangentMode,
          syncAllTransformProperties: _syncTransformTracks,
        );

        setState(() {
          _dragTooltipPos = Offset(pos.dx, pos.dy - 24);
          _dragTooltipText = 'H2 (${relX.toStringAsFixed(2)}, ${relY.toStringAsFixed(2)})';
        });
        break;

      case _ActiveDragType.playhead:
        _seekToLayerRelativeTime(coords.xToTime(pos.dx));
        break;

      case _ActiveDragType.none:
        break;
    }
  }

  void _handlePanEnd() {
    setState(() {
      _dragType = _ActiveDragType.none;
      _draggedKeyframe = null;
      _nextKeyframe = null;
      _dragTooltipText = null;
      _dragTooltipPos = null;
    });
  }

  void _handleTapDown(
    TapDownDetails details,
    MotionGraphCoordinates coords,
    KeyframeTrack track,
    double layerDuration,
  ) {
    final tapX = details.localPosition.dx;
    var targetRelSec = coords.xToTime(tapX);

    // Proximity snap to keyframe diamonds (within 24 logical pixels)
    for (final kf in track.keyframes) {
      final kfX = coords.timeToX(kf.timeInSeconds);
      if ((tapX - kfX).abs() <= 24.0) {
        targetRelSec = kf.timeInSeconds;
        HapticFeedback.selectionClick();
        break;
      }
    }
    _seekToLayerRelativeTime(targetRelSec);
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

/// CustomPainter rendering grid, continuous evaluated curve, keyframe diamonds,
/// interactive Bézier tangent handles, velocity speed graphs, and active coordinate tooltips
class _MotionGraphPainter extends CustomPainter {
  final KeyframeTrack track;
  final double durationSec;
  final double playheadSec;
  final MotionKeyframe? selectedKeyframe;
  final MotionKeyframe? nextKeyframe;
  final AnimatableProperty property;
  final MotionGraphDisplayMode displayMode;
  final MotionGraphCoordinates coords;
  final String? dragTooltipText;
  final Offset? dragTooltipPos;

  _MotionGraphPainter({
    required this.track,
    required this.durationSec,
    required this.playheadSec,
    required this.selectedKeyframe,
    required this.nextKeyframe,
    required this.property,
    required this.displayMode,
    required this.coords,
    this.dragTooltipText,
    this.dragTooltipPos,
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

    if (displayMode == MotionGraphDisplayMode.speedCurve) {
      // 2A. Render Speed / Velocity Graph
      _paintSpeedCurve(canvas, size);
    } else {
      // 2B. Render Standard Value Curve & Bézier Handles
      _paintValueCurve(canvas, size);
    }

    // 3. Draw Playhead Vertical Indicator Line
    final playheadX = coords.timeToX(playheadSec);
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

    // 4. Draw Dragging Tooltip HUD
    if (dragTooltipText != null && dragTooltipPos != null) {
      _paintTooltip(canvas, size, dragTooltipText!, dragTooltipPos!);
    }
  }

  void _paintValueCurve(Canvas canvas, Size size) {
    // Continuous evaluated curve (120 sampled intervals for exact easing curvature)
    final curvePath = Path();
    const sampleCount = 120;
    for (int i = 0; i <= sampleCount; i++) {
      final t = (i / sampleCount) * durationSec;
      final val = track.isEmpty ? property.defaultValue : track.evaluate(t);
      final x = coords.timeToX(t);
      final y = coords.valueToY(val);
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

    // Interactive Bézier Tangent Handles (for selected segment)
    if (selectedKeyframe != null && nextKeyframe != null && selectedKeyframe!.easing.mode == InterpolationMode.cubicBezier) {
      final handles = coords.getBezierHandleOffsets(selectedKeyframe!, nextKeyframe!);
      if (handles != null) {
        final kf1Pos = coords.keyframeOffset(selectedKeyframe!);
        final kf2Pos = coords.keyframeOffset(nextKeyframe!);

        final dashedPaint1 = Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        final dashedPaint2 = Paint()
          ..color = const Color(0xFFFFB300).withOpacity(0.8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        // Draw handle connection lines
        _drawDashedLine(canvas, kf1Pos, handles.$1, dashedPaint1);
        _drawDashedLine(canvas, kf2Pos, handles.$2, dashedPaint2);

        // Draw Handle 1 Knob (Cyan)
        _drawHandleKnob(canvas, handles.$1, const Color(0xFF00E5FF), '1');

        // Draw Handle 2 Knob (Amber)
        _drawHandleKnob(canvas, handles.$2, const Color(0xFFFFB300), '2');
      }
    }

    // Draw Keyframe Diamonds on the curve
    for (final kf in track.keyframes) {
      final kfPos = coords.keyframeOffset(kf);
      final isSelected = selectedKeyframe?.timestampMs == kf.timestampMs;

      canvas.save();
      canvas.translate(kfPos.dx, kfPos.dy);
      canvas.rotate(math.pi / 4);

      final diamondSize = isSelected ? 11.0 : 7.0;
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
  }

  void _paintSpeedCurve(Canvas canvas, Size size) {
    const sampleCount = 100;
    final speeds = <double>[];
    double maxSpeed = 0.01;

    for (int i = 0; i <= sampleCount; i++) {
      final t = (i / sampleCount) * durationSec;
      final speed = track.evaluateDerivative(t).abs();
      speeds.add(speed);
      if (speed > maxSpeed) maxSpeed = speed;
    }

    double speedToY(double sp) {
      final norm = (sp / maxSpeed).clamp(0.0, 1.0);
      return size.height - (norm * (size.height - 36.0) + 18.0);
    }

    // Speed curve area fill and stroke path
    final speedPath = Path();
    final areaPath = Path();

    for (int i = 0; i <= sampleCount; i++) {
      final t = (i / sampleCount) * durationSec;
      final x = coords.timeToX(t);
      final y = speedToY(speeds[i]);

      if (i == 0) {
        speedPath.moveTo(x, y);
        areaPath.moveTo(x, size.height);
        areaPath.lineTo(x, y);
      } else {
        speedPath.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
    }
    areaPath.lineTo(size.width, size.height);
    areaPath.close();

    // Fill Area under speed curve
    final areaPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, size.height),
        [
          const Color(0xFF00E5FF).withOpacity(0.35),
          const Color(0xFF00E5FF).withOpacity(0.02),
        ],
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, areaPaint);

    // Speed Stroke Line
    final strokePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(speedPath, strokePaint);

    // Draw Keyframe Speed Markers
    for (final kf in track.keyframes) {
      final kfX = coords.timeToX(kf.timeInSeconds);
      final speed = track.evaluateDerivative(kf.timeInSeconds).abs();
      final kfY = speedToY(speed);

      final circlePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(kfX, kfY), 4.5, circlePaint);
      canvas.drawCircle(
        Offset(kfX, kfY),
        4.5,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    // Speed Scale Legend text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Max Speed: ${maxSpeed.toStringAsFixed(1)} ${property.unit}/s',
        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(10, 8));
  }

  void _drawHandleKnob(Canvas canvas, Offset pos, Color color, String label) {
    // Outer touch guide circle
    final guidePaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 12.0, guidePaint);

    // Handle solid knob
    final knobPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 6.0, knobPaint);

    // White border
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(pos, 6.0, borderPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 4.0;
    const dashSpace = 3.0;
    final totalDistance = (p2 - p1).distance;
    if (totalDistance <= 0) return;

    final dx = (p2.dx - p1.dx) / totalDistance;
    final dy = (p2.dy - p1.dy) / totalDistance;

    double currentDist = 0.0;
    while (currentDist < totalDistance) {
      final start = Offset(p1.dx + dx * currentDist, p1.dy + dy * currentDist);
      final endDist = math.min(currentDist + dashLength, totalDistance);
      final end = Offset(p1.dx + dx * endDist, p1.dy + dy * endDist);
      canvas.drawLine(start, end, paint);
      currentDist += dashLength + dashSpace;
    }
  }

  void _paintTooltip(Canvas canvas, Size size, String text, Offset pos) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final width = textPainter.width + padding.horizontal;
    final height = textPainter.height + padding.vertical;

    final tooltipX = (pos.dx - width / 2).clamp(4.0, size.width - width - 4.0);
    final tooltipY = (pos.dy - height - 4.0).clamp(4.0, size.height - height - 4.0);
    final rect = Rect.fromLTWH(tooltipX, tooltipY, width, height);

    final bgPaint = Paint()
      ..color = const Color(0xFFFFD600)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), bgPaint);

    textPainter.paint(canvas, Offset(tooltipX + padding.left, tooltipY + padding.top));
  }

  @override
  bool shouldRepaint(covariant _MotionGraphPainter oldDelegate) {
    return oldDelegate.track != track ||
        oldDelegate.playheadSec != playheadSec ||
        oldDelegate.selectedKeyframe != selectedKeyframe ||
        oldDelegate.nextKeyframe != nextKeyframe ||
        oldDelegate.displayMode != displayMode ||
        oldDelegate.durationSec != durationSec ||
        oldDelegate.dragTooltipText != dragTooltipText ||
        oldDelegate.dragTooltipPos != dragTooltipPos;
  }
}
