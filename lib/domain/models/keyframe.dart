import 'dart:math' as math;
import 'dart:ui' as ui;

/// Easing interpolation modes for keyframe transitions
enum InterpolationMode {
  hold,
  linear,
  easeIn,
  easeOut,
  easeInOut,
  cubicBezier,
}

/// Mode governing tangent handle synchronization across keyframe boundaries
enum TangentMode {
  /// Both tangent handles maintain symmetric collinear alignment (smooth C1 continuity)
  autoSmooth('Auto Smooth'),

  /// Tangent handles can move independently for sharp corners or bounces
  broken('Broken Corner'),

  /// Tangent handles are disabled (linear progression)
  linear('Linear');

  final String label;
  const TangentMode(this.label);
}

/// Professional easing curve specification supporting standard presets and cubic Bézier math
class EasingCurve {
  final InterpolationMode mode;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String? label;
  final TangentMode tangentMode;

  const EasingCurve({
    this.mode = InterpolationMode.easeInOut,
    this.x1 = 0.42,
    this.y1 = 0.0,
    this.x2 = 0.58,
    this.y2 = 1.0,
    this.label,
    this.tangentMode = TangentMode.autoSmooth,
  });

  String get displayName => label ?? mode.name;

  static const linear = EasingCurve(mode: InterpolationMode.linear, label: 'Linear', tangentMode: TangentMode.linear);
  static const hold = EasingCurve(mode: InterpolationMode.hold, label: 'Hold');
  static const easeIn = EasingCurve(mode: InterpolationMode.easeIn, x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0, label: 'Ease In');
  static const easeOut = EasingCurve(mode: InterpolationMode.easeOut, x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0, label: 'Ease Out');
  static const easeInOut = EasingCurve(mode: InterpolationMode.easeInOut, x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0, label: 'Ease In-Out');

