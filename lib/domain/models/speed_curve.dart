import 'dart:math' as math;

/// Interpolation mode between adjacent speed control points
enum SpeedInterpolation {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  hold;

  /// Evaluates normalized interpolation progression [t] (0.0 to 1.0)
  double evaluate(double t) {
    final clamped = t.clamp(0.0, 1.0);
    switch (this) {
      case SpeedInterpolation.linear:
        return clamped;
      case SpeedInterpolation.easeIn:
        return clamped * clamped;
      case SpeedInterpolation.easeOut:
        return clamped * (2.0 - clamped);
      case SpeedInterpolation.easeInOut:
        return clamped < 0.5
            ? 2.0 * clamped * clamped
            : -1.0 + (4.0 - 2.0 * clamped) * clamped;
      case SpeedInterpolation.hold:
        return clamped >= 1.0 ? 1.0 : 0.0;
    }
  }
}

/// Represents a single control point on a 2D speed-time curve
class SpeedCurvePoint {
  final double timeRatio; // 0.0 to 1.0 (relative position along clip)
  final double speedMultiplier; // e.g. 0.1x to 50.0x
  final SpeedInterpolation interpolation;

  const SpeedCurvePoint({
    required this.timeRatio,
    required this.speedMultiplier,
    this.interpolation = SpeedInterpolation.linear,
  });

