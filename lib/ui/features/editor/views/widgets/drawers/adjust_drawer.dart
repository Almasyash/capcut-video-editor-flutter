import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/tts_service.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/rgb_curves_model.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class AdjustDrawer extends StatefulWidget {
  final EditorViewModel viewModel;

  const AdjustDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  State<AdjustDrawer> createState() => _AdjustDrawerState();
}

class _AdjustDrawerState extends State<AdjustDrawer> {
  String _activeProperty = 'Brightness';
  bool _showCurveEditor = false;
  CurveChannel _selectedCurveChannel = CurveChannel.master;

  @override
  Widget build(BuildContext context) {
    final adj = widget.viewModel.colorAdjustments;

    return Container(
      height: _showCurveEditor ? 280 : 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      _showCurveEditor ? 'RGB Curves' : 'Adjustments: $_activeProperty',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showCurveEditor ? Icons.tune_rounded : Icons.show_chart_rounded,
                        color: _showCurveEditor ? AppColors.secondary : AppColors.primary,
                        size: 20,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      tooltip: _showCurveEditor ? 'Back to Sliders' : 'RGB Curves',
                      onPressed: () {
                        setState(() => _showCurveEditor = !_showCurveEditor);
                        TtsService.announce(_showCurveEditor ? 'RGB Curves opened' : 'Sliders opened');
                      },
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        widget.viewModel.resetColorAdjustments();
                      },
                      child: const Text('Reset', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                    const SizedBox(width: 6),
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

          if (_showCurveEditor)
            Expanded(child: _buildCurveEditor(adj))
          else ...[
            // Active Slider
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
              child: _buildActiveSlider(adj),
            ),

            // Property Selector Carousel
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  _buildPropertyPill('Exposure', Icons.exposure_rounded, (adj.exposure * 100).round()),
                  _buildPropertyPill('Brightness', Icons.brightness_6_rounded, (adj.brightness * 100).round()),
                  _buildPropertyPill('Contrast', Icons.contrast_rounded, ((adj.contrast - 1.0) * 100).round()),
                  _buildPropertyPill('Saturation', Icons.gradient_rounded, ((adj.saturation - 1.0) * 100).round()),
                  _buildPropertyPill('Temperature', Icons.thermostat_rounded, (adj.temperature * 100).round()),
                  _buildPropertyPill('Tint', Icons.colorize_rounded, (adj.tint * 100).round()),
                  _buildPropertyPill('Highlights', Icons.wb_sunny_outlined, (adj.highlights * 100).round()),
                  _buildPropertyPill('Shadows', Icons.nightlight_round, (adj.shadows * 100).round()),
                  _buildPropertyPill('Blacks', Icons.brightness_1_rounded, (adj.blacks * 100).round()),
                  _buildPropertyPill('Whites', Icons.brightness_medium_rounded, (adj.whites * 100).round()),
                  _buildPropertyPill('Vignette', Icons.vignette_rounded, (adj.vignette * 100).round()),
                  _buildPropertyPill('Sharpen', Icons.details_rounded, (adj.sharpness * 100).round()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSlider(ColorAdjustments adj) {
    double value = 0.0;
    double min = -1.0;
    double max = 1.0;
    String displayValue = '0';

    switch (_activeProperty) {
      case 'Exposure':
        value = adj.exposure;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Brightness':
        value = adj.brightness;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Contrast':
        value = adj.contrast;
        min = 0.0;
        max = 2.0;
        displayValue = '${((value - 1.0) * 100).round()}';
        break;
      case 'Saturation':
        value = adj.saturation;
        min = 0.0;
        max = 2.0;
        displayValue = '${((value - 1.0) * 100).round()}';
        break;
      case 'Temperature':
        value = adj.temperature;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Tint':
        value = adj.tint;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Highlights':
        value = adj.highlights;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Shadows':
        value = adj.shadows;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Blacks':
        value = adj.blacks;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Whites':
        value = adj.whites;
        displayValue = '${(value * 100).round()}';
        break;
      case 'Vignette':
        value = adj.vignette;
        min = 0.0;
        max = 1.0;
        displayValue = '${(value * 100).round()}%';
        break;
      case 'Sharpen':
        value = adj.sharpness;
        min = 0.0;
        max = 1.0;
        displayValue = '${(value * 100).round()}%';
        break;
    }

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('$_activeProperty:', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.primary,
            onChanged: (val) {
              ColorAdjustments updated;
              switch (_activeProperty) {
                case 'Exposure':
                  updated = adj.copyWith(exposure: val);
                  break;
                case 'Brightness':
                  updated = adj.copyWith(brightness: val);
                  break;
                case 'Contrast':
                  updated = adj.copyWith(contrast: val);
                  break;
                case 'Saturation':
                  updated = adj.copyWith(saturation: val);
                  break;
                case 'Temperature':
                  updated = adj.copyWith(temperature: val);
                  break;
                case 'Tint':
                  updated = adj.copyWith(tint: val);
                  break;
                case 'Highlights':
                  updated = adj.copyWith(highlights: val);
                  break;
                case 'Shadows':
                  updated = adj.copyWith(shadows: val);
                  break;
                case 'Blacks':
                  updated = adj.copyWith(blacks: val);
                  break;
                case 'Whites':
                  updated = adj.copyWith(whites: val);
                  break;
                case 'Vignette':
                  updated = adj.copyWith(vignette: val);
                  break;
                case 'Sharpen':
                  updated = adj.copyWith(sharpness: val);
                  break;
                default:
                  updated = adj;
              }
              widget.viewModel.updateColorAdjustments(updated);
            },
            onChangeEnd: (val) {
              ColorAdjustments updated;
              switch (_activeProperty) {
                case 'Exposure':
                  updated = adj.copyWith(exposure: val);
                  break;
                case 'Brightness':
                  updated = adj.copyWith(brightness: val);
                  break;
                case 'Contrast':
                  updated = adj.copyWith(contrast: val);
                  break;
                case 'Saturation':
                  updated = adj.copyWith(saturation: val);
                  break;
                case 'Temperature':
                  updated = adj.copyWith(temperature: val);
                  break;
                case 'Tint':
                  updated = adj.copyWith(tint: val);
                  break;
                case 'Highlights':
                  updated = adj.copyWith(highlights: val);
                  break;
                case 'Shadows':
                  updated = adj.copyWith(shadows: val);
                  break;
                case 'Blacks':
                  updated = adj.copyWith(blacks: val);
                  break;
                case 'Whites':
                  updated = adj.copyWith(whites: val);
                  break;
                case 'Vignette':
                  updated = adj.copyWith(vignette: val);
                  break;
                case 'Sharpen':
                  updated = adj.copyWith(sharpness: val);
                  break;
                default:
                  updated = adj;
              }
              widget.viewModel.commitColorAdjustments(updated, propertyName: _activeProperty);
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            displayValue,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyPill(String name, IconData icon, int val) {
    final isSelected = _activeProperty == name;
    final hasAdjustment = val != 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        onTap: () {
          setState(() => _activeProperty = name);
          TtsService.announce('$name control selected');
        },
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.primary : (hasAdjustment ? AppColors.secondary : AppColors.divider),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.primary : Colors.white70),
              const SizedBox(height: 4),
              Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurveEditor(ColorAdjustments adj) {
    final curves = adj.curves;
    final channelPoints = curves.getChannel(_selectedCurveChannel);

    Color channelColor;
    switch (_selectedCurveChannel) {
      case CurveChannel.master:
        channelColor = Colors.white;
        break;
      case CurveChannel.red:
        channelColor = const Color(0xFFFF5252);
        break;
      case CurveChannel.green:
        channelColor = const Color(0xFF69F0AE);
        break;
      case CurveChannel.blue:
        channelColor = const Color(0xFF448AFF);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // Channel selector pills
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChannelPill('RGB', CurveChannel.master, Colors.white),
              const SizedBox(width: 8),
              _buildChannelPill('Red', CurveChannel.red, const Color(0xFFFF5252)),
              const SizedBox(width: 8),
              _buildChannelPill('Green', CurveChannel.green, const Color(0xFF69F0AE)),
              const SizedBox(width: 8),
              _buildChannelPill('Blue', CurveChannel.blue, const Color(0xFF448AFF)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final updatedCurves = curves.resetChannel(_selectedCurveChannel);
                  widget.viewModel.commitColorAdjustments(
                    adj.copyWith(curves: updatedCurves),
                    propertyName: 'Curve ${_selectedCurveChannel.name}',
                  );
                },
                child: const Text('Reset Channel', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Interactive 2D curve canvas
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider, width: 0.8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;

                    return GestureDetector(
                      onTapDown: (details) {
                        final local = details.localPosition;
                        final normX = (local.dx / w).clamp(0.0, 1.0);
                        final normY = (1.0 - (local.dy / h)).clamp(0.0, 1.0);

                        final newPoint = CurvePoint(normX, normY);
                        final updatedCurves = curves.addPoint(_selectedCurveChannel, newPoint);
                        widget.viewModel.commitColorAdjustments(
                          adj.copyWith(curves: updatedCurves),
                          propertyName: 'Curve point added',
                        );
                      },
                      child: CustomPaint(
                        size: Size(w, h),
                        painter: _CurvePainter(
                          points: channelPoints,
                          channelColor: channelColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelPill(String label, CurveChannel channel, Color color) {
    final isSelected = _selectedCurveChannel == channel;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCurveChannel = channel);
        TtsService.announce('$label curve channel selected');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.25) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : AppColors.divider, width: isSelected ? 1.5 : 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> points;
  final Color channelColor;

  _CurvePainter({required this.points, required this.channelColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.8;

    for (int i = 1; i < 4; i++) {
      final x = size.width * (i / 4.0);
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Identity reference diagonal
    final diagPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagPaint);

    if (points.isEmpty) return;

    // Draw curve path
    final curvePath = Path();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final px = p.x * size.width;
      final py = (1.0 - p.y) * size.height;
      if (i == 0) {
        curvePath.moveTo(px, py);
      } else {
        curvePath.lineTo(px, py);
      }
    }

    final curvePaint = Paint()
      ..color = channelColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, curvePaint);

    // Draw point markers
    final pointPaint = Paint()
      ..color = channelColor
      ..style = PaintingStyle.fill;
    final haloPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final p in points) {
      final px = p.x * size.width;
      final py = (1.0 - p.y) * size.height;
      canvas.drawCircle(Offset(px, py), 4.0, pointPaint);
      canvas.drawCircle(Offset(px, py), 4.0, haloPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.channelColor != channelColor;
}