  // Industry Standard Cubic Bézier Animation Presets
  static const easeInQuad = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.11, y1: 0.0, x2: 0.5, y2: 0.0, label: 'Ease In Quad');
  static const easeOutQuad = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.5, y1: 1.0, x2: 0.89, y2: 1.0, label: 'Ease Out Quad');
  static const easeInOutQuad = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.45, y1: 0.0, x2: 0.55, y2: 1.0, label: 'Ease In-Out Quad');

  static const easeInCubic = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.32, y1: 0.0, x2: 0.67, y2: 0.0, label: 'Ease In Cubic');
  static const easeOutCubic = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.33, y1: 1.0, x2: 0.68, y2: 1.0, label: 'Ease Out Cubic');
  static const easeInOutCubic = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.65, y1: 0.0, x2: 0.35, y2: 1.0, label: 'Ease In-Out Cubic');

  static const easeInBack = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.36, y1: 0.0, x2: 0.66, y2: -0.56, label: 'Ease In Back', tangentMode: TangentMode.broken);
  static const easeOutBack = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0, label: 'Ease Out Back', tangentMode: TangentMode.broken);
  static const easeInOutBack = EasingCurve(mode: InterpolationMode.cubicBezier, x1: 0.68, y1: -0.6, x2: 0.32, y2: 1.6, label: 'Ease In-Out Back', tangentMode: TangentMode.broken);

  static const List<EasingCurve> standardPresets = [
    linear,
    easeInOut,
    easeIn,
    easeOut,
    easeInQuad,
    easeOutQuad,
    easeInOutQuad,
    easeInCubic,
    easeOutCubic,
    easeInOutCubic,
    easeInBack,
    easeOutBack,
    easeInOutBack,
    hold,
  ];

  factory EasingCurve.cubic(
    double x1,
    double y1,
    double x2,
    double y2, {
    String label = 'Custom Bézier',
    TangentMode tangentMode = TangentMode.autoSmooth,
  }) {
    return EasingCurve(
      mode: InterpolationMode.cubicBezier,
      x1: x1.clamp(0.0, 1.0),
      y1: y1,
      x2: x2.clamp(0.0, 1.0),
      y2: y2,
      label: label,
      tangentMode: tangentMode,
    );
  }

  EasingCurve copyWith({
    InterpolationMode? mode,
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    String? label,
    TangentMode? tangentMode,
  }) {
    return EasingCurve(
      mode: mode ?? this.mode,
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      label: label ?? this.label,
      tangentMode: tangentMode ?? this.tangentMode,
    );
  }

  /// Evaluates normalized curve progression [0.0, 1.0] given time progress [0.0, 1.0]
  double evaluate(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    switch (mode) {
      case InterpolationMode.hold:
        return clampedT >= 1.0 ? 1.0 : 0.0;
      case InterpolationMode.linear:
        return clampedT;
      case InterpolationMode.easeIn:
        return clampedT * clampedT * clampedT;
      case InterpolationMode.easeOut:
        return 1.0 - math.pow(1.0 - clampedT, 3).toDouble();
      case InterpolationMode.easeInOut:
        return clampedT < 0.5
            ? 4.0 * clampedT * clampedT * clampedT
            : 1.0 - math.pow(-2.0 * clampedT + 2.0, 3) / 2.0;
      case InterpolationMode.cubicBezier:
        return _evaluateCubicBezier(clampedT);
    }
  }

  /// Evaluates instantaneous rate of change dy/dt given time progress [0.0, 1.0]
  double evaluateDerivative(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    switch (mode) {
      case InterpolationMode.hold:
        return 0.0;
      case InterpolationMode.linear:
        return 1.0;
      case InterpolationMode.easeIn:
        return 3.0 * clampedT * clampedT;
      case InterpolationMode.easeOut:
        final inv = 1.0 - clampedT;
        return 3.0 * inv * inv;
      case InterpolationMode.easeInOut:
        if (clampedT < 0.5) {
          return 12.0 * clampedT * clampedT;
        } else {
          final inv = 1.0 - clampedT;
          return 12.0 * inv * inv;
        }
      case InterpolationMode.cubicBezier:
        return _evaluateCubicBezierDerivative(clampedT);
    }
  }

  /// Alias for evaluate to match motion physics solvers
  double solve(double t) => evaluate(t);

  /// Solves parametric cubic parameter s in [0.0, 1.0] where X(s) == t
  double _solveCubicParameter(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;

    // Fast initial guess with Newton-Raphson
    double s = t;
    for (int i = 0; i < 8; i++) {
      final currentX = _sampleCurveX(s) - t;
      if (currentX.abs() < 1e-6) {
        return s;
      }
      final dx = _sampleCurveDerivativeX(s);
      if (dx.abs() < 1e-6) break;
      s -= currentX / dx;
      if (s < 0.0 || s > 1.0) break; // Diverged out of unit range, fallback to bisection
    }

    // Binary subdivision fallback guarantees convergence for steep curves or flat tangents
    double low = 0.0;
    double high = 1.0;
    s = t;
    for (int i = 0; i < 16; i++) {
      final currentX = _sampleCurveX(s);
      if ((currentX - t).abs() < 1e-6) break;
      if (t > currentX) {
        low = s;
      } else {
        high = s;
      }
      s = (high + low) * 0.5;
    }
    return s;
  }

  /// Standard Newton-Raphson cubic Bézier solver with guaranteed binary subdivision fallback
  double _evaluateCubicBezier(double t) {
    final s = _solveCubicParameter(t);
    return _sampleCurveY(s);
  }

  /// Computes dy/dx derivative for cubic Bézier at time t
  double _evaluateCubicBezierDerivative(double t) {
    final s = _solveCubicParameter(t);
    final dx = _sampleCurveDerivativeX(s);
    final dy = _sampleCurveDerivativeY(s);
    if (dx.abs() < 1e-6) {
      return dy >= 0 ? 100.0 : -100.0;
    }
    return (dy / dx).clamp(-100.0, 100.0);
  }

  double _sampleCurveX(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * x1 +
           3.0 * (1.0 - t) * t * t * x2 +
           t * t * t;
  }

  double _sampleCurveDerivativeX(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * x1 +
           6.0 * (1.0 - t) * t * (x2 - x1) +
           3.0 * t * t * (1.0 - x2);
  }

  double _sampleCurveY(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * y1 +
           3.0 * (1.0 - t) * t * t * y2 +
           t * t * t;
  }

  double _sampleCurveDerivativeY(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * y1 +
           6.0 * (1.0 - t) * t * (y2 - y1) +
           3.0 * t * t * (1.0 - y2);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'label': label,
    'tangentMode': tangentMode.name,
  };

  factory EasingCurve.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? 'easeInOut';
    final mode = InterpolationMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => InterpolationMode.easeInOut,
    );
    final tangentModeName = json['tangentMode'] as String? ?? 'autoSmooth';
    final tangentMode = TangentMode.values.firstWhere(
      (m) => m.name == tangentModeName,
      orElse: () => TangentMode.autoSmooth,
    );
    return EasingCurve(
      mode: mode,
      x1: (json['x1'] as num?)?.toDouble() ?? 0.42,
      y1: (json['y1'] as num?)?.toDouble() ?? 0.0,
      x2: (json['x2'] as num?)?.toDouble() ?? 0.58,
      y2: (json['y2'] as num?)?.toDouble() ?? 1.0,
      label: json['label'] as String?,
      tangentMode: tangentMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EasingCurve &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          x1 == other.x1 &&
          y1 == other.y1 &&
          x2 == other.x2 &&
          y2 == other.y2 &&
          tangentMode == other.tangentMode;

  @override
  int get hashCode =>
      mode.hashCode ^
      x1.hashCode ^
      y1.hashCode ^
      x2.hashCode ^
      y2.hashCode ^
      tangentMode.hashCode;
}

/// Easing interpolation curves for keyframe transitions (Legacy Enum with Enhanced Evaluation)
enum KeyframeCurve {
  linear('Linear'),
  easeInOut('Ease In-Out'),
  easeIn('Ease In'),
  easeOut('Ease Out'),
  hold('Hold');

  final String label;
  const KeyframeCurve(this.label);

  /// Evaluates the normalized curve progression [0.0, 1.0]
  double evaluate(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    switch (this) {
      case KeyframeCurve.hold:
        return clampedT >= 1.0 ? 1.0 : 0.0;
      case KeyframeCurve.linear:
        return clampedT;
      case KeyframeCurve.easeInOut:
        return clampedT < 0.5
            ? 4.0 * clampedT * clampedT * clampedT
            : 1.0 - math.pow(-2.0 * clampedT + 2.0, 3) / 2.0;
      case KeyframeCurve.easeIn:
        return clampedT * clampedT * clampedT;
      case KeyframeCurve.easeOut:
        return 1.0 - math.pow(1.0 - clampedT, 3).toDouble();
    }
  }

  EasingCurve toEasingCurve() {
    switch (this) {
      case KeyframeCurve.linear:
        return EasingCurve.linear;
      case KeyframeCurve.hold:
        return EasingCurve.hold;
      case KeyframeCurve.easeIn:
        return EasingCurve.easeIn;
      case KeyframeCurve.easeOut:
        return EasingCurve.easeOut;
      case KeyframeCurve.easeInOut:
        return EasingCurve.easeInOut;
    }
  }

