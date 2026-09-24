import 'dart:math' as math;

/// Represents a single control point on a 2D speed-time curve
class SpeedCurvePoint {
  final double timeRatio; // 0.0 to 1.0 (relative position along clip)
  final double speedMultiplier; // e.g. 0.1x to 50.0x

  const SpeedCurvePoint({
    required this.timeRatio,
    required this.speedMultiplier,
  });

  SpeedCurvePoint copyWith({double? timeRatio, double? speedMultiplier}) {
    return SpeedCurvePoint(
      timeRatio: timeRatio ?? this.timeRatio,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeRatio': timeRatio,
        'speedMultiplier': speedMultiplier,
      };

  factory SpeedCurvePoint.fromJson(Map<String, dynamic> json) => SpeedCurvePoint(
        timeRatio: (json['timeRatio'] as num).toDouble(),
        speedMultiplier: (json['speedMultiplier'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedCurvePoint &&
          runtimeType == other.runtimeType &&
          timeRatio == other.timeRatio &&
          speedMultiplier == other.speedMultiplier;

  @override
  int get hashCode => timeRatio.hashCode ^ speedMultiplier.hashCode;
}

enum SpeedCurvePresetType {
  none,
  montage,
  hero,
  bullet,
  jumpCut,
  flashIn,
  flashOut,
  bubbly,
  custom,
}

/// CapCut-style non-linear speed ramping curve
class SpeedCurve {
  final SpeedCurvePresetType type;
  final List<SpeedCurvePoint> points;

  /// Preserves natural human pitch without chipmunk distortion
  final bool keepPitch;

  /// Simulates optical-flow frame blending for ultra smooth slow-mo ramps
  final bool smoothSlowMo;

  const SpeedCurve({
    required this.type,
    required this.points,
    this.keepPitch = true,
    this.smoothSlowMo = true,
  });

  /// Evaluates the instantaneous speed multiplier at given clip time ratio [t] (0.0 to 1.0)
  double evaluateSpeedAt(double t) {
    if (points.isEmpty) return 1.0;
    if (points.length == 1) return points.first.speedMultiplier;
    final clampedT = t.clamp(0.0, 1.0);

    final sorted = List<SpeedCurvePoint>.from(points)
      ..sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    if (clampedT <= sorted.first.timeRatio) return sorted.first.speedMultiplier;
    if (clampedT >= sorted.last.timeRatio) return sorted.last.speedMultiplier;

    for (int i = 0; i < sorted.length - 1; i++) {
      final p1 = sorted[i];
      final p2 = sorted[i + 1];
      if (clampedT >= p1.timeRatio && clampedT <= p2.timeRatio) {
        final span = p2.timeRatio - p1.timeRatio;
        if (span <= 0.0001) return p2.speedMultiplier;
        final factor = (clampedT - p1.timeRatio) / span;
        return p1.speedMultiplier + factor * (p2.speedMultiplier - p1.speedMultiplier);
      }
    }
    return sorted.last.speedMultiplier;
  }

  /// Calculates the effective average speed over the entire curve.
  /// Used for calculating the total timeline duration: originalTrimDuration / averageSpeed.
  double get averageSpeed {
    if (points.isEmpty) return 1.0;
    if (points.length == 1) return points.first.speedMultiplier.clamp(0.1, 100.0);

    final sorted = List<SpeedCurvePoint>.from(points)
      ..sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    double totalArea = 0.0;
    if (sorted.first.timeRatio > 0.0) {
      totalArea += sorted.first.speedMultiplier * sorted.first.timeRatio;
    }

    for (int i = 0; i < sorted.length - 1; i++) {
      final p1 = sorted[i];
      final p2 = sorted[i + 1];
      final dt = p2.timeRatio - p1.timeRatio;
      if (dt > 0.0) {
        totalArea += (p1.speedMultiplier + p2.speedMultiplier) * 0.5 * dt;
      }
    }

    if (sorted.last.timeRatio < 1.0) {
      totalArea += sorted.last.speedMultiplier * (1.0 - sorted.last.timeRatio);
    }

    return math.max(0.1, totalArea.clamp(0.1, 100.0));
  }

  /// Computes the exact normalized source progress (0.0 to 1.0) corresponding to
  /// a normalized timeline position [timelineRatio] (0.0 to 1.0).
  ///
  /// This calculates the definite integral of the speed curve from 0 to [timelineRatio]
  /// divided by the total integral from 0 to 1.
  double getSourceProgressAt(double timelineRatio) {
    final u = timelineRatio.clamp(0.0, 1.0);
    if (u <= 0.0) return 0.0;
    if (u >= 1.0) return 1.0;
    if (points.isEmpty) return u;
    if (points.length == 1) return u;

    final sorted = List<SpeedCurvePoint>.from(points)
      ..sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    double totalArea = 0.0;
    double partialArea = 0.0;

    void addSegment(double t1, double t2, double s1, double s2) {
      final dt = t2 - t1;
      if (dt <= 0.0) return;
      final area = (s1 + s2) * 0.5 * dt;
      totalArea += area;

      if (u >= t2) {
        partialArea += area;
      } else if (u > t1) {
        final factor = (u - t1) / dt;
        final speedAtU = s1 + factor * (s2 - s1);
        partialArea += (s1 + speedAtU) * 0.5 * (u - t1);
      }
    }

    if (sorted.first.timeRatio > 0.0) {
      addSegment(0.0, sorted.first.timeRatio, sorted.first.speedMultiplier, sorted.first.speedMultiplier);
    }

    for (int i = 0; i < sorted.length - 1; i++) {
      final p1 = sorted[i];
      final p2 = sorted[i + 1];
      addSegment(p1.timeRatio, p2.timeRatio, p1.speedMultiplier, p2.speedMultiplier);
    }

    if (sorted.last.timeRatio < 1.0) {
      addSegment(sorted.last.timeRatio, 1.0, sorted.last.speedMultiplier, sorted.last.speedMultiplier);
    }

    if (totalArea <= 0.00001) return u;
    return (partialArea / totalArea).clamp(0.0, 1.0);
  }

  static SpeedCurve montage({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.montage,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 2.5),
          SpeedCurvePoint(timeRatio: 0.25, speedMultiplier: 0.3),
          SpeedCurvePoint(timeRatio: 0.75, speedMultiplier: 0.3),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 2.5),
        ],
      );

  static SpeedCurve hero({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.hero,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 0.2, speedMultiplier: 3.5),
          SpeedCurvePoint(timeRatio: 0.45, speedMultiplier: 0.2),
          SpeedCurvePoint(timeRatio: 0.75, speedMultiplier: 0.2),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 1.0),
        ],
      );