  SpeedCurvePoint copyWith({
    double? timeRatio,
    double? speedMultiplier,
    SpeedInterpolation? interpolation,
  }) {
    return SpeedCurvePoint(
      timeRatio: timeRatio ?? this.timeRatio,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      interpolation: interpolation ?? this.interpolation,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeRatio': timeRatio,
        'speedMultiplier': speedMultiplier,
        'interpolation': interpolation.name,
      };

  factory SpeedCurvePoint.fromJson(Map<String, dynamic> json) => SpeedCurvePoint(
        timeRatio: (json['timeRatio'] as num).toDouble(),
        speedMultiplier: (json['speedMultiplier'] as num).toDouble(),
        interpolation: json['interpolation'] != null
            ? SpeedInterpolation.values.firstWhere(
                (e) => e.name == json['interpolation'],
                orElse: () => SpeedInterpolation.linear,
              )
            : SpeedInterpolation.linear,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedCurvePoint &&
          runtimeType == other.runtimeType &&
          timeRatio == other.timeRatio &&
          speedMultiplier == other.speedMultiplier &&
          interpolation == other.interpolation;

  @override
  int get hashCode =>
      timeRatio.hashCode ^ speedMultiplier.hashCode ^ interpolation.hashCode;
}

/// Canonical alias for SpeedCurvePoint matching NLE terminology
typedef SpeedPoint = SpeedCurvePoint;

/// Represents a segment between two consecutive speed points
class SpeedSegment {
  final double startTimeRatio;
  final double endTimeRatio;
  final double startSpeed;
  final double endSpeed;
  final SpeedInterpolation interpolation;

  const SpeedSegment({
    double? startTimeRatio,
    double? endTimeRatio,
    double? startRatio,
    double? endRatio,
    required this.startSpeed,
    required this.endSpeed,
    this.interpolation = SpeedInterpolation.linear,
  })  : startTimeRatio = startTimeRatio ?? startRatio ?? 0.0,
        endTimeRatio = endTimeRatio ?? endRatio ?? 1.0;

  double get startRatio => startTimeRatio;
  double get endRatio => endTimeRatio;
  double get durationRatio => (endTimeRatio - startTimeRatio).clamp(0.0, 1.0);
  double get averageSpeed => (startSpeed + endSpeed) / 2.0;

  double evaluateAt(double t) {
    if (durationRatio <= 0.0001) return endSpeed;
    final progress = ((t - startTimeRatio) / durationRatio).clamp(0.0, 1.0);
    final factor = interpolation.evaluate(progress);
    return startSpeed + factor * (endSpeed - startSpeed);
  }
}

/// Non-destructive Freeze Frame model
class FreezeFrame {
  final Duration timelineOffset; // relative to clip timeline start
  final Duration duration;       // duration of the freeze (default 3.0s)
  final Duration sourceTime;     // exact source frame timestamp being held

  const FreezeFrame({
    required this.timelineOffset,
    this.duration = const Duration(seconds: 3),
    required this.sourceTime,
  });

  FreezeFrame copyWith({
    Duration? timelineOffset,
    Duration? duration,
    Duration? sourceTime,
  }) {
    return FreezeFrame(
      timelineOffset: timelineOffset ?? this.timelineOffset,
      duration: duration ?? this.duration,
      sourceTime: sourceTime ?? this.sourceTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'timelineOffsetMs': timelineOffset.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'sourceTimeMs': sourceTime.inMilliseconds,
      };

  factory FreezeFrame.fromJson(Map<String, dynamic> json) => FreezeFrame(
        timelineOffset: Duration(
            milliseconds: (json['timelineOffsetMs'] as num?)?.toInt() ?? 0),
        duration: Duration(
            milliseconds: (json['durationMs'] as num?)?.toInt() ?? 3000),
        sourceTime: Duration(
            milliseconds: (json['sourceTimeMs'] as num?)?.toInt() ?? 0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreezeFrame &&
          runtimeType == other.runtimeType &&
          timelineOffset == other.timelineOffset &&
          duration == other.duration &&
          sourceTime == other.sourceTime;

  @override
  int get hashCode =>
      timelineOffset.hashCode ^ duration.hashCode ^ sourceTime.hashCode;
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
  smooth,
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
        final rawFactor = (clampedT - p1.timeRatio) / span;
        final factor = p1.interpolation.evaluate(rawFactor);
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

  /// Splits the speed curve at [splitTimelineRatio], returning two independent,
  /// continuous curves rebased to [0.0, 1.0] for Part 1 and Part 2.
  (SpeedCurve partA, SpeedCurve partB) splitAt(double splitTimelineRatio) {
    final u = splitTimelineRatio.clamp(0.001, 0.999);
    final splitSpeed = evaluateSpeedAt(u);

    final sorted = List<SpeedCurvePoint>.from(points)
      ..sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    // Part A: from 0.0 to u, normalized to [0.0, 1.0]
    final ptsA = <SpeedCurvePoint>[];
    for (final p in sorted) {
      if (p.timeRatio < u) {
        ptsA.add(SpeedCurvePoint(
          timeRatio: (p.timeRatio / u).clamp(0.0, 1.0),
          speedMultiplier: p.speedMultiplier,
          interpolation: p.interpolation,
        ));
      }
    }
    if (ptsA.isEmpty || ptsA.first.timeRatio > 0.001) {
      ptsA.insert(
        0,
        SpeedCurvePoint(
          timeRatio: 0.0,
          speedMultiplier: evaluateSpeedAt(0.0),
        ),
      );
    }
    ptsA.add(SpeedCurvePoint(
      timeRatio: 1.0,
      speedMultiplier: splitSpeed,
    ));

    // Part B: from u to 1.0, normalized to [0.0, 1.0]
    final ptsB = <SpeedCurvePoint>[
      SpeedCurvePoint(
        timeRatio: 0.0,
        speedMultiplier: splitSpeed,
      ),
    ];
    for (final p in sorted) {
      if (p.timeRatio > u) {
        ptsB.add(SpeedCurvePoint(
          timeRatio: ((p.timeRatio - u) / (1.0 - u)).clamp(0.0, 1.0),
          speedMultiplier: p.speedMultiplier,
          interpolation: p.interpolation,
        ));
      }
    }
    if (ptsB.last.timeRatio < 0.999) {
      ptsB.add(SpeedCurvePoint(
        timeRatio: 1.0,
        speedMultiplier: evaluateSpeedAt(1.0),
      ));
    }

    final curveA = SpeedCurve(
      type: SpeedCurvePresetType.custom,
      points: ptsA,
      keepPitch: keepPitch,
      smoothSlowMo: smoothSlowMo,
    );

    final curveB = SpeedCurve(
      type: SpeedCurvePresetType.custom,
      points: ptsB,
      keepPitch: keepPitch,
      smoothSlowMo: smoothSlowMo,
    );

    return (curveA, curveB);
  }

  /// Clamps speed points to [startRatio, endRatio] during trimming,
  /// ensuring points outside the trimmed clip are safely removed or re-normalized.
  SpeedCurve clampToRange(double startRatio, double endRatio) {
    final start = startRatio.clamp(0.0, 0.99);
    final end = endRatio.clamp(start + 0.01, 1.0);
    final span = end - start;

    final newPts = <SpeedCurvePoint>[
      SpeedCurvePoint(
        timeRatio: 0.0,
        speedMultiplier: evaluateSpeedAt(start),
      ),
    ];

    for (final p in points) {
      if (p.timeRatio > start && p.timeRatio < end) {
        newPts.add(SpeedCurvePoint(
          timeRatio: ((p.timeRatio - start) / span).clamp(0.0, 1.0),
          speedMultiplier: p.speedMultiplier,
          interpolation: p.interpolation,
        ));
      }
    }

    newPts.add(SpeedCurvePoint(
      timeRatio: 1.0,
      speedMultiplier: evaluateSpeedAt(end),
    ));

    return copyWith(
      type: SpeedCurvePresetType.custom,
      points: newPts,
    );
  }

  /// Deep duplicate of speed curve
  SpeedCurve duplicate() {
    return copyWith(
      points: points.map((p) => p.copyWith()).toList(),
    );
  }

  // --- Presets ---

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

  static SpeedCurve smooth({bool keepPitch = true, bool smoothSlowMo = true}) => SpeedCurve(
        type: SpeedCurvePresetType.smooth,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: const [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 0.25, speedMultiplier: 0.5),
          SpeedCurvePoint(timeRatio: 0.5, speedMultiplier: 2.0),
          SpeedCurvePoint(timeRatio: 0.75, speedMultiplier: 0.5),
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

  static SpeedCurve constant(
    double speed, {
    bool keepPitch = true,
    bool smoothSlowMo = true,
  }) =>
      SpeedCurve(
        type: SpeedCurvePresetType.custom,
        keepPitch: keepPitch,
        smoothSlowMo: smoothSlowMo,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: speed),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: speed),
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

/// Deterministic Time Remapping Engine bridging timeline time and source media time
class TimeRemapper {
  /// Deterministic conversion from clip timeline offset to source media timestamp.
  static Duration timelineToSourceTime({
    required Duration timelineOffset,
    required Duration trimStart,
    required Duration trimEnd,
    required Duration originalDuration,
    SpeedCurve? speedCurve,
    double constantSpeed = 1.0,
    bool isReversed = false,
    FreezeFrame? freezeFrame,
    bool isFrozen = false,
    Duration? wholeClipFreezeTime,
  }) {
    final trimmedDurationMs = (trimEnd.inMilliseconds - trimStart.inMilliseconds)
        .clamp(0, originalDuration.inMilliseconds);
    if (trimmedDurationMs <= 0) return trimStart;

    // Whole-clip freeze handling
    if (isFrozen) {
      final frozenAt = wholeClipFreezeTime ?? trimStart;
      return frozenAt;
    }

    // Freeze frame segment handling
    if (freezeFrame != null && freezeFrame.duration.inMilliseconds > 0) {
      final freezeStartMs = freezeFrame.timelineOffset.inMilliseconds;
      final freezeDurMs = freezeFrame.duration.inMilliseconds;
      final freezeEndMs = freezeStartMs + freezeDurMs;
      final currentMs = timelineOffset.inMilliseconds;

      if (currentMs >= freezeStartMs && currentMs <= freezeEndMs) {
        // Inside freeze window: return exact frozen source frame
        return freezeFrame.sourceTime;
      }

      // If past freeze window, subtract freeze duration to rebase timeline time
      final effectiveTimelineMs = currentMs > freezeEndMs
          ? currentMs - freezeDurMs
          : currentMs;

      return _computeSpeedSourceTime(
        timelineOffsetMs: effectiveTimelineMs,
        trimStart: trimStart,
        trimEnd: trimEnd,
        trimmedDurationMs: trimmedDurationMs,
        originalDuration: originalDuration,
        speedCurve: speedCurve,
        constantSpeed: constantSpeed,
        isReversed: isReversed,
      );
    }

    return _computeSpeedSourceTime(
      timelineOffsetMs: timelineOffset.inMilliseconds,
      trimStart: trimStart,
      trimEnd: trimEnd,
      trimmedDurationMs: trimmedDurationMs,
      originalDuration: originalDuration,
      speedCurve: speedCurve,
      constantSpeed: constantSpeed,
      isReversed: isReversed,
    );
  }

  static Duration _computeSpeedSourceTime({
    required int timelineOffsetMs,
    required Duration trimStart,
    required Duration trimEnd,
    required int trimmedDurationMs,
    required Duration originalDuration,
    SpeedCurve? speedCurve,
    double constantSpeed = 1.0,
    bool isReversed = false,
  }) {
    if (speedCurve != null) {
      final avgSpeed = speedCurve.averageSpeed;
      final activeTimelineDurationMs = (trimmedDurationMs / avgSpeed).round().clamp(1, 100000000);
      final timelineRatio = timelineOffsetMs / activeTimelineDurationMs;
      var sourceProgress = speedCurve.getSourceProgressAt(timelineRatio.clamp(0.0, 1.0));
      if (isReversed) {
        sourceProgress = 1.0 - sourceProgress;
      }
      final sourceOffsetMs = (sourceProgress * trimmedDurationMs).round();
      final sourceTimeMs = (trimStart.inMilliseconds + sourceOffsetMs).clamp(
        0,
        originalDuration.inMilliseconds,
      );
      return Duration(milliseconds: sourceTimeMs);
    } else {
      final validSpeed = constantSpeed.clamp(0.1, 100.0);
      final sourceOffsetMs = (timelineOffsetMs * validSpeed).round();
      final baseSourceMs = isReversed
          ? trimEnd.inMilliseconds - sourceOffsetMs
          : trimStart.inMilliseconds + sourceOffsetMs;
      final sourceTimeMs = baseSourceMs.clamp(
        0,
        originalDuration.inMilliseconds,
      );
      return Duration(milliseconds: sourceTimeMs);
    }
  }

  /// Calculates the active timeline duration for a clip.
  static Duration calculateActiveDuration({
    required Duration trimStart,
    required Duration trimEnd,
    Duration? originalDuration,
    SpeedCurve? speedCurve,
    double constantSpeed = 1.0,
    FreezeFrame? freezeFrame,
    bool isFrozen = false,
    Duration? frozenDuration,
  }) {
    final maxMs = originalDuration?.inMilliseconds ?? trimEnd.inMilliseconds;
    final trimmedMs = (trimEnd.inMilliseconds - trimStart.inMilliseconds)
        .clamp(0, maxMs);
    if (trimmedMs <= 0) return Duration.zero;

    if (isFrozen) {
      return frozenDuration ?? const Duration(seconds: 3);
    }

    final effectiveSpeed = (speedCurve != null)
        ? speedCurve.averageSpeed
        : (constantSpeed > 0 ? constantSpeed : 1.0);
    final clampedSpeed = effectiveSpeed.clamp(0.1, 100.0);
    final baseTimelineMs = (trimmedMs / clampedSpeed).round();

    final freezeAddMs = (freezeFrame != null) ? freezeFrame.duration.inMilliseconds : 0;
    return Duration(milliseconds: baseTimelineMs + freezeAddMs);
  }
}

/// Canonical alias for TimeRemapper
typedef TimeRemap = TimeRemapper;
