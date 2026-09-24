import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class _SpeedPresetOption {
  final SpeedCurvePresetType type;
  final String label;
  final IconData icon;

  const _SpeedPresetOption({
    required this.type,
    required this.label,
    required this.icon,
  });
}

/// Modal sheet offering both Normal Constant Speed (0.1x to 100x)
/// and Graphic Curve Speed Adjustment with prebuilt presets, custom 2D curve editing,
/// Pitch Preservation and Optical-Flow Smooth Slow-Mo.
class SpeedAdjustmentSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const SpeedAdjustmentSheet({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, EditorViewModel viewModel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
      ),
      builder: (_) => SpeedAdjustmentSheet(viewModel: viewModel),
    );
  }

  @override
  State<SpeedAdjustmentSheet> createState() => _SpeedAdjustmentSheetState();
}

class _SpeedAdjustmentSheetState extends State<SpeedAdjustmentSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Normal Speed state
  double _normalSpeed = 1.0;

  // Curve Speed state
  SpeedCurvePresetType _selectedPreset = SpeedCurvePresetType.none;
  List<SpeedCurvePoint> _curvePoints = [];
  int? _selectedPointIndex;

  // Advanced toggles
  bool _keepPitch = true;
  bool _smoothSlowMo = true;

  @override
  void initState() {
    super.initState();
    final clip = widget.viewModel.selectedClip;
    if (clip != null) {
      _normalSpeed = clip.speed;
      if (clip.speedCurve != null) {
        _selectedPreset = clip.speedCurve!.type;
        _curvePoints = List.from(clip.speedCurve!.points);
        _keepPitch = clip.speedCurve!.keepPitch;
        _smoothSlowMo = clip.speedCurve!.smoothSlowMo;
      } else {
        _selectedPreset = SpeedCurvePresetType.none;
        _curvePoints = List.from(SpeedCurve.montage().points);
      }
    } else {
      _curvePoints = List.from(SpeedCurve.montage().points);
    }

    final initialTab = (_selectedPreset != SpeedCurvePresetType.none) ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _applyPreset(SpeedCurvePresetType type) {
    setState(() {
      _selectedPreset = type;
      _selectedPointIndex = null;
      switch (type) {
        case SpeedCurvePresetType.none:
          break;
        case SpeedCurvePresetType.montage:
          _curvePoints = List.from(SpeedCurve.montage().points);
          break;
        case SpeedCurvePresetType.hero:
          _curvePoints = List.from(SpeedCurve.hero().points);
          break;
        case SpeedCurvePresetType.bullet:
          _curvePoints = List.from(SpeedCurve.bullet().points);
          break;
        case SpeedCurvePresetType.jumpCut:
          _curvePoints = List.from(SpeedCurve.jumpCut().points);
          break;
        case SpeedCurvePresetType.flashIn:
          _curvePoints = List.from(SpeedCurve.flashIn().points);
          break;
        case SpeedCurvePresetType.flashOut:
          _curvePoints = List.from(SpeedCurve.flashOut().points);
          break;
        case SpeedCurvePresetType.bubbly:
          _curvePoints = List.from(SpeedCurve.bubbly().points);
          break;
        case SpeedCurvePresetType.custom:
          if (_curvePoints.isEmpty) {
            _curvePoints = List.from(SpeedCurve.custom().points);
          }
          break;
      }
    });
  }

  void _onApply() {
    final isCurveTab = _tabController.index == 1;
    if (isCurveTab && _selectedPreset != SpeedCurvePresetType.none && _curvePoints.isNotEmpty) {
      final curve = SpeedCurve(
        type: _selectedPreset,
        points: _curvePoints,
        keepPitch: _keepPitch,
        smoothSlowMo: _smoothSlowMo,
      );
      widget.viewModel.setClipSpeedCurve(curve);
    } else {
      widget.viewModel.setClipSpeed(_normalSpeed);
    }
    Navigator.of(context).pop();
  }

  void _onReset() {
    setState(() {
      _normalSpeed = 1.0;
      _selectedPreset = SpeedCurvePresetType.none;
      _curvePoints = List.from(SpeedCurve.montage().points);
      _selectedPointIndex = null;
      _keepPitch = true;
      _smoothSlowMo = true;
    });
    widget.viewModel.setClipSpeed(1.0);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.viewModel.selectedClip;
    final originalTrimSec = clip != null
        ? (clip.trimEnd.inMilliseconds - clip.trimStart.inMilliseconds) / 1000.0
        : 5.0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header with Tabs
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Speed Control',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(text: 'Normal'),
                    Tab(text: 'Curve (Graphic)'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),

          // Tab Views
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNormalSpeedTab(originalTrimSec),
                _buildCurveSpeedTab(originalTrimSec),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),

          // Bottom Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textMuted),
                label: const Text('Reset (1.0x)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onPressed: _onReset,
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _onApply,
                    child: const Text('Apply Speed', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNormalSpeedTab(double originalTrimSec) {
    final effectiveSec = originalTrimSec / (_normalSpeed > 0 ? _normalSpeed : 1.0);
    final normalPresets = [0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 5.0, 10.0, 50.0, 100.0];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Speed Display
          Center(
            child: Column(
              children: [
                Text(
                  '${_normalSpeed.toStringAsFixed(1)}x',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.primary),
                ),
                Text(
                  'Duration: ${originalTrimSec.toStringAsFixed(1)}s -> ${effectiveSec.toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Continuous Slider (mapped logarithmically from 0.1 to 100)
          Slider(
            value: (math.log(_normalSpeed) - math.log(0.1)) / (math.log(100.0) - math.log(0.1)),
            min: 0.0,
            max: 1.0,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceLight,
            onChanged: (val) {
              final speed = math.exp(math.log(0.1) + val * (math.log(100.0) - math.log(0.1)));
              setState(() {
                _normalSpeed = (speed < 2.0) ? (speed * 10).round() / 10.0 : speed.roundToDouble();
              });
            },
          ),
          const SizedBox(height: 12),

          // Preset Chips including 10x and 50x
          const Text('Speed Presets:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: normalPresets.map((s) {
              final isSelected = (_normalSpeed - s).abs() < 0.05;
              return ChoiceChip(
                label: Text('${s.toStringAsFixed(s < 1 ? 1 : 0)}x'),
                selected: isSelected,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _normalSpeed = s);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Audio pitch preservation toggle
          _buildToggleOption(
            icon: Icons.record_voice_over_rounded,
            title: 'Pitch Preservation',
            subtitle: 'Retain natural voice pitch without chipmunk distortion',
            value: _keepPitch,
            onChanged: (val) => setState(() => _keepPitch = val),
          ),
          if (_normalSpeed < 1.0) ...[
            const SizedBox(height: 8),
            _buildToggleOption(
              icon: Icons.auto_awesome_rounded,
              title: 'Smooth Slow-Mo',
              subtitle: 'Simulate optical flow frame blending for buttery slow motion',
              value: _smoothSlowMo,
              onChanged: (val) => setState(() => _smoothSlowMo = val),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurveSpeedTab(double originalTrimSec) {
    final tempCurve = SpeedCurve(
      type: _selectedPreset,
      points: _curvePoints,
      keepPitch: _keepPitch,
      smoothSlowMo: _smoothSlowMo,
    );
    final avgSpeed = tempCurve.averageSpeed;
    final effectiveSec = originalTrimSec / avgSpeed;

    const presets = [
      _SpeedPresetOption(type: SpeedCurvePresetType.none, label: 'None (1x)', icon: Icons.horizontal_rule_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.montage, label: 'Montage', icon: Icons.movie_filter_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.hero, label: 'Hero', icon: Icons.flash_on_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.bullet, label: 'Bullet', icon: Icons.sports_mma_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.jumpCut, label: 'Jump Cut', icon: Icons.content_cut_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.flashIn, label: 'Flash In', icon: Icons.keyboard_double_arrow_right_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.flashOut, label: 'Flash Out', icon: Icons.keyboard_double_arrow_left_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.bubbly, label: 'Bubbly', icon: Icons.bubble_chart_rounded),
      _SpeedPresetOption(type: SpeedCurvePresetType.custom, label: 'Custom', icon: Icons.tune_rounded),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preset Selector Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: presets.map((p) {
              final isSelected = _selectedPreset == p.type;
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _applyPreset(p.type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.divider,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(p.icon, size: 14, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Speed & Duration Readout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Effective Avg Speed: ${avgSpeed.toStringAsFixed(2)}x',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              Text(
                '${originalTrimSec.toStringAsFixed(1)}s -> ${effectiveSec.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 2D Graphic Curve Canvas
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: const Color(0xFF10131A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _CurveCanvas(
                points: _curvePoints,
                selectedPointIndex: _selectedPointIndex,
                isCustom: _selectedPreset == SpeedCurvePresetType.custom,
                onSelectPoint: (idx) => setState(() => _selectedPointIndex = idx),
                onUpdatePoint: (idx, pt) {
                  setState(() {
                    _selectedPreset = SpeedCurvePresetType.custom;
                    _curvePoints[idx] = pt;
                  });
                },
                onAddPoint: (pt) {
                  if (_curvePoints.length < 10) {
                    setState(() {
                      _selectedPreset = SpeedCurvePresetType.custom;
                      _curvePoints.add(pt);
                      _curvePoints.sort((a, b) => a.timeRatio.compareTo(b.timeRatio));
                      _selectedPointIndex = _curvePoints.indexOf(pt);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Point Details & Custom Point Controls
          if (_selectedPointIndex != null && _selectedPointIndex! < _curvePoints.length) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Point ${_selectedPointIndex! + 1}: Time ${(_curvePoints[_selectedPointIndex!].timeRatio * 100).toInt()}% • Speed ${_curvePoints[_selectedPointIndex!].speedMultiplier.toStringAsFixed(1)}x',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
                if (_curvePoints.length > 2)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPreset = SpeedCurvePresetType.custom;
                        _curvePoints.removeAt(_selectedPointIndex!);
                        _selectedPointIndex = null;
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('Delete Point', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Quick speed values for selected point
            Row(
              children: [
                const Text('Snap:', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [0.2, 0.5, 1.0, 2.0, 3.5, 5.0].map((spd) {
                        final isCurr = (_curvePoints[_selectedPointIndex!].speedMultiplier - spd).abs() < 0.05;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedPreset = SpeedCurvePresetType.custom;
                                _curvePoints[_selectedPointIndex!] =
                                    _curvePoints[_selectedPointIndex!].copyWith(speedMultiplier: spd);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCurr ? AppColors.primary : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${spd}x',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isCurr ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Drag points to adjust speed curve. Tap empty space to add point.',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),

          // Toggles: Pitch Preservation & Smooth Slow-Mo
          _buildToggleOption(
            icon: Icons.record_voice_over_rounded,
            title: 'Pitch Preservation',
            subtitle: 'Retain natural voice pitch without chipmunk distortion',
            value: _keepPitch,
            onChanged: (val) => setState(() => _keepPitch = val),
          ),
          const SizedBox(height: 8),
          _buildToggleOption(
            icon: Icons.auto_awesome_rounded,
            title: 'Smooth Slow-Mo',
            subtitle: 'Simulate optical flow frame blending for buttery slow motion',
            value: _smoothSlowMo,
            onChanged: (val) => setState(() => _smoothSlowMo = val),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? AppColors.primary.withOpacity(0.3) : AppColors.divider,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.surfaceLight,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Interactive 2D Graph CustomPainter and GestureDetector widget
class _CurveCanvas extends StatelessWidget {
  final List<SpeedCurvePoint> points;
  final int? selectedPointIndex;
  final bool isCustom;
  final ValueChanged<int?> onSelectPoint;
  final void Function(int index, SpeedCurvePoint point) onUpdatePoint;
  final ValueChanged<SpeedCurvePoint> onAddPoint;

  const _CurveCanvas({
    required this.points,
    required this.selectedPointIndex,
    required this.isCustom,
    required this.onSelectPoint,
    required this.onUpdatePoint,
    required this.onAddPoint,
  });

  // Maps speed (0.1x to 10.0x) to canvas Y coordinate (bottom to top)
  static double _speedToY(double speed, double height) {
    final norm = (math.log(speed.clamp(0.1, 10.0)) - math.log(0.1)) / (math.log(10.0) - math.log(0.1));
    return height - (norm * (height - 20) + 10);
  }

  static double _yToSpeed(double y, double height) {
    final norm = ((height - y - 10) / (height - 20)).clamp(0.0, 1.0);
    return math.exp(math.log(0.1) + norm * (math.log(10.0) - math.log(0.1)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final tapPos = details.localPosition;
            for (int i = 0; i < points.length; i++) {
              final px = points[i].timeRatio * (w - 24) + 12;
              final py = _speedToY(points[i].speedMultiplier, h);
              if ((Offset(px, py) - tapPos).distance < 20) {
                onSelectPoint(i);
                return;
              }
            }

            final tRatio = ((tapPos.dx - 12) / (w - 24)).clamp(0.0, 1.0);
            final speed = _yToSpeed(tapPos.dy, h);
            onAddPoint(SpeedCurvePoint(timeRatio: tRatio, speedMultiplier: speed));
          },
          onPanUpdate: (details) {
            if (selectedPointIndex == null || selectedPointIndex! >= points.length) return;
            final idx = selectedPointIndex!;
            final isEdge = (idx == 0 || idx == points.length - 1);

            final newX = details.localPosition.dx;
            final newY = details.localPosition.dy;

            final newSpeed = _yToSpeed(newY, h);

            double newTRatio = points[idx].timeRatio;
            if (!isEdge) {
              final minT = points[idx - 1].timeRatio + 0.02;
              final maxT = points[idx + 1].timeRatio - 0.02;
              final rawTRatio = ((newX - 12) / (w - 24)).clamp(0.0, 1.0);
              newTRatio = rawTRatio.clamp(minT, maxT);
            }

            onUpdatePoint(
              idx,
              SpeedCurvePoint(timeRatio: newTRatio, speedMultiplier: newSpeed),
            );
          },
          child: CustomPaint(
            size: Size(w, h),
            painter: _CurveGraphPainter(
              points: points,
              selectedIndex: selectedPointIndex,
            ),
          ),
        );
      },
    );
  }
}

class _CurveGraphPainter extends CustomPainter {
  final List<SpeedCurvePoint> points;
  final int? selectedIndex;

  _CurveGraphPainter({required this.points, required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    final baseLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final y1x = _CurveCanvas._speedToY(1.0, h);
    canvas.drawLine(Offset(0, y1x), Offset(w, y1x), baseLinePaint);

    final textPainter = TextPainter(
      text: const TextSpan(text: '1.0x', style: TextStyle(color: Colors.white38, fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(4, y1x - 12));

    final top10x = _CurveCanvas._speedToY(10.0, h);
    canvas.drawLine(Offset(0, top10x), Offset(w, top10x), gridPaint);
    final topPainter = TextPainter(
      text: const TextSpan(text: '10.0x', style: TextStyle(color: Colors.white24, fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    topPainter.paint(canvas, Offset(4, top10x + 2));

    final bot01x = _CurveCanvas._speedToY(0.1, h);
    final botPainter = TextPainter(
      text: const TextSpan(text: '0.1x', style: TextStyle(color: Colors.white24, fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    botPainter.paint(canvas, Offset(4, bot01x - 12));

    if (points.isEmpty) return;

    final screenCoords = points.map((p) {
      final x = p.timeRatio * (w - 24) + 12;
      final y = _CurveCanvas._speedToY(p.speedMultiplier, h);
      return Offset(x, y);
    }).toList();

    final fillPath = Path()..moveTo(screenCoords.first.dx, h);
    fillPath.lineTo(screenCoords.first.dx, screenCoords.first.dy);
    for (int i = 0; i < screenCoords.length - 1; i++) {
      final p0 = screenCoords[i];
      final p1 = screenCoords[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      fillPath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    fillPath.lineTo(screenCoords.last.dx, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withOpacity(0.35),
          AppColors.primary.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    final linePath = Path()..moveTo(screenCoords.first.dx, screenCoords.first.dy);
    for (int i = 0; i < screenCoords.length - 1; i++) {
      final p0 = screenCoords[i];
      final p1 = screenCoords[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    for (int i = 0; i < screenCoords.length; i++) {
      final pt = screenCoords[i];
      final isSelected = selectedIndex == i;

      if (isSelected) {
        final glowPaint = Paint()
          ..color = AppColors.primary.withOpacity(0.4)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 12, glowPaint);
      }

      final pointPaint = Paint()
        ..color = isSelected ? Colors.white : AppColors.primary
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 6.5 : 5.0, pointPaint);

      final pointBorder = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pt, isSelected ? 6.5 : 5.0, pointBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CurveGraphPainter oldDelegate) => true;
}