  static SpeedCurve bullet({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.bullet,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 4.0),
          SpeedCurvePoint(timeRatio: 0.4, speedMultiplier: 0.2),
          SpeedCurvePoint(timeRatio: 0.6, speedMultiplier: 0.2),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 4.0),
        ],
      );

  static SpeedCurve jumpCut({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.jumpCut,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 2.5),
          SpeedCurvePoint(timeRatio: 0.25, speedMultiplier: 0.5),
          SpeedCurvePoint(timeRatio: 0.5, speedMultiplier: 2.5),
          SpeedCurvePoint(timeRatio: 0.75, speedMultiplier: 0.5),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 2.5),
        ],
      );

  static SpeedCurve flashIn({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.flashIn,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 5.0),
          SpeedCurvePoint(timeRatio: 0.3, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 1.0),
        ],
      );

  static SpeedCurve flashOut({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.flashOut,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 0.7, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 5.0),
        ],
      );

  static SpeedCurve bubbly({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.bubbly,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 0.2, speedMultiplier: 0.4),
          SpeedCurvePoint(timeRatio: 0.5, speedMultiplier: 3.2),
          SpeedCurvePoint(timeRatio: 0.8, speedMultiplier: 0.4),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 1.0),
        ],
      );

  static SpeedCurve custom({
    List<SpeedCurvePoint>? points,
    bool keepPitch = true,
    bool smoothSlowMo = true,
  }) =>
      SpeedCurve(
        type: SpeedCurvePresetType.custom,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: points ??
            const [
              SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
              SpeedCurvePoint(timeRatio: 0.3, speedMultiplier: 2.5),
              SpeedCurvePoint(timeRatio: 0.7, speedMultiplier: 0.4),
              SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 1.0),
            ],
      );

  SpeedCurve copyWith({
    SpeedCurvePresetType? type,
    List<SpeedCurvePoint>? points,
    bool? keepPitch,
    bool? smoothSlowMo,
  }) {
    return SpeedCurve(
      type: type ?? this.type,
      points: points ?? this.points,
      keepPitch: keepPitch ?? this.keepPitch,
      smoothSlowMo: smoothSlowMo ?? this.smoothSlowMo,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'points': points.map((p) => p.toJson()).toList(),
        'keepPitch': keepPitch,
        'smoothSlowMo': smoothSlowMo,
      };

  factory SpeedCurve.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'custom';
    final type = SpeedCurvePresetType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => SpeedCurvePresetType.custom,
    );
    final rawPoints = (json['points'] as List<dynamic>?) ?? [];
    final pts = rawPoints
        .map((p) => SpeedCurvePoint.fromJson(p as Map<String, dynamic>))
        .toList();
    return SpeedCurve(
      type: type,
      points: pts,
      keepPitch: json['keepPitch'] as bool? ?? true,
      smoothSlowMo: json['smoothSlowMo'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedCurve &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          keepPitch == other.keepPitch &&
          smoothSlowMo == other.smoothSlowMo &&
          _listEquals(points, other.points);

  @override
  int get hashCode =>
      type.hashCode ^
      keepPitch.hashCode ^
      smoothSlowMo.hashCode ^
      points.length.hashCode;

  static bool _listEquals(List<SpeedCurvePoint> a, List<SpeedCurvePoint> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