  static KeyframeCurve fromEasingCurve(EasingCurve curve) {
    switch (curve.mode) {
      case InterpolationMode.linear:
        return KeyframeCurve.linear;
      case InterpolationMode.hold:
        return KeyframeCurve.hold;
      case InterpolationMode.easeIn:
        return KeyframeCurve.easeIn;
      case InterpolationMode.easeOut:
        return KeyframeCurve.easeOut;
      case InterpolationMode.easeInOut:
      case InterpolationMode.cubicBezier:
        return KeyframeCurve.easeInOut;
    }
  }
}

/// Enumeration of animatable properties across the timeline engine
enum AnimatableProperty {
  // Transform
  positionX('Position X', 'px', 0.0, -3000.0, 3000.0),
  positionY('Position Y', 'px', 0.0, -3000.0, 3000.0),
  scale('Scale', 'x', 1.0, 0.05, 10.0),
  rotation('Rotation', '°', 0.0, -3600.0, 3600.0), // Continuous angle support

  // Visual
  opacity('Opacity', '%', 1.0, 0.0, 1.0),

  // Color Adjustments
  brightness('Brightness', '', 0.0, -1.0, 1.0),
  contrast('Contrast', '', 0.0, -1.0, 1.0),
  saturation('Saturation', '', 0.0, -1.0, 1.0),
  exposure('Exposure', '', 0.0, -1.0, 1.0),
  temperature('Temperature', '', 0.0, -1.0, 1.0),
  tint('Tint', '', 0.0, -1.0, 1.0),
  highlights('Highlights', '', 0.0, -1.0, 1.0),
  shadows('Shadows', '', 0.0, -1.0, 1.0),
  blacks('Blacks', '', 0.0, -1.0, 1.0),
  whites('Whites', '', 0.0, -1.0, 1.0),
  vignette('Vignette', '', 0.0, 0.0, 1.0),
  sharpness('Sharpness', '', 0.0, 0.0, 1.0),
  filterIntensity('Filter Intensity', '%', 1.0, 0.0, 1.0),
  effectIntensity('Effect Intensity', '%', 1.0, 0.0, 1.0),

  // PIP Specific
  cropLeft('Crop Left', '%', 0.0, 0.0, 1.0),
  cropTop('Crop Top', '%', 0.0, 0.0, 1.0),
  cropWidth('Crop Width', '%', 1.0, 0.0, 1.0),
  cropHeight('Crop Height', '%', 1.0, 0.0, 1.0),
  blendOpacity('Blend Opacity', '%', 1.0, 0.0, 1.0),

  // Audio Specific
  volume('Volume', '%', 1.0, 0.0, 2.0),

  // Mask Specific
  maskPositionX('Mask Position X', '', 0.0, -3.0, 3.0),
  maskPositionY('Mask Position Y', '', 0.0, -3.0, 3.0),
  maskScale('Mask Scale', 'x', 1.0, 0.05, 10.0),
  maskRotation('Mask Rotation', '°', 0.0, -3600.0, 3600.0),
  maskOpacity('Mask Opacity', '%', 1.0, 0.0, 1.0),
  maskFeather('Mask Feather', 'px', 0.0, 0.0, 100.0),
  maskExpansion('Mask Expansion', 'px', 0.0, -100.0, 100.0),
  maskWidth('Mask Width', '%', 0.5, 0.01, 2.0),
  maskHeight('Mask Height', '%', 0.5, 0.01, 2.0);

  // Alias for sharpen / sharpness compatibility
  static AnimatableProperty get sharpen => AnimatableProperty.sharpness;

  final String label;
  final String unit;
  final double defaultValue;
  final double minValue;
  final double maxValue;

  const AnimatableProperty(
    this.label,
    this.unit,
    this.defaultValue,
    this.minValue,
    this.maxValue,
  );

  bool get isTransform =>
      this == AnimatableProperty.positionX ||
      this == AnimatableProperty.positionY ||
      this == AnimatableProperty.scale ||
      this == AnimatableProperty.rotation;

  bool get isVisual => this == AnimatableProperty.opacity;

  bool get isColor =>
      this == AnimatableProperty.brightness ||
      this == AnimatableProperty.contrast ||
      this == AnimatableProperty.saturation ||
      this == AnimatableProperty.exposure ||
      this == AnimatableProperty.temperature ||
      this == AnimatableProperty.tint ||
      this == AnimatableProperty.highlights ||
      this == AnimatableProperty.shadows ||
      this == AnimatableProperty.blacks ||
      this == AnimatableProperty.whites ||
      this == AnimatableProperty.vignette ||
      this == AnimatableProperty.sharpness ||
      this == AnimatableProperty.filterIntensity ||
      this == AnimatableProperty.effectIntensity;

  bool get isAudio => this == AnimatableProperty.volume;

  bool get isMask =>
      this == AnimatableProperty.maskPositionX ||
      this == AnimatableProperty.maskPositionY ||
      this == AnimatableProperty.maskScale ||
      this == AnimatableProperty.maskRotation ||
      this == AnimatableProperty.maskOpacity ||
      this == AnimatableProperty.maskFeather ||
      this == AnimatableProperty.maskExpansion ||
      this == AnimatableProperty.maskWidth ||
      this == AnimatableProperty.maskHeight;

  double sanitize(double val) {
    if (val.isNaN || val.isInfinite) return defaultValue;
    return val.clamp(minValue, maxValue);
  }
}

/// Represents a single property keyframe with integer millisecond precision
class MotionKeyframe {
  final String id;
  final int timestampMs; // Authoritative integer time unit
  final double value;
  final EasingCurve easing;

  const MotionKeyframe({
    required this.id,
    required this.timestampMs,
    required this.value,
    this.easing = EasingCurve.easeInOut,
  });

  double get timeInSeconds => timestampMs / 1000.0;
  Duration get timestamp => Duration(milliseconds: timestampMs);

