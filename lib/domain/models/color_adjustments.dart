import 'package:flutter/material.dart';

/// Color adjustment parameters for fine-tuning video clips
class ColorAdjustments {
  final double brightness; // -1.0 to 1.0 (default 0.0)
  final double contrast; // 0.0 to 2.0 (default 1.0)
  final double saturation; // 0.0 to 2.0 (default 1.0)
  final double exposure; // -1.0 to 1.0 (default 0.0)
  final double temperature; // -1.0 (cool) to 1.0 (warm) (default 0.0)
  final double vignette; // 0.0 to 1.0 (default 0.0)

  const ColorAdjustments({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.exposure = 0.0,
    this.temperature = 0.0,
    this.vignette = 0.0,
  });

  bool get isDefault =>
      brightness == 0.0 &&
      contrast == 1.0 &&
      saturation == 1.0 &&
      exposure == 0.0 &&
      temperature == 0.0 &&
      vignette == 0.0;

  ColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? temperature,
    double? vignette,
  }) {
    return ColorAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      temperature: temperature ?? this.temperature,
      vignette: vignette ?? this.vignette,
    );
  }

  ColorFilter? getColorFilter() {
    if (isDefault) return null;

    final b = (brightness + exposure) * 50.0;
    final c = contrast;
    final s = saturation;
    final tempR = temperature > 0 ? temperature * 20.0 : 0.0;
    final tempB = temperature < 0 ? -temperature * 20.0 : 0.0;

    // Saturation matrix coefficients
    final lumR = 0.2126 * (1.0 - s);
    final lumG = 0.7152 * (1.0 - s);
    final lumB = 0.0722 * (1.0 - s);

    return ColorFilter.matrix(<double>[
      (lumR + s) * c, lumG * c, lumB * c, 0, b + tempR,
      lumR * c, (lumG + s) * c, lumB * c, 0, b,
      lumR * c, lumG * c, (lumB + s) * c, 0, b + tempB,
      0, 0, 0, 1, 0,
    ]);
  }

  Map<String, dynamic> toJson() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'exposure': exposure,
      'temperature': temperature,
      'vignette': vignette,
    };
  }

  factory ColorAdjustments.fromJson(Map<String, dynamic> json) {
    return ColorAdjustments(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
