import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/lut_config.dart';
import 'package:capcut_video_editor/domain/models/rgb_curves_model.dart';

/// Professional non-destructive color adjustment parameters for fine-tuning video clips and main video canvas
@immutable
class ColorAdjustments {
  // Basic Tonal & Exposure Controls
  final double brightness; // -1.0 to 1.0 (default 0.0)
  final double contrast; // 0.0 to 2.0 (default 1.0, neutral)
  final double saturation; // 0.0 to 2.0 (default 1.0, neutral)
  final double exposure; // -1.0 to 1.0 (default 0.0)

  // White Balance / Temperature & Tint
  final double temperature; // -1.0 (cool) to 1.0 (warm) (default 0.0)
  final double tint; // -1.0 (green) to 1.0 (magenta) (default 0.0)

  // Advanced Tone Mapping
  final double highlights; // -1.0 to 1.0 (default 0.0)
  final double shadows; // -1.0 to 1.0 (default 0.0)
  final double blacks; // -1.0 to 1.0 (default 0.0)
  final double whites; // -1.0 to 1.0 (default 0.0)

  // Lens & Optics Effects
  final double vignette; // 0.0 to 1.0 (default 0.0)
  final double vignetteRadius; // 0.1 to 1.5 (default 0.8)
  final double vignetteSoftness; // 0.01 to 1.0 (default 0.5)
  final double sharpness; // 0.0 to 1.0 (default 0.0)

  // Non-destructive Curves & LUT
  final RgbCurvesModel curves;
  final LutConfig? lut;

  const ColorAdjustments({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.exposure = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.blacks = 0.0,
    this.whites = 0.0,
    this.vignette = 0.0,
    this.vignetteRadius = 0.8,
    this.vignetteSoftness = 0.5,
    this.sharpness = 0.0,
    this.curves = RgbCurvesModel.identity,
    this.lut,
  });

  /// Invariant: check if adjustments represent pure identity/neutral state
  bool get isDefault =>
      brightness == 0.0 &&
      contrast == 1.0 &&
      saturation == 1.0 &&
      exposure == 0.0 &&
      temperature == 0.0 &&
      tint == 0.0 &&
      highlights == 0.0 &&
      shadows == 0.0 &&
      blacks == 0.0 &&
      whites == 0.0 &&
      vignette == 0.0 &&
      sharpness == 0.0 &&
      curves.isIdentity &&
      (lut == null || !lut!.isValid);

  ColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? blacks,
    double? whites,
    double? vignette,
    double? vignetteRadius,
    double? vignetteSoftness,
    double? sharpness,
    RgbCurvesModel? curves,
    LutConfig? lut,
    bool clearLut = false,
  }) {
    return ColorAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      blacks: blacks ?? this.blacks,
      whites: whites ?? this.whites,
      vignette: vignette ?? this.vignette,
      vignetteRadius: vignetteRadius ?? this.vignetteRadius,
      vignetteSoftness: vignetteSoftness ?? this.vignetteSoftness,
      sharpness: sharpness ?? this.sharpness,
      curves: curves ?? this.curves,
      lut: clearLut ? null : (lut ?? this.lut),
    );
  }

  /// Builds GPU Flutter ColorFilter matrix. Returns null if all controls are in neutral default state.
  ColorFilter? getColorFilter() {
    if (isDefault) return null;

    final b = (brightness + exposure) * 50.0;
    final c = contrast.clamp(0.0, 3.0);
    final s = saturation.clamp(0.0, 3.0);

    final tempR = temperature > 0 ? temperature * 25.0 : 0.0;
    final tempB = temperature < 0 ? -temperature * 25.0 : 0.0;
    final tintG = tint < 0 ? -tint * 20.0 : 0.0;
    final tintM = tint > 0 ? tint * 20.0 : 0.0;

    final highOffset = (highlights + whites) * 15.0;
    final shadowOffset = (shadows + blacks) * 15.0;
    final totalOffset = b + highOffset + shadowOffset;

    final lumR = 0.2126 * (1.0 - s);
    final lumG = 0.7152 * (1.0 - s);
    final lumB = 0.0722 * (1.0 - s);

    var rOffset = totalOffset + tempR + tintM;
    var gOffset = totalOffset + tintG;
    var bOffset = totalOffset + tempB + tintM;

    final cOffset = 128.0 * (1.0 - c);

    double rScale = 1.0;
    double gScale = 1.0;
    double bScale = 1.0;

    if (!curves.isIdentity) {
      final m0 = curves.evaluate(0.0, CurveChannel.master);
      final m1 = curves.evaluate(1.0, CurveChannel.master);
      final mMid = curves.evaluate(0.5, CurveChannel.master);
      final curveMasterGain = (m1 - m0).clamp(0.1, 3.0);
      final curveMasterOffset = (m0 * 255.0) + (mMid - (m0 + m1) * 0.5) * 128.0;

      final r0 = curves.evaluate(0.0, CurveChannel.red);
      final r1 = curves.evaluate(1.0, CurveChannel.red);
      final rMid = curves.evaluate(0.5, CurveChannel.red);
      final curveRGain = (r1 - r0).clamp(0.1, 3.0);
      final curveROffset = (r0 * 255.0) + (rMid - (r0 + r1) * 0.5) * 128.0;

      final g0 = curves.evaluate(0.0, CurveChannel.green);
      final g1 = curves.evaluate(1.0, CurveChannel.green);
      final gMid = curves.evaluate(0.5, CurveChannel.green);
      final curveGGain = (g1 - g0).clamp(0.1, 3.0);
      final curveGOffset = (g0 * 255.0) + (gMid - (g0 + g1) * 0.5) * 128.0;

      final b0 = curves.evaluate(0.0, CurveChannel.blue);
      final b1 = curves.evaluate(1.0, CurveChannel.blue);
      final bMid = curves.evaluate(0.5, CurveChannel.blue);
      final curveBGain = (b1 - b0).clamp(0.1, 3.0);
      final curveBOffset = (b0 * 255.0) + (bMid - (b0 + b1) * 0.5) * 128.0;

      rScale = curveMasterGain * curveRGain;
      gScale = curveMasterGain * curveGGain;
      bScale = curveMasterGain * curveBGain;

      rOffset += curveMasterOffset + curveROffset;
      gOffset += curveMasterOffset + curveGOffset;
      bOffset += curveMasterOffset + curveBOffset;
    }

    return ColorFilter.matrix(<double>[
      (lumR + s) * c * rScale, lumG * c * rScale, lumB * c * rScale, 0, rOffset + cOffset,
      lumR * c * gScale, (lumG + s) * c * gScale, lumB * c * gScale, 0, gOffset + cOffset,
      lumR * c * bScale, lumG * c * bScale, (lumB + s) * c * bScale, 0, bOffset + cOffset,
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
      'tint': tint,
      'highlights': highlights,
      'shadows': shadows,
      'blacks': blacks,
      'whites': whites,
      'vignette': vignette,
      'vignetteRadius': vignetteRadius,
      'vignetteSoftness': vignetteSoftness,
      'sharpness': sharpness,
      'curves': curves.toJson(),
      if (lut != null) 'lut': lut!.toJson(),
    };
  }

  factory ColorAdjustments.fromJson(Map<String, dynamic> json) {
    return ColorAdjustments(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      blacks: (json['blacks'] as num?)?.toDouble() ?? 0.0,
      whites: (json['whites'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      vignetteRadius: (json['vignetteRadius'] as num?)?.toDouble() ?? 0.8,
      vignetteSoftness: (json['vignetteSoftness'] as num?)?.toDouble() ?? 0.5,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      curves: json['curves'] != null
          ? RgbCurvesModel.fromJson(json['curves'] as Map<String, dynamic>)
          : RgbCurvesModel.identity,
      lut: json['lut'] != null
          ? LutConfig.fromJson(json['lut'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorAdjustments &&
          runtimeType == other.runtimeType &&
          brightness == other.brightness &&
          contrast == other.contrast &&
          saturation == other.saturation &&
          exposure == other.exposure &&
          temperature == other.temperature &&
          tint == other.tint &&
          highlights == other.highlights &&
          shadows == other.shadows &&
          blacks == other.blacks &&
          whites == other.whites &&
          vignette == other.vignette &&
          vignetteRadius == other.vignetteRadius &&
          vignetteSoftness == other.vignetteSoftness &&
          sharpness == other.sharpness &&
          curves == other.curves &&
          lut == other.lut;

  @override
  int get hashCode => Object.hashAll([
    brightness,
    contrast,
    saturation,
    exposure,
    temperature,
    tint,
    highlights,
    shadows,
    blacks,
    whites,
    vignette,
    vignetteRadius,
    vignetteSoftness,
    sharpness,
    curves,
    lut,
  ]);
}
