import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
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

  @override
  Widget build(BuildContext context) {
    final adj = widget.viewModel.colorAdjustments;

    return Container(
      height: 200,
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
                    Text('Adjustments: $_activeProperty', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ],
                ),
                Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.viewModel.resetColorAdjustments,
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

          // Active Slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
            child: _buildActiveSlider(adj),
          ),

          // Property Selector Buttons
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _buildPropertyPill('Brightness', Icons.brightness_6_rounded, (adj.brightness * 100).round()),
                _buildPropertyPill('Contrast', Icons.contrast_rounded, ((adj.contrast - 1.0) * 100).round()),
                _buildPropertyPill('Saturation', Icons.gradient_rounded, ((adj.saturation - 1.0) * 100).round()),
                _buildPropertyPill('Exposure', Icons.exposure_rounded, (adj.exposure * 100).round()),
                _buildPropertyPill('Temperature', Icons.thermostat_rounded, (adj.temperature * 100).round()),
                _buildPropertyPill('Vignette', Icons.vignette_rounded, (adj.vignette * 100).round()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSlider(dynamic adj) {
    double value = 0.0;
    double min = -1.0;
    double max = 1.0;
    String displayValue = '0';

    if (_activeProperty == 'Brightness') {
      value = adj.brightness;
      displayValue = '${(value * 100).round()}';
    } else if (_activeProperty == 'Contrast') {
      value = adj.contrast;
      min = 0.5;
      max = 1.5;
      displayValue = '${((value - 1.0) * 100).round()}';
    } else if (_activeProperty == 'Saturation') {
      value = adj.saturation;
      min = 0.0;
      max = 2.0;
      displayValue = '${((value - 1.0) * 100).round()}';
    } else if (_activeProperty == 'Exposure') {
      value = adj.exposure;
      displayValue = '${(value * 100).round()}';
    } else if (_activeProperty == 'Temperature') {
      value = adj.temperature;
      displayValue = '${(value * 100).round()}';
    } else if (_activeProperty == 'Vignette') {
      value = adj.vignette;
      min = 0.0;
      max = 1.0;
      displayValue = '${(value * 100).round()}%';
    }

    return Row(
      children: [
        SizedBox(
          width: 75,
          child: Text('$_activeProperty:', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: AppColors.primary,
            onChanged: (val) {
              if (_activeProperty == 'Brightness') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(brightness: val));
              } else if (_activeProperty == 'Contrast') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(contrast: val));
              } else if (_activeProperty == 'Saturation') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(saturation: val));
              } else if (_activeProperty == 'Exposure') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(exposure: val));
              } else if (_activeProperty == 'Temperature') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(temperature: val));
              } else if (_activeProperty == 'Vignette') {
                widget.viewModel.updateColorAdjustments(adj.copyWith(vignette: val));
              }
            },
          ),
        ),
        SizedBox(
          width: 40,
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
        onTap: () => setState(() => _activeProperty = name),
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
}