  MotionKeyframe copyWith({
    String? id,
    int? timestampMs,
    double? value,
    EasingCurve? easing,
  }) {
    return MotionKeyframe(
      id: id ?? this.id,
      timestampMs: timestampMs ?? this.timestampMs,
      value: value ?? this.value,
      easing: easing ?? this.easing,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestampMs,
    'value': value,
    'easing': easing.toJson(),
  };

  factory MotionKeyframe.fromJson(Map<String, dynamic> json) {
    final rawVal = (json['value'] as num?)?.toDouble() ?? 0.0;
    final sanitizedVal = (rawVal.isNaN || rawVal.isInfinite) ? 0.0 : rawVal;
    final ms = (json['timestampMs'] as num?)?.toInt() ?? 0;

    EasingCurve easing = EasingCurve.easeInOut;
    if (json['easing'] is Map<String, dynamic>) {
      easing = EasingCurve.fromJson(json['easing'] as Map<String, dynamic>);
    } else if (json['easing'] is String) {
      final name = json['easing'] as String;
      final mode = InterpolationMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => InterpolationMode.easeInOut,
      );
      easing = EasingCurve(mode: mode);
    }

    return MotionKeyframe(
      id: json['id'] as String? ?? 'mkf_${DateTime.now().millisecondsSinceEpoch}',
      timestampMs: ms.clamp(0, 86400000), // Max 24 hours
      value: sanitizedVal,
      easing: easing,
    );
  }

  @override
  String toString() =>
      'MotionKeyframe(id: $id, time: ${timeInSeconds}s, val: $value, easing: ${easing.displayName})';
}

/// Deterministic, sorted track of keyframes for a single animatable property
class KeyframeTrack {
  final AnimatableProperty property;
  final List<MotionKeyframe> keyframes;
  final double? defaultValue;

  const KeyframeTrack({
    required this.property,
    this.keyframes = const [],
    this.defaultValue,
  });

  double get effectiveDefaultValue => defaultValue ?? property.defaultValue;

  bool get isEmpty => keyframes.isEmpty;
  bool get isNotEmpty => keyframes.isNotEmpty;
  int get length => keyframes.length;

