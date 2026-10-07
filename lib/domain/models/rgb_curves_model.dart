import 'package:flutter/foundation.dart';

/// Single control point on an RGB curve
@immutable
class CurvePoint {
  final double x; // 0.0 to 1.0
  final double y; // 0.0 to 1.0

  const CurvePoint(this.x, this.y);

  CurvePoint copyWith({double? x, double? y}) {
    return CurvePoint(
      (x ?? this.x).clamp(0.0, 1.0),
      (y ?? this.y).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
  };

  factory CurvePoint.fromJson(Map<String, dynamic> json) {
    return CurvePoint(
      ((json['x'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      ((json['y'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurvePoint &&
          runtimeType == other.runtimeType &&
          (x - other.x).abs() < 1e-6 &&
          (y - other.y).abs() < 1e-6;

  @override
  int get hashCode => Object.hash((x * 1000).round(), (y * 1000).round());

  @override
  String toString() => 'CurvePoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Supported curve channels
enum CurveChannel { master, red, green, blue }

/// Non-destructive, multi-channel RGB curves model
@immutable
class RgbCurvesModel {
  final List<CurvePoint> master;
  final List<CurvePoint> red;
  final List<CurvePoint> green;
  final List<CurvePoint> blue;

  const RgbCurvesModel({
    this.master = const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)],
    this.red = const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)],
    this.green = const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)],
    this.blue = const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)],
  });

  /// Identity default instance
  static const RgbCurvesModel identity = RgbCurvesModel();

  List<CurvePoint> get masterPoints => master;
  List<CurvePoint> get redPoints => red;
  List<CurvePoint> get greenPoints => green;
  List<CurvePoint> get bluePoints => blue;

  /// Check if all channels are in identity state [(0,0), (1,1)]
  bool get isIdentity =>
      _isChannelIdentity(master) &&
      _isChannelIdentity(red) &&
      _isChannelIdentity(green) &&
      _isChannelIdentity(blue);

  static bool _isChannelIdentity(List<CurvePoint> pts) {
    if (pts.length != 2) return false;
    final p0 = pts[0];
    final p1 = pts[1];
    return (p0.x - 0.0).abs() < 1e-4 &&
        (p0.y - 0.0).abs() < 1e-4 &&
        (p1.x - 1.0).abs() < 1e-4 &&
        (p1.y - 1.0).abs() < 1e-4;
  }

  List<CurvePoint> getChannel(CurveChannel channel) {
    switch (channel) {
      case CurveChannel.master:
        return master;
      case CurveChannel.red:
        return red;
      case CurveChannel.green:
        return green;
      case CurveChannel.blue:
        return blue;
    }
  }

  RgbCurvesModel setChannel(CurveChannel channel, List<CurvePoint> points) {
    final sorted = List<CurvePoint>.from(points)..sort((a, b) => a.x.compareTo(b.x));
    switch (channel) {
      case CurveChannel.master:
        return copyWith(master: sorted);
      case CurveChannel.red:
        return copyWith(red: sorted);
      case CurveChannel.green:
        return copyWith(green: sorted);
      case CurveChannel.blue:
        return copyWith(blue: sorted);
    }
  }

  RgbCurvesModel addPoint(CurveChannel channel, CurvePoint point) {
    final current = List<CurvePoint>.from(getChannel(channel));
    // Don't duplicate points within 0.02 x-distance
    current.removeWhere((p) => (p.x - point.x).abs() < 0.02);
    current.add(point);
    current.sort((a, b) => a.x.compareTo(b.x));
    return setChannel(channel, current);
  }

  RgbCurvesModel removePoint(CurveChannel channel, int index) {
    final current = List<CurvePoint>.from(getChannel(channel));
    if (current.length <= 2) return this; // Keep at least endpoints
    if (index > 0 && index < current.length - 1) {
      current.removeAt(index);
      return setChannel(channel, current);
    }
    return this;
  }

  RgbCurvesModel resetChannel(CurveChannel channel) {
    const defaultPts = [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)];
    return setChannel(channel, defaultPts);
  }

  RgbCurvesModel resetAll() => identity;

  /// Piecewise linear evaluation for fast real-time CPU evaluation or shader LUT generation
  double evaluate(double inputX, [CurveChannel channel = CurveChannel.master]) {
    final clampedX = inputX.clamp(0.0, 1.0);
    final pts = getChannel(channel);
    if (pts.isEmpty) return clampedX;
    if (pts.length == 1) return pts.first.y;

    if (clampedX <= pts.first.x) return pts.first.y;
    if (clampedX >= pts.last.x) return pts.last.y;

    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      if (clampedX >= p0.x && clampedX <= p1.x) {
        final dx = p1.x - p0.x;
        if (dx.abs() < 1e-6) return p0.y;
        final t = (clampedX - p0.x) / dx;
        return (p0.y + t * (p1.y - p0.y)).clamp(0.0, 1.0);
      }
    }
    return clampedX;
  }

  RgbCurvesModel copyWith({
    List<CurvePoint>? master,
    List<CurvePoint>? red,
    List<CurvePoint>? green,
    List<CurvePoint>? blue,
  }) {
    return RgbCurvesModel(
      master: master ?? this.master,
      red: red ?? this.red,
      green: green ?? this.green,
      blue: blue ?? this.blue,
    );
  }

  Map<String, dynamic> toJson() => {
    'master': master.map((p) => p.toJson()).toList(),
    'red': red.map((p) => p.toJson()).toList(),
    'green': green.map((p) => p.toJson()).toList(),
    'blue': blue.map((p) => p.toJson()).toList(),
  };

  factory RgbCurvesModel.fromJson(Map<String, dynamic> json) {
    List<CurvePoint> parsePts(dynamic list) {
      if (list is! List) return const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)];
      final pts = list
          .whereType<Map<String, dynamic>>()
          .map((m) => CurvePoint.fromJson(m))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      return pts.length >= 2 ? pts : const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)];
    }

    return RgbCurvesModel(
      master: parsePts(json['master']),
      red: parsePts(json['red']),
      green: parsePts(json['green']),
      blue: parsePts(json['blue']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RgbCurvesModel &&
          runtimeType == other.runtimeType &&
          listEquals(master, other.master) &&
          listEquals(red, other.red) &&
          listEquals(green, other.green) &&
          listEquals(blue, other.blue);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(master),
    Object.hashAll(red),
    Object.hashAll(green),
    Object.hashAll(blue),
  );
}
