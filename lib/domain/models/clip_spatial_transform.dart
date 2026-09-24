import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/transform_snap_engine.dart';

/// Immutable domain model representing the spatial transformation state
/// of an individual media clip on the interactive canvas.
class ClipSpatialTransform {
  /// Associated unique clip ID
  final String clipId;

  /// Horizontal position offset relative to canvas center (default 0.0)
  final double xPos;

  /// Vertical position offset relative to canvas center (default 0.0)
  final double yPos;

  /// Uniform spatial scale factor (default 1.0, must be positive finite)
  final double scale;

  /// Continuous spatial rotation in radians (default 0.0)
  final double rotationAngle;

  /// Minimum allowable scale to prevent inversion or zero-dimension rendering
  static const double minScale = 0.05;

  /// Maximum allowable scale
  static const double maxScale = 20.0;

  /// Distance threshold in logical pixels below which clip center auto-snaps to canvas center (0.0)
  static const double centerSnapThreshold = TransformSnapConfig.centerSnapThreshold;

  /// Distance threshold in logical pixels above which clip center breaks free from center snap
  static const double centerReleaseThreshold = TransformSnapConfig.centerReleaseThreshold;

  /// Distance threshold in logical pixels below which clip edge auto-snaps to canvas edge
  static const double edgeSnapThreshold = TransformSnapConfig.edgeSnapThreshold;

  /// Distance threshold in logical pixels above which clip edge breaks free from edge snap
  static const double edgeReleaseThreshold = TransformSnapConfig.edgeReleaseThreshold;

  /// Computes updated snap state and effective coordinate for a single axis with hysteresis.
  /// Returns a record: (effectiveCoordinate, isSnapped).
  static (double, bool) calculateCenterSnap({
    required double rawCoordinate,
    required bool currentlySnapped,
    double snapThreshold = centerSnapThreshold,
    double releaseThreshold = centerReleaseThreshold,
  }) {
    if (currentlySnapped) {
      if (rawCoordinate.abs() > releaseThreshold) {
        return (rawCoordinate, false);
      } else {
        return (0.0, true);
      }
    } else {
      if (rawCoordinate.abs() <= snapThreshold) {
        return (0.0, true);
      } else {
        return (rawCoordinate, false);
      }
    }
  }

  const ClipSpatialTransform({
    required this.clipId,
    this.xPos = 0.0,
    this.yPos = 0.0,
    this.scale = 1.0,
    this.rotationAngle = 0.0,
  });

  /// Factory constructor to extract spatial transform directly from a VideoClip
  factory ClipSpatialTransform.fromClip(VideoClip clip) {
    return ClipSpatialTransform(
      clipId: clip.id,
      xPos: clip.xPos,
      yPos: clip.yPos,
      scale: clip.scale,
      rotationAngle: clip.rotationAngle,
    );
  }

  /// Sanitizes and validates scale to ensure it is positive and finite
  static double sanitizeScale(double rawScale, {double fallback = 1.0}) {
    if (rawScale.isNaN || !rawScale.isFinite || rawScale <= 0.0) {
      return fallback;
    }
    return rawScale.clamp(minScale, maxScale);
  }

  /// Sanitizes position coordinate ensuring finite numbers
  static double sanitizePosition(double val, {double fallback = 0.0}) {
    if (val.isNaN || !val.isFinite) return fallback;
    return val;
  }

  /// Sanitizes rotation angle ensuring finite numbers
  static double sanitizeRotation(double val, {double fallback = 0.0}) {
    if (val.isNaN || !val.isFinite) return fallback;
    return val;
  }

  ClipSpatialTransform copyWith({
    String? clipId,
    double? xPos,
    double? yPos,
    double? scale,
    double? rotationAngle,
  }) {
    return ClipSpatialTransform(
      clipId: clipId ?? this.clipId,
      xPos: xPos != null ? sanitizePosition(xPos, fallback: this.xPos) : this.xPos,
      yPos: yPos != null ? sanitizePosition(yPos, fallback: this.yPos) : this.yPos,
      scale: scale != null ? sanitizeScale(scale, fallback: this.scale) : this.scale,
      rotationAngle: rotationAngle != null ? sanitizeRotation(rotationAngle, fallback: this.rotationAngle) : this.rotationAngle,
    );
  }

  /// Applies this spatial transform to an existing VideoClip immutably
  VideoClip applyTo(VideoClip clip) {
    return clip.copyWith(
      xPos: xPos,
      yPos: yPos,
      scale: scale,
      rotationAngle: rotationAngle,
    );
  }

  /// Computes the Flutter Matrix4 representation for this spatial transform,
  /// seamlessly composing continuous spatial transform with legacy step rotation
  /// and horizontal/vertical flips.
  Matrix4 toMatrix4({
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) {
    final totalRotation = (legacyRotationDegrees * math.pi / 180.0) + rotationAngle;
    final scaleX = (flipHorizontal ? -1.0 : 1.0) * scale;
    final scaleY = (flipVertical ? -1.0 : 1.0) * scale;

    return Matrix4.identity()
      ..translate(xPos, yPos, 0.0)
      ..rotateZ(totalRotation)
      ..scale(scaleX, scaleY, 1.0);
  }

  Map<String, dynamic> toJson() {
    return {
      'clipId': clipId,
      'xPos': xPos,
      'yPos': yPos,
      'scale': scale,
      'rotationAngle': rotationAngle,
    };
  }

  factory ClipSpatialTransform.fromJson(Map<String, dynamic> json) {
    return ClipSpatialTransform(
      clipId: json['clipId'] as String? ?? '',
      xPos: sanitizePosition((json['xPos'] as num?)?.toDouble() ?? 0.0),
      yPos: sanitizePosition((json['yPos'] as num?)?.toDouble() ?? 0.0),
      scale: sanitizeScale((json['scale'] as num?)?.toDouble() ?? 1.0),
      rotationAngle: sanitizeRotation((json['rotationAngle'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipSpatialTransform &&
          runtimeType == other.runtimeType &&
          clipId == other.clipId &&
          xPos == other.xPos &&
          yPos == other.yPos &&
          scale == other.scale &&
          rotationAngle == other.rotationAngle;

  @override
  int get hashCode =>
      clipId.hashCode ^
      xPos.hashCode ^
      yPos.hashCode ^
      scale.hashCode ^
      rotationAngle.hashCode;

  @override
  String toString() =>
      'ClipSpatialTransform(clipId: $clipId, x: $xPos, y: $yPos, scale: $scale, rad: $rotationAngle)';
}