  /// Pure deterministic evaluation function using binary search O(log N)
  double evaluate(double timeInSeconds) {
    if (keyframes.isEmpty) return effectiveDefaultValue;
    if (keyframes.length == 1) return property.sanitize(keyframes.first.value);

    final timeMs = (timeInSeconds * 1000).round();

    // Boundary checks
    if (timeMs <= keyframes.first.timestampMs) {
      return property.sanitize(keyframes.first.value);
    }
    if (timeMs >= keyframes.last.timestampMs) {
      return property.sanitize(keyframes.last.value);
    }

    // Binary search for bounding interval [k_i, k_{i+1}]
    int low = 0;
    int high = keyframes.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (keyframes[mid].timestampMs <= timeMs) {
        if (mid == keyframes.length - 1 || keyframes[mid + 1].timestampMs > timeMs) {
          final k1 = keyframes[mid];
          final k2 = keyframes[mid + 1];
          final durationMs = k2.timestampMs - k1.timestampMs;
          if (durationMs <= 0) return property.sanitize(k1.value);

          final progress = (timeMs - k1.timestampMs) / durationMs;
          final easedProgress = k1.easing.evaluate(progress);

          // Interpolation logic
          final val = _interpolate(k1.value, k2.value, easedProgress);
          return property.sanitize(val);
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return property.sanitize(keyframes.last.value);
  }

  /// Evaluates instantaneous rate of change (velocity) in property units per second
  double evaluateDerivative(double timeInSeconds) {
    if (keyframes.length <= 1) return 0.0;

    final timeMs = (timeInSeconds * 1000).round();

    // Outside keyframe range, velocity is zero (held value)
    if (timeMs <= keyframes.first.timestampMs || timeMs >= keyframes.last.timestampMs) {
      return 0.0;
    }

    // Binary search for bounding interval [k_i, k_{i+1}]
    int low = 0;
    int high = keyframes.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (keyframes[mid].timestampMs <= timeMs) {
        if (mid == keyframes.length - 1 || keyframes[mid + 1].timestampMs > timeMs) {
          final k1 = keyframes[mid];
          final k2 = keyframes[mid + 1];
          final durationSec = (k2.timestampMs - k1.timestampMs) / 1000.0;
          if (durationSec <= 1e-4) return 0.0;

          final progress = (timeMs - k1.timestampMs) / (k2.timestampMs - k1.timestampMs);
          final deltaVal = k2.value - k1.value;
          final easeDeriv = k1.easing.evaluateDerivative(progress);

          return (deltaVal / durationSec) * easeDeriv;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return 0.0;
  }

  /// Updates keyframe value at existing timestamp without changing easing or reordering
  KeyframeTrack updateKeyframeValueAt(int timeMs, double value, {int toleranceMs = 80}) {
    final sanitizedVal = property.sanitize(value);
    final idx = keyframes.indexWhere((k) => (k.timestampMs - timeMs).abs() <= toleranceMs);
    if (idx < 0) return this;

    final updated = List<MotionKeyframe>.from(keyframes);
    updated[idx] = updated[idx].copyWith(value: sanitizedVal);
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Updates keyframe easing at existing timestamp
  KeyframeTrack updateKeyframeEasingAt(int timeMs, EasingCurve easing, {int toleranceMs = 80}) {
    final idx = keyframes.indexWhere((k) => (k.timestampMs - timeMs).abs() <= toleranceMs);
    if (idx < 0) return this;

    final updated = List<MotionKeyframe>.from(keyframes);
    updated[idx] = updated[idx].copyWith(easing: easing);
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  double _interpolate(double v1, double v2, double t) {
    if (property == AnimatableProperty.rotation) {
      // Continuous rotation interpolation preserving full multi-turn revolutions
      return v1 + (v2 - v1) * t;
    }
    return v1 + (v2 - v1) * t;
  }

  /// Adds or updates a keyframe at the target timestamp (replaces if within tolerance)
  KeyframeTrack addOrUpdate(int timeMs, double value, {EasingCurve? easing, int toleranceMs = 50}) {
    final sanitizedVal = property.sanitize(value);
    final sanitizedTimeMs = timeMs.clamp(0, 86400000);
    final curve = easing ?? EasingCurve.easeInOut;

    final updated = List<MotionKeyframe>.from(keyframes);
    final existingIdx = updated.indexWhere((k) => (k.timestampMs - sanitizedTimeMs).abs() <= toleranceMs);

    if (existingIdx >= 0) {
      updated[existingIdx] = updated[existingIdx].copyWith(
        timestampMs: sanitizedTimeMs,
        value: sanitizedVal,
        easing: curve,
      );
    } else {
      updated.add(MotionKeyframe(
        id: 'mkf_${DateTime.now().millisecondsSinceEpoch}_${property.name}',
        timestampMs: sanitizedTimeMs,
        value: sanitizedVal,
        easing: curve,
      ));
    }
    updated.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Removes a keyframe within toleranceMs of target timestamp
  KeyframeTrack removeAt(int timeMs, {int toleranceMs = 80}) {
    final updated = keyframes.where((k) => (k.timestampMs - timeMs).abs() > toleranceMs).toList();
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Finds keyframe within toleranceMs of target timestamp
  MotionKeyframe? getKeyframeAt(int timeMs, {int toleranceMs = 80}) {
    for (final k in keyframes) {
      if ((k.timestampMs - timeMs).abs() <= toleranceMs) {
        return k;
      }
    }
    return null;
  }

  /// Finds keyframe at or immediately before timeMs (for segment easing evaluation)
  MotionKeyframe? getKeyframeAtOrBefore(int timeMs, {int toleranceMs = 80}) {
    final direct = getKeyframeAt(timeMs, toleranceMs: toleranceMs);
    if (direct != null) return direct;
    MotionKeyframe? best;
    for (final k in keyframes) {
      if (k.timestampMs <= timeMs) {
        best = k;
      } else {
        break;
      }
    }
    return best ?? (keyframes.isNotEmpty ? keyframes.first : null);
  }

  /// Removes a keyframe by its unique ID
  KeyframeTrack removeById(String id) {
    final updated = keyframes.where((k) => k.id != id).toList();
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Clamps track to a maximum duration, discarding out-of-bounds keyframes
  KeyframeTrack clampToDuration(int maxDurationMs) {
    final updated = keyframes.where((k) => k.timestampMs <= maxDurationMs).toList();
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Splits track at splitTimeMs into two parts:
  /// Part A: [0, splitTimeMs] (with boundary keyframe at splitTimeMs preserving evaluated value)
  /// Part B: shifted by splitTimeMs (timestamps start at 0)
  (KeyframeTrack partA, KeyframeTrack partB) splitAt(int splitTimeMs) {
    if (keyframes.isEmpty) {
      return (KeyframeTrack(property: property), KeyframeTrack(property: property));
    }

    final splitSec = splitTimeMs / 1000.0;
    final splitVal = evaluate(splitSec);

    final kfA = <MotionKeyframe>[];
    for (final k in keyframes) {
      if (k.timestampMs < splitTimeMs) {
        kfA.add(k);
      }
    }
    // Ensure boundary value at splitTimeMs
    kfA.add(MotionKeyframe(
      id: 'kf_${DateTime.now().millisecondsSinceEpoch}_splA',
      timestampMs: splitTimeMs,
      value: splitVal,
    ));

    final kfB = <MotionKeyframe>[];
    // Boundary value at 0ms in part B
    kfB.add(MotionKeyframe(
      id: 'kf_${DateTime.now().millisecondsSinceEpoch}_splB',
      timestampMs: 0,
      value: splitVal,
    ));
    for (final k in keyframes) {
      if (k.timestampMs > splitTimeMs) {
        kfB.add(k.copyWith(
          timestampMs: k.timestampMs - splitTimeMs,
        ));
      }
    }

    return (
      KeyframeTrack(property: property, keyframes: kfA, defaultValue: defaultValue),
      KeyframeTrack(property: property, keyframes: kfB, defaultValue: defaultValue),
    );
  }

  /// Duplicates track with fresh unique keyframe IDs
  KeyframeTrack duplicate() {
    final duplicated = keyframes.map((k) => k.copyWith(
      id: 'kf_${DateTime.now().microsecondsSinceEpoch}_${k.timestampMs}',
    )).toList();
    return KeyframeTrack(property: property, keyframes: duplicated, defaultValue: defaultValue);
  }

  /// Shifts all keyframes by offsetMs, ensuring timestamps do not drop below minTimeMs
  KeyframeTrack shiftTime(int offsetMs, {int minTimeMs = 0}) {
    if (keyframes.isEmpty || offsetMs == 0) return this;
    final updated = keyframes.map((k) {
      final newTime = (k.timestampMs + offsetMs).clamp(minTimeMs, 86400000);
      return k.copyWith(timestampMs: newTime);
    }).toList();
    updated.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Scales keyframe spacing relative to originMs by a positive factor
  KeyframeTrack scaleTime(double factor, {int originMs = 0}) {
    if (keyframes.isEmpty || factor <= 0.0) return this;
    final updated = keyframes.map((k) {
      final dt = k.timestampMs - originMs;
      final newTime = (originMs + (dt * factor).round()).clamp(0, 86400000);
      return k.copyWith(timestampMs: newTime);
    }).toList();
    updated.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  /// Applies a specified easing curve to all keyframes on this track
  KeyframeTrack applyEasingToAll(EasingCurve easing) {
    if (keyframes.isEmpty) return this;
    final updated = keyframes.map((k) => k.copyWith(easing: easing)).toList();
    return KeyframeTrack(property: property, keyframes: updated, defaultValue: defaultValue);
  }

  Map<String, dynamic> toJson() => {
    'property': property.name,
    'defaultValue': defaultValue,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };

  factory KeyframeTrack.fromJson(Map<String, dynamic> json) {
    final propName = json['property'] as String? ?? 'scale';
    final prop = AnimatableProperty.values.firstWhere(
      (p) => p.name == propName,
      orElse: () => AnimatableProperty.scale,
    );
    final defVal = (json['defaultValue'] as num?)?.toDouble() ?? prop.defaultValue;
    final rawKeyframes = (json['keyframes'] as List<dynamic>?)
            ?.map((k) => MotionKeyframe.fromJson(k as Map<String, dynamic>))
            .toList() ??
        [];
    rawKeyframes.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return KeyframeTrack(
      property: prop,
      defaultValue: defVal,
      keyframes: rawKeyframes,
    );
  }
}

/// Unified multi-track animation container attachable to any timeline layer
class KeyframeTrackGroup {
  final Map<AnimatableProperty, KeyframeTrack> tracks;

  const KeyframeTrackGroup({
    this.tracks = const {},
  });

  bool get isEmpty => tracks.values.every((t) => t.isEmpty);
  bool get isNotEmpty => !isEmpty;
  int get totalKeyframeCount => tracks.values.fold(0, (sum, t) => sum + t.length);

  /// Checks whether a track exists and has at least one keyframe
  bool hasProperty(AnimatableProperty property) {
    final track = tracks[property];
    return track != null && track.isNotEmpty;
  }

  /// Evaluates an individual property at timeInSeconds
  double evaluate(AnimatableProperty property, double timeInSeconds, {double? fallback}) {
    final track = tracks[property];
    if (track == null || track.isEmpty) return fallback ?? property.defaultValue;
    return track.evaluate(timeInSeconds);
  }

  /// Evaluates instantaneous velocity (rate of change) for a property at timeInSeconds
  double evaluateDerivative(AnimatableProperty property, double timeInSeconds) {
    final track = tracks[property];
    if (track == null || track.isEmpty) return 0.0;
    return track.evaluateDerivative(timeInSeconds);
  }

  /// Updates keyframe value at target timestamp for property without altering curve or timing
  KeyframeTrackGroup updateKeyframeValueAt(
    AnimatableProperty property,
    int timeMs,
    double value, {
    int toleranceMs = 80,
  }) {
    final track = tracks[property];
    if (track == null) return this;
    final updatedTracks = Map<AnimatableProperty, KeyframeTrack>.from(tracks);
    updatedTracks[property] = track.updateKeyframeValueAt(timeMs, value, toleranceMs: toleranceMs);
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Shifts all tracks by offsetMs
  KeyframeTrackGroup shiftTime(int offsetMs, {int minTimeMs = 0}) {
    final updatedTracks = <AnimatableProperty, KeyframeTrack>{};
    for (final entry in tracks.entries) {
      updatedTracks[entry.key] = entry.value.shiftTime(offsetMs, minTimeMs: minTimeMs);
    }
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Scales all tracks relative to originMs
  KeyframeTrackGroup scaleTime(double factor, {int originMs = 0}) {
    final updatedTracks = <AnimatableProperty, KeyframeTrack>{};
    for (final entry in tracks.entries) {
      updatedTracks[entry.key] = entry.value.scaleTime(factor, originMs: originMs);
    }
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Applies easing to a specific property's track
  KeyframeTrackGroup applyEasingToProperty(AnimatableProperty property, EasingCurve easing) {
    final track = tracks[property];
    if (track == null) return this;
    final updatedTracks = Map<AnimatableProperty, KeyframeTrack>.from(tracks);
    updatedTracks[property] = track.applyEasingToAll(easing);
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Evaluates all configured tracks at timeInSeconds
  Map<AnimatableProperty, double> evaluateAll(double timeInSeconds) {
    final result = <AnimatableProperty, double>{};
    for (final prop in AnimatableProperty.values) {
      result[prop] = evaluate(prop, timeInSeconds);
    }
    return result;
  }

  /// Returns sorted unique timestamps in milliseconds across all tracks
  List<int> getAllTimestampsMs() {
    final set = <int>{};
    for (final track in tracks.values) {
      for (final kf in track.keyframes) {
        set.add(kf.timestampMs);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Checks if any track has a keyframe at or near target time
  bool hasKeyframeAt(int timeMs, {int toleranceMs = 80}) {
    for (final track in tracks.values) {
      if (track.keyframes.any((k) => (k.timestampMs - timeMs).abs() <= toleranceMs)) {
        return true;
      }
    }
    return false;
  }

  /// Adds a keyframe for a single property
  KeyframeTrackGroup addKeyframe(AnimatableProperty property, int timeMs, double value, {EasingCurve? easing}) {
    final updatedTracks = Map<AnimatableProperty, KeyframeTrack>.from(tracks);
    final track = updatedTracks[property] ?? KeyframeTrack(property: property);
    updatedTracks[property] = track.addOrUpdate(timeMs, value, easing: easing);
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Adds a full spatial transform keyframe bundle at timeMs
  KeyframeTrackGroup addTransformKeyframe({
    required int timeMs,
    required double posX,
    required double posY,
    required double scale,
    required double rotation,
    required double opacity,
    EasingCurve? easing,
  }) {
    var group = addKeyframe(AnimatableProperty.positionX, timeMs, posX, easing: easing);
    group = group.addKeyframe(AnimatableProperty.positionY, timeMs, posY, easing: easing);
    group = group.addKeyframe(AnimatableProperty.scale, timeMs, scale, easing: easing);
    group = group.addKeyframe(AnimatableProperty.rotation, timeMs, rotation, easing: easing);
    group = group.addKeyframe(AnimatableProperty.opacity, timeMs, opacity, easing: easing);
    return group;
  }

  /// Updates easing curve at timeMs across all active transform tracks (scale, pos, rot, opacity)
  KeyframeTrackGroup updateEasingForTransformProperties(
    int timeMs,
    EasingCurve easing, {
    int toleranceMs = 80,
  }) {
    final updatedTracks = Map<AnimatableProperty, KeyframeTrack>.from(tracks);
    for (final prop in const [
      AnimatableProperty.scale,
      AnimatableProperty.positionX,
      AnimatableProperty.positionY,
      AnimatableProperty.rotation,
      AnimatableProperty.opacity,
    ]) {
      final track = updatedTracks[prop];
      if (track != null) {
        final kf = track.getKeyframeAt(timeMs, toleranceMs: toleranceMs);
        if (kf != null) {
          updatedTracks[prop] = track.addOrUpdate(
            kf.timestampMs,
            kf.value,
            easing: easing,
            toleranceMs: toleranceMs,
          );
        }
      }
    }
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Removes all keyframes near timeMs across all tracks
  KeyframeTrackGroup removeKeyframeAtTime(int timeMs, {int toleranceMs = 80}) {
    final updatedTracks = <AnimatableProperty, KeyframeTrack>{};
    for (final entry in tracks.entries) {
      updatedTracks[entry.key] = entry.value.removeAt(timeMs, toleranceMs: toleranceMs);
    }
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Clamps all tracks to layer duration
  KeyframeTrackGroup clampToDuration(int maxDurationMs) {
    final updatedTracks = <AnimatableProperty, KeyframeTrack>{};
    for (final entry in tracks.entries) {
      updatedTracks[entry.key] = entry.value.clampToDuration(maxDurationMs);
    }
    return KeyframeTrackGroup(tracks: updatedTracks);
  }

  /// Splits all tracks at splitTimeMs
  (KeyframeTrackGroup partA, KeyframeTrackGroup partB) splitAt(int splitTimeMs) {
    final tracksA = <AnimatableProperty, KeyframeTrack>{};
    final tracksB = <AnimatableProperty, KeyframeTrack>{};

    for (final entry in tracks.entries) {
      final (tA, tB) = entry.value.splitAt(splitTimeMs);
      tracksA[entry.key] = tA;
      tracksB[entry.key] = tB;
    }

    return (
      KeyframeTrackGroup(tracks: tracksA),
      KeyframeTrackGroup(tracks: tracksB),
    );
  }

  /// Duplicates all tracks with fresh unique keyframe IDs
  KeyframeTrackGroup duplicate() {
    final dupTracks = <AnimatableProperty, KeyframeTrack>{};
    for (final entry in tracks.entries) {
      dupTracks[entry.key] = entry.value.duplicate();
    }
    return KeyframeTrackGroup(tracks: dupTracks);
  }

  /// Converts legacy List<VideoKeyframe> into a unified KeyframeTrackGroup
  static KeyframeTrackGroup fromVideoKeyframes(List<VideoKeyframe> keyframes) {
    if (keyframes.isEmpty) return const KeyframeTrackGroup();

    var group = const KeyframeTrackGroup();
    for (final kf in keyframes) {
      final ms = kf.timestamp.inMilliseconds;
      final easing = kf.curve.toEasingCurve();
      group = group.addTransformKeyframe(
        timeMs: ms,
        posX: kf.positionX,
        posY: kf.positionY,
        scale: kf.scale,
        rotation: kf.rotationDegrees,
        opacity: kf.opacity,
        easing: easing,
      );
    }
    return group;
  }

  /// Converts transform tracks back to legacy List<VideoKeyframe> for backward compatibility
  List<VideoKeyframe> toVideoKeyframes() {
    final times = getAllTimestampsMs();
    if (times.isEmpty) return const [];

    return times.map((ms) {
      final timeSec = ms / 1000.0;
      final x = evaluate(AnimatableProperty.positionX, timeSec);
      final y = evaluate(AnimatableProperty.positionY, timeSec);
      final s = evaluate(AnimatableProperty.scale, timeSec);
      final r = evaluate(AnimatableProperty.rotation, timeSec);
      final op = evaluate(AnimatableProperty.opacity, timeSec);

      // Determine curve from transform tracks (check scale, position, rotation, opacity)
      MotionKeyframe? foundKf;
      for (final prop in const [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
      ]) {
        final track = tracks[prop];
        if (track != null) {
          final candidate = track.getKeyframeAt(ms, toleranceMs: 50);
          if (candidate != null) {
            foundKf ??= candidate;
            // If candidate has non-default or customized curve, prioritize it
            if (candidate.easing.mode != InterpolationMode.easeInOut || candidate.easing != EasingCurve.easeInOut) {
              foundKf = candidate;
              break;
            }
          }
        }
      }
      final curve = KeyframeCurve.fromEasingCurve(foundKf?.easing ?? EasingCurve.easeInOut);

      return VideoKeyframe(
        id: 'kf_$ms',
        timestamp: Duration(milliseconds: ms),
        scale: s,
        rotationDegrees: r,
        positionX: x,
        positionY: y,
        opacity: op,
        curve: curve,
      );
    }).toList();
  }

  Map<String, dynamic> toJson() => {
    'tracks': tracks.map((key, value) => MapEntry(key.name, value.toJson())),
  };

  factory KeyframeTrackGroup.fromJson(Map<String, dynamic> json) {
    final tracksMap = <AnimatableProperty, KeyframeTrack>{};
    if (json['tracks'] is Map<String, dynamic>) {
      final rawMap = json['tracks'] as Map<String, dynamic>;
      for (final entry in rawMap.entries) {
        final prop = AnimatableProperty.values.firstWhere(
          (p) => p.name == entry.key,
          orElse: () => AnimatableProperty.scale,
        );
        if (entry.value is Map<String, dynamic>) {
          tracksMap[prop] = KeyframeTrack.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }
    return KeyframeTrackGroup(tracks: tracksMap);
  }
}

/// Represents a single keyframe point on a clip's timeline (Full Backward-Compatible Legacy Model)
class VideoKeyframe {
  final String id;
  final Duration timestamp; // Offset relative to clip start
  final double scale; // 0.1 to 5.0
  final double rotationDegrees; // -360 to 360
  final double positionX; // Pan X in pixels
  final double positionY; // Pan Y in pixels
  final double opacity; // 0.0 to 1.0
  final KeyframeCurve curve;

  VideoKeyframe({
    required this.id,
    Duration? timestamp,
    double? timeInSeconds,
    this.scale = 1.0,
    this.rotationDegrees = 0.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.opacity = 1.0,
    this.curve = KeyframeCurve.easeInOut,
  }) : timestamp = timestamp ??
            (timeInSeconds != null
                ? Duration(microseconds: (timeInSeconds * 1000000).round())
                : Duration.zero);

  double get timeInSeconds => timestamp.inMilliseconds / 1000.0;

  VideoKeyframe copyWith({
    String? id,
    Duration? timestamp,
    double? scale,
    double? rotationDegrees,
    double? positionX,
    double? positionY,
    double? opacity,
    KeyframeCurve? curve,
  }) {
    return VideoKeyframe(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      scale: scale ?? this.scale,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      opacity: opacity ?? this.opacity,
      curve: curve ?? this.curve,
    );
  }

  /// Linearly/cubically interpolates a timeline position from a list of keyframes.
  static VideoKeyframe? interpolate({
    required List<VideoKeyframe> keyframes,
    required double timeInSeconds,
  }) {
    if (keyframes.isEmpty) return null;
    if (keyframes.length == 1) return keyframes.first;

    final sorted = List<VideoKeyframe>.from(keyframes)
      ..sort((a, b) => a.timeInSeconds.compareTo(b.timeInSeconds));

    if (timeInSeconds <= sorted.first.timeInSeconds) {
      return sorted.first;
    }
    if (timeInSeconds >= sorted.last.timeInSeconds) {
      return sorted.last;
    }

    for (int i = 0; i < sorted.length - 1; i++) {
      final k1 = sorted[i];
      final k2 = sorted[i + 1];
      if (timeInSeconds >= k1.timeInSeconds && timeInSeconds <= k2.timeInSeconds) {
        return interpolateBetween(k1, k2, timeInSeconds);
      }
    }
    return sorted.last;
  }

  /// Linearly/cubically interpolates between two adjacent keyframes
  static VideoKeyframe interpolateBetween(
    VideoKeyframe k1,
    VideoKeyframe k2,
    double currentClipTime,
  ) {
    final diff = k2.timeInSeconds - k1.timeInSeconds;
    final rawT = diff <= 0.0001 ? 0.0 : (currentClipTime - k1.timeInSeconds) / diff;
    final curvedT = k1.curve.evaluate(rawT);

    return VideoKeyframe(
      id: 'kf_interpolated',
      timestamp: Duration(milliseconds: (currentClipTime * 1000).round()),
      scale: ui.lerpDouble(k1.scale, k2.scale, curvedT) ?? k1.scale,
      rotationDegrees: ui.lerpDouble(k1.rotationDegrees, k2.rotationDegrees, curvedT) ?? k1.rotationDegrees,
      positionX: ui.lerpDouble(k1.positionX, k2.positionX, curvedT) ?? k1.positionX,
      positionY: ui.lerpDouble(k1.positionY, k2.positionY, curvedT) ?? k1.positionY,
      opacity: (ui.lerpDouble(k1.opacity, k2.opacity, curvedT) ?? k1.opacity).clamp(0.0, 1.0),
      curve: k1.curve,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestamp.inMilliseconds,
    'scale': scale,
    'rotationDegrees': rotationDegrees,
    'positionX': positionX,
    'positionY': positionY,
    'opacity': opacity,
    'curve': curve.name,
  };

  factory VideoKeyframe.fromJson(Map<String, dynamic> json) {
    KeyframeCurve parsedCurve = KeyframeCurve.easeInOut;
    if (json['curve'] is String) {
      parsedCurve = KeyframeCurve.values.firstWhere(
        (c) => c.name == json['curve'],
        orElse: () => KeyframeCurve.easeInOut,
      );
    }

    return VideoKeyframe(
      id: json['id'] as String? ?? 'kf_',
      timestamp: Duration(milliseconds: (json['timestampMs'] as num?)?.toInt() ?? 0),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0.0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      curve: parsedCurve,
    );
  }

  @override
  String toString() =>
      'VideoKeyframe(time: ${timeInSeconds}s, scale: $scale, rot: $rotationDegrees, pos: ($positionX, $positionY), op: $opacity, curve: ${curve.name})';
}

/// Alias for backwards compatibility with keyframe tests and utilities
typedef Keyframe = VideoKeyframe;
