import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/clip_spatial_transform.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';

/// Configuration for spatial transform auto-snapping thresholds and hysteresis.
class TransformSnapConfig {
  /// Distance threshold in logical pixels below which clip center auto-snaps to canvas center
  static const double centerSnapThreshold = 10.0;

  /// Distance threshold in logical pixels above which clip center breaks free from center snap
  static const double centerReleaseThreshold = 14.0;

  /// Distance threshold in logical pixels below which clip edge auto-snaps to canvas edge
  static const double edgeSnapThreshold = 10.0;

  /// Distance threshold in logical pixels above which clip edge breaks free from edge snap
  static const double edgeReleaseThreshold = 14.0;
}

/// Supported alignment targets for the horizontal (X) axis.
enum SnapTargetX {
  none,
  centerX,
  leftEdge,
  rightEdge,
}

/// Supported alignment targets for the vertical (Y) axis.
enum SnapTargetY {
  none,
  centerY,
  topEdge,
  bottomEdge,
}

/// Supported layer types for smart multi-layer alignment.
enum LayerType {
  mainVideo,
  pipVideo,
  text,
  sticker,
  canvas,
}

/// Supported horizontal spatial snap relationships between active layer and target layer.
enum SnapRelationshipX {
  none,
  centerToCenter, // Priority 1
  leftToLeft, // Priority 2 (Same-Edge)
  rightToRight, // Priority 2 (Same-Edge)
  leftToRight, // Priority 3 (Opposite-Edge)
  rightToLeft, // Priority 3 (Opposite-Edge)
  canvasCenter, // Priority 1 (Center-to-Center)
  canvasLeftEdge, // Priority 4 (Canvas Edges)
  canvasRightEdge, // Priority 4 (Canvas Edges)
}

/// Supported vertical spatial snap relationships between active layer and target layer.
enum SnapRelationshipY {
  none,
  centerToCenter, // Priority 1
  topToTop, // Priority 2 (Same-Edge)
  bottomToBottom, // Priority 2 (Same-Edge)
  topToBottom, // Priority 3 (Opposite-Edge)
  bottomToTop, // Priority 3 (Opposite-Edge)
  canvasCenter, // Priority 1 (Center-to-Center)
  canvasTopEdge, // Priority 4 (Canvas Edges)
  canvasBottomEdge, // Priority 4 (Canvas Edges)
}

/// The visual axis-aligned bounding box (AABB) of the transformed media clip
/// in canvas-relative space (where (0,0) is canvas center).
class TransformedVisualBounds {
  final double left;
  final double right;
  final double top;
  final double bottom;
  final double centerX;
  final double centerY;

  const TransformedVisualBounds({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.centerX,
    required this.centerY,
  });

  double get width => right - left;
  double get height => bottom - top;

  /// Computes the visual bounding geometry of a clip of dimensions [canvasSize]
  /// transformed by [transform], [legacyRotationDegrees], and flip options.
  ///
  /// The bounds are relative to canvas center (0,0).
  /// Note: The base unrotated clip fills the canvas (-w/2, -h/2) to (w/2, h/2).
  factory TransformedVisualBounds.fromTransform({
    required Size canvasSize,
    required ClipSpatialTransform transform,
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) {
    final halfW = canvasSize.width / 2.0;
    final halfH = canvasSize.height / 2.0;

    // Four unrotated corners relative to clip center
    final p0 = Offset(-halfW, -halfH);
    final p1 = Offset(halfW, -halfH);
    final p2 = Offset(halfW, halfH);
    final p3 = Offset(-halfW, halfH);

    final totalRotation = (legacyRotationDegrees * math.pi / 180.0) + transform.rotationAngle;
    final scaleX = (flipHorizontal ? -1.0 : 1.0) * transform.scale;
    final scaleY = (flipVertical ? -1.0 : 1.0) * transform.scale;

    final cosA = math.cos(totalRotation);
    final sinA = math.sin(totalRotation);

    Offset transformCorner(Offset p) {
      // 1. Scale & Flip
      final sx = p.dx * scaleX;
      final sy = p.dy * scaleY;
      // 2. Rotate around center (0,0)
      final rx = sx * cosA - sy * sinA;
      final ry = sx * sinA + sy * cosA;
      // 3. Translate by (xPos, yPos)
      return Offset(rx + transform.xPos, ry + transform.yPos);
    }

    final t0 = transformCorner(p0);
    final t1 = transformCorner(p1);
    final t2 = transformCorner(p2);
    final t3 = transformCorner(p3);

    final left = math.min(math.min(t0.dx, t1.dx), math.min(t2.dx, t3.dx));
    final right = math.max(math.max(t0.dx, t1.dx), math.max(t2.dx, t3.dx));
    final top = math.min(math.min(t0.dy, t1.dy), math.min(t2.dy, t3.dy));
    final bottom = math.max(math.max(t0.dy, t1.dy), math.max(t2.dy, t3.dy));

    return TransformedVisualBounds(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      centerX: transform.xPos,
      centerY: transform.yPos,
    );
  }
}

/// Universal geometry descriptor for any layer (or canvas) participating in alignment.
/// Expressed in canvas-relative space where (0,0) is canvas center.
class TransformAlignmentBounds {
  final String id;
  final String name;
  final LayerType type;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final double centerX;
  final double centerY;

  const TransformAlignmentBounds({
    required this.id,
    required this.name,
    required this.type,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.centerX,
    required this.centerY,
  });

  double get width => right - left;
  double get height => bottom - top;

  factory TransformAlignmentBounds.canvas(Size canvasSize) {
    final halfW = canvasSize.width / 2.0;
    final halfH = canvasSize.height / 2.0;
    return TransformAlignmentBounds(
      id: '__canvas__',
      name: 'Canvas',
      type: LayerType.canvas,
      left: -halfW,
      right: halfW,
      top: -halfH,
      bottom: halfH,
      centerX: 0.0,
      centerY: 0.0,
    );
  }

  factory TransformAlignmentBounds.fromVisualBounds({
    required String id,
    required String name,
    required LayerType type,
    required TransformedVisualBounds bounds,
  }) {
    return TransformAlignmentBounds(
      id: id,
      name: name,
      type: type,
      left: bounds.left,
      right: bounds.right,
      top: bounds.top,
      bottom: bounds.bottom,
      centerX: bounds.centerX,
      centerY: bounds.centerY,
    );
  }

  factory TransformAlignmentBounds.fromVideoClip({
    required VideoClip clip,
    required Size canvasSize,
  }) {
    final bounds = TransformedVisualBounds.fromTransform(
      canvasSize: canvasSize,
      transform: ClipSpatialTransform.fromClip(clip),
      legacyRotationDegrees: clip.rotationDegrees,
      flipHorizontal: clip.flipHorizontal,
      flipVertical: clip.flipVertical,
    );
    return TransformAlignmentBounds.fromVisualBounds(
      id: clip.id,
      name: clip.title,
      type: LayerType.mainVideo,
      bounds: bounds,
    );
  }

  factory TransformAlignmentBounds.fromOverlayClip({
    required OverlayClip overlay,
    required Size canvasSize,
  }) {
    const baseW = 140.0;
    const baseH = 100.0;
    final halfW = (baseW * overlay.scale) / 2.0;
    final halfH = (baseH * overlay.scale) / 2.0;

    final childLeft = (canvasSize.width - baseW) * overlay.position.dx;
    final childTop = (canvasSize.height - baseH) * overlay.position.dy;
    final childCenterX = childLeft + baseW / 2.0 - canvasSize.width / 2.0;
    final childCenterY = childTop + baseH / 2.0 - canvasSize.height / 2.0;

    if (overlay.rotation == 0.0) {
      return TransformAlignmentBounds(
        id: overlay.id,
        name: overlay.title,
        type: LayerType.pipVideo,
        left: childCenterX - halfW,
        right: childCenterX + halfW,
        top: childCenterY - halfH,
        bottom: childCenterY + halfH,
        centerX: childCenterX,
        centerY: childCenterY,
      );
    }

    final cosA = math.cos(overlay.rotation);
    final sinA = math.sin(overlay.rotation);
    final p0 = Offset(-halfW, -halfH);
    final p1 = Offset(halfW, -halfH);
    final p2 = Offset(halfW, halfH);
    final p3 = Offset(-halfW, halfH);

    Offset rot(Offset p) => Offset(
          p.dx * cosA - p.dy * sinA + childCenterX,
          p.dx * sinA + p.dy * cosA + childCenterY,
        );

    final t0 = rot(p0);
    final t1 = rot(p1);
    final t2 = rot(p2);
    final t3 = rot(p3);

    final left = math.min(math.min(t0.dx, t1.dx), math.min(t2.dx, t3.dx));
    final right = math.max(math.max(t0.dx, t1.dx), math.max(t2.dx, t3.dx));
    final top = math.min(math.min(t0.dy, t1.dy), math.min(t2.dy, t3.dy));
    final bottom = math.max(math.max(t0.dy, t1.dy), math.max(t2.dy, t3.dy));

    return TransformAlignmentBounds(
      id: overlay.id,
      name: overlay.title,
      type: LayerType.pipVideo,
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      centerX: childCenterX,
      centerY: childCenterY,
    );
  }

  factory TransformAlignmentBounds.fromTextOverlay({
    required TextOverlay text,
    required Size canvasSize,
  }) {
    final approxW = text.boxWidth ?? math.max(80.0, text.text.length * (text.fontSize * 0.55) + 28.0);
    final approxH = text.fontSize + 16.0;

    final childLeft = (canvasSize.width - approxW) * text.position.dx.clamp(0.05, 0.95);
    final childTop = (canvasSize.height - approxH) * text.position.dy.clamp(0.05, 0.95);
    final childCenterX = childLeft + approxW / 2.0 - canvasSize.width / 2.0;
    final childCenterY = childTop + approxH / 2.0 - canvasSize.height / 2.0;
    final halfW = approxW / 2.0;
    final halfH = approxH / 2.0;

    return TransformAlignmentBounds(
      id: text.id,
      name: text.text,
      type: LayerType.text,
      left: childCenterX - halfW,
      right: childCenterX + halfW,
      top: childCenterY - halfH,
      bottom: childCenterY + halfH,
      centerX: childCenterX,
      centerY: childCenterY,
    );
  }

  factory TransformAlignmentBounds.fromStickerOverlay({
    required StickerOverlay sticker,
    required Size canvasSize,
  }) {
    const baseDim = 64.0;
    final scaledDim = baseDim * sticker.scale;
    final halfW = scaledDim / 2.0;
    final halfH = scaledDim / 2.0;

    final childLeft = (canvasSize.width - scaledDim) * sticker.position.dx;
    final childTop = (canvasSize.height - scaledDim) * sticker.position.dy;
    final childCenterX = childLeft + halfW - canvasSize.width / 2.0;
    final childCenterY = childTop + halfH - canvasSize.height / 2.0;

    if (sticker.rotation == 0.0) {
      return TransformAlignmentBounds(
        id: sticker.id,
        name: sticker.preset.label,
        type: LayerType.sticker,
        left: childCenterX - halfW,
        right: childCenterX + halfW,
        top: childCenterY - halfH,
        bottom: childCenterY + halfH,
        centerX: childCenterX,
        centerY: childCenterY,
      );
    }

    final cosA = math.cos(sticker.rotation);
    final sinA = math.sin(sticker.rotation);
    final p0 = Offset(-halfW, -halfH);
    final p1 = Offset(halfW, -halfH);
    final p2 = Offset(halfW, halfH);
    final p3 = Offset(-halfW, halfH);

    Offset rot(Offset p) => Offset(
          p.dx * cosA - p.dy * sinA + childCenterX,
          p.dx * sinA + p.dy * cosA + childCenterY,
        );

    final t0 = rot(p0);
    final t1 = rot(p1);
    final t2 = rot(p2);
    final t3 = rot(p3);

    final left = math.min(math.min(t0.dx, t1.dx), math.min(t2.dx, t3.dx));
    final right = math.max(math.max(t0.dx, t1.dx), math.max(t2.dx, t3.dx));
    final top = math.min(math.min(t0.dy, t1.dy), math.min(t2.dy, t3.dy));
    final bottom = math.max(math.max(t0.dy, t1.dy), math.max(t2.dy, t3.dy));

    return TransformAlignmentBounds(
      id: sticker.id,
      name: sticker.preset.label,
      type: LayerType.sticker,
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      centerX: childCenterX,
      centerY: childCenterY,
    );
  }
}

/// Description of the horizontal alignment target snapped to.
class ActiveSnapTargetX {
  final String targetLayerId;
  final String targetLayerName;
  final LayerType targetLayerType;
  final SnapRelationshipX relationship;
  final double snapCoordinate;
  final double guideCoordinate;

  const ActiveSnapTargetX({
    required this.targetLayerId,
    required this.targetLayerName,
    required this.targetLayerType,
    required this.relationship,
    required this.snapCoordinate,
    required this.guideCoordinate,
  });

  static const none = ActiveSnapTargetX(
    targetLayerId: '',
    targetLayerName: '',
    targetLayerType: LayerType.canvas,
    relationship: SnapRelationshipX.none,
    snapCoordinate: 0.0,
    guideCoordinate: 0.0,
  );

  bool get isSnapped => relationship != SnapRelationshipX.none;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveSnapTargetX &&
          runtimeType == other.runtimeType &&
          targetLayerId == other.targetLayerId &&
          relationship == other.relationship &&
          (snapCoordinate - other.snapCoordinate).abs() < 0.001;

  @override
  int get hashCode => Object.hash(targetLayerId, relationship, snapCoordinate);
}

/// Description of the vertical alignment target snapped to.
class ActiveSnapTargetY {
  final String targetLayerId;
  final String targetLayerName;
  final LayerType targetLayerType;
  final SnapRelationshipY relationship;
  final double snapCoordinate;
  final double guideCoordinate;

  const ActiveSnapTargetY({
    required this.targetLayerId,
    required this.targetLayerName,
    required this.targetLayerType,
    required this.relationship,
    required this.snapCoordinate,
    required this.guideCoordinate,
  });

  static const none = ActiveSnapTargetY(
    targetLayerId: '',
    targetLayerName: '',
    targetLayerType: LayerType.canvas,
    relationship: SnapRelationshipY.none,
    snapCoordinate: 0.0,
    guideCoordinate: 0.0,
  );

  bool get isSnapped => relationship != SnapRelationshipY.none;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveSnapTargetY &&
          runtimeType == other.runtimeType &&
          targetLayerId == other.targetLayerId &&
          relationship == other.relationship &&
          (snapCoordinate - other.snapCoordinate).abs() < 0.001;

  @override
  int get hashCode => Object.hash(targetLayerId, relationship, snapCoordinate);
}

/// Result of evaluating multi-target snapping on both axes.
class SnapEvaluationResult {
  final double effectiveX;
  final double effectiveY;
  final SnapTargetX snapTargetX;
  final SnapTargetY snapTargetY;
  final ActiveSnapTargetX activeSnapTargetX;
  final ActiveSnapTargetY activeSnapTargetY;
  final double? guideX;
  final double? guideY;

  const SnapEvaluationResult({
    required this.effectiveX,
    required this.effectiveY,
    this.snapTargetX = SnapTargetX.none,
    this.snapTargetY = SnapTargetY.none,
    this.activeSnapTargetX = ActiveSnapTargetX.none,
    this.activeSnapTargetY = ActiveSnapTargetY.none,
    this.guideX,
    this.guideY,
  });

  bool get isSnappedX => snapTargetX != SnapTargetX.none || activeSnapTargetX.isSnapped;
  bool get isSnappedY => snapTargetY != SnapTargetY.none || activeSnapTargetY.isSnapped;
}

class _SnapCandidateX {
  final String layerId;
  final String layerName;
  final LayerType layerType;
  final SnapRelationshipX relationship;
  final int priority; // 1: Center, 2: Same-Edge, 3: Opposite-Edge, 4: Canvas Edge
  final double snapTargetX;
  final double guideX;
  final double distance;

  const _SnapCandidateX({
    required this.layerId,
    required this.layerName,
    required this.layerType,
    required this.relationship,
    required this.priority,
    required this.snapTargetX,
    required this.guideX,
    required this.distance,
  });
}

class _SnapCandidateY {
  final String layerId;
  final String layerName;
  final LayerType layerType;
  final SnapRelationshipY relationship;
  final int priority; // 1: Center, 2: Same-Edge, 3: Opposite-Edge, 4: Canvas Edge
  final double snapTargetY;
  final double guideY;
  final double distance;

  const _SnapCandidateY({
    required this.layerId,
    required this.layerName,
    required this.layerType,
    required this.relationship,
    required this.priority,
    required this.snapTargetY,
    required this.guideY,
    required this.distance,
  });
}

/// Pure deterministic snap engine for advanced center & edge alignment across multiple layers.
class TransformSnapEngine {
  /// Calculates visual half-extent on the X-axis for the given scale, rotation, and flips.
  /// (bounds.right - bounds.left) / 2
  static double calculateHalfExtentX({
    required Size canvasSize,
    required double scale,
    required double rotationAngle,
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) {
    final bounds = TransformedVisualBounds.fromTransform(
      canvasSize: canvasSize,
      transform: ClipSpatialTransform(
        clipId: '',
        xPos: 0.0,
        yPos: 0.0,
        scale: scale,
        rotationAngle: rotationAngle,
      ),
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    return (bounds.right - bounds.left) / 2.0;
  }

  /// Calculates visual half-extent on the Y-axis for the given scale, rotation, and flips.
  /// (bounds.bottom - bounds.top) / 2
  static double calculateHalfExtentY({
    required Size canvasSize,
    required double scale,
    required double rotationAngle,
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) {
    final bounds = TransformedVisualBounds.fromTransform(
      canvasSize: canvasSize,
      transform: ClipSpatialTransform(
        clipId: '',
        xPos: 0.0,
        yPos: 0.0,
        scale: scale,
        rotationAngle: rotationAngle,
      ),
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    return (bounds.bottom - bounds.top) / 2.0;
  }

  /// Evaluates snapping against canvas and multiple reference layers.
  static SnapEvaluationResult evaluateMultiLayerSnap({
    required double rawX,
    required double rawY,
    required double scale,
    required double rotationAngle,
    required Size canvasSize,
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
    String activeLayerId = '',
    List<TransformAlignmentBounds> referenceLayers = const [],
    ActiveSnapTargetX currentActiveSnapX = ActiveSnapTargetX.none,
    ActiveSnapTargetY currentActiveSnapY = ActiveSnapTargetY.none,
  }) {
    final halfClipW = calculateHalfExtentX(
      canvasSize: canvasSize,
      scale: scale,
      rotationAngle: rotationAngle,
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    final halfClipH = calculateHalfExtentY(
      canvasSize: canvasSize,
      scale: scale,
      rotationAngle: rotationAngle,
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );

    // Ensure canvas is always evaluated as baseline reference, and exclude active layer itself
    final candidateLayers = <TransformAlignmentBounds>[
      TransformAlignmentBounds.canvas(canvasSize),
      ...referenceLayers.where((l) => l.id.isNotEmpty && l.id != activeLayerId && l.id != '__canvas__'),
    ];

    // 1. Evaluate X axis
    final (effectiveX, activeSnapX, guideX, snapTargetX) = _evaluateMultiLayerAxisX(
      rawX: rawX,
      halfClipW: halfClipW,
      candidateLayers: candidateLayers,
      currentSnap: currentActiveSnapX,
    );

    // 2. Evaluate Y axis
    final (effectiveY, activeSnapY, guideY, snapTargetY) = _evaluateMultiLayerAxisY(
      rawY: rawY,
      halfClipH: halfClipH,
      candidateLayers: candidateLayers,
      currentSnap: currentActiveSnapY,
    );

    return SnapEvaluationResult(
      effectiveX: effectiveX,
      effectiveY: effectiveY,
      snapTargetX: snapTargetX,
      snapTargetY: snapTargetY,
      activeSnapTargetX: activeSnapX,
      activeSnapTargetY: activeSnapY,
      guideX: guideX,
      guideY: guideY,
    );
  }

  static (double, ActiveSnapTargetX, double?, SnapTargetX) _evaluateMultiLayerAxisX({
    required double rawX,
    required double halfClipW,
    required List<TransformAlignmentBounds> candidateLayers,
    required ActiveSnapTargetX currentSnap,
  }) {
    // A. If currently snapped to a target, test hysteresis release against that specific target
    if (currentSnap.isSnapped) {
      final dist = (rawX - currentSnap.snapCoordinate).abs();
      final releaseLimit = (currentSnap.relationship == SnapRelationshipX.canvasCenter ||
              currentSnap.relationship == SnapRelationshipX.centerToCenter)
          ? TransformSnapConfig.centerReleaseThreshold
          : TransformSnapConfig.edgeReleaseThreshold;

      if (dist <= releaseLimit) {
        final snapTargetX = _mapRelationshipToSnapTargetX(currentSnap.relationship);
        return (currentSnap.snapCoordinate, currentSnap, currentSnap.guideCoordinate, snapTargetX);
      }
    }

    // B. Not currently snapped or exceeded release threshold -> Evaluate new snap candidates
    final candidates = <_SnapCandidateX>[];

    for (final ref in candidateLayers) {
      if (ref.type == LayerType.canvas) {
        // 1. Canvas Center: Priority 1
        final distCenter = (rawX - 0.0).abs();
        if (distCenter <= TransformSnapConfig.centerSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.canvasCenter,
            priority: 1,
            snapTargetX: 0.0,
            guideX: 0.0,
            distance: distCenter,
          ));
        }

        // 2. Canvas Left Edge: Priority 4
        final targetLeft = ref.left + halfClipW;
        final distLeft = (rawX - targetLeft).abs();
        if (distLeft <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.canvasLeftEdge,
            priority: 4,
            snapTargetX: targetLeft,
            guideX: ref.left,
            distance: distLeft,
          ));
        }

        // 3. Canvas Right Edge: Priority 4
        final targetRight = ref.right - halfClipW;
        final distRight = (rawX - targetRight).abs();
        if (distRight <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.canvasRightEdge,
            priority: 4,
            snapTargetX: targetRight,
            guideX: ref.right,
            distance: distRight,
          ));
        }
      } else {
        // Multi-Layer alignment against another layer
        // 1. Center-to-Center: Priority 1
        final distCenter = (rawX - ref.centerX).abs();
        if (distCenter <= TransformSnapConfig.centerSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.centerToCenter,
            priority: 1,
            snapTargetX: ref.centerX,
            guideX: ref.centerX,
            distance: distCenter,
          ));
        }

        // 2. Same-Edge: Left-to-Left (Priority 2)
        final targetLeftToLeft = ref.left + halfClipW;
        final distLeftToLeft = (rawX - targetLeftToLeft).abs();
        if (distLeftToLeft <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.leftToLeft,
            priority: 2,
            snapTargetX: targetLeftToLeft,
            guideX: ref.left,
            distance: distLeftToLeft,
          ));
        }

        // 3. Same-Edge: Right-to-Right (Priority 2)
        final targetRightToRight = ref.right - halfClipW;
        final distRightToRight = (rawX - targetRightToRight).abs();
        if (distRightToRight <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.rightToRight,
            priority: 2,
            snapTargetX: targetRightToRight,
            guideX: ref.right,
            distance: distRightToRight,
          ));
        }

        // 4. Opposite-Edge: Left-to-Right (Priority 3)
        final targetLeftToRight = ref.right + halfClipW;
        final distLeftToRight = (rawX - targetLeftToRight).abs();
        if (distLeftToRight <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.leftToRight,
            priority: 3,
            snapTargetX: targetLeftToRight,
            guideX: ref.right,
            distance: distLeftToRight,
          ));
        }

        // 5. Opposite-Edge: Right-to-Left (Priority 3)
        final targetRightToLeft = ref.left - halfClipW;
        final distRightToLeft = (rawX - targetRightToLeft).abs();
        if (distRightToLeft <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateX(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipX.rightToLeft,
            priority: 3,
            snapTargetX: targetRightToLeft,
            guideX: ref.left,
            distance: distRightToLeft,
          ));
        }
      }
    }

    if (candidates.isEmpty) {
      return (rawX, ActiveSnapTargetX.none, null, SnapTargetX.none);
    }

    // Deterministic priority ordering:
    // 1. Priority tier (1: Center, 2: Same-Edge, 3: Opposite-Edge, 4: Canvas Edge)
    // 2. Smaller distance
    // 3. Explicit layer beats Canvas when distance is identical
    // 4. Stable layerId string -> relationship index
    candidates.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority.compareTo(b.priority);
      }
      if ((a.distance - b.distance).abs() > 0.001) {
        return a.distance.compareTo(b.distance);
      }
      final aIsLayer = a.layerType != LayerType.canvas;
      final bIsLayer = b.layerType != LayerType.canvas;
      if (aIsLayer != bIsLayer) {
        return aIsLayer ? -1 : 1;
      }
      final idCmp = a.layerId.compareTo(b.layerId);
      if (idCmp != 0) return idCmp;
      return a.relationship.index.compareTo(b.relationship.index);
    });

    final winner = candidates.first;
    final activeSnap = ActiveSnapTargetX(
      targetLayerId: winner.layerId,
      targetLayerName: winner.layerName,
      targetLayerType: winner.layerType,
      relationship: winner.relationship,
      snapCoordinate: winner.snapTargetX,
      guideCoordinate: winner.guideX,
    );
    final snapTargetX = _mapRelationshipToSnapTargetX(winner.relationship);

    return (winner.snapTargetX, activeSnap, winner.guideX, snapTargetX);
  }

  static (double, ActiveSnapTargetY, double?, SnapTargetY) _evaluateMultiLayerAxisY({
    required double rawY,
    required double halfClipH,
    required List<TransformAlignmentBounds> candidateLayers,
    required ActiveSnapTargetY currentSnap,
  }) {
    // A. If currently snapped to a target, test hysteresis release against that specific target
    if (currentSnap.isSnapped) {
      final dist = (rawY - currentSnap.snapCoordinate).abs();
      final releaseLimit = (currentSnap.relationship == SnapRelationshipY.canvasCenter ||
              currentSnap.relationship == SnapRelationshipY.centerToCenter)
          ? TransformSnapConfig.centerReleaseThreshold
          : TransformSnapConfig.edgeReleaseThreshold;

      if (dist <= releaseLimit) {
        final snapTargetY = _mapRelationshipToSnapTargetY(currentSnap.relationship);
        return (currentSnap.snapCoordinate, currentSnap, currentSnap.guideCoordinate, snapTargetY);
      }
    }

    // B. Not currently snapped or exceeded release threshold -> Evaluate new snap candidates
    final candidates = <_SnapCandidateY>[];

    for (final ref in candidateLayers) {
      if (ref.type == LayerType.canvas) {
        // 1. Canvas Center: Priority 1
        final distCenter = (rawY - 0.0).abs();
        if (distCenter <= TransformSnapConfig.centerSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.canvasCenter,
            priority: 1,
            snapTargetY: 0.0,
            guideY: 0.0,
            distance: distCenter,
          ));
        }

        // 2. Canvas Top Edge: Priority 4
        final targetTop = ref.top + halfClipH;
        final distTop = (rawY - targetTop).abs();
        if (distTop <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.canvasTopEdge,
            priority: 4,
            snapTargetY: targetTop,
            guideY: ref.top,
            distance: distTop,
          ));
        }

        // 3. Canvas Bottom Edge: Priority 4
        final targetBottom = ref.bottom - halfClipH;
        final distBottom = (rawY - targetBottom).abs();
        if (distBottom <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.canvasBottomEdge,
            priority: 4,
            snapTargetY: targetBottom,
            guideY: ref.bottom,
            distance: distBottom,
          ));
        }
      } else {
        // Multi-Layer alignment against another layer
        // 1. Center-to-Center: Priority 1
        final distCenter = (rawY - ref.centerY).abs();
        if (distCenter <= TransformSnapConfig.centerSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.centerToCenter,
            priority: 1,
            snapTargetY: ref.centerY,
            guideY: ref.centerY,
            distance: distCenter,
          ));
        }

        // 2. Same-Edge: Top-to-Top (Priority 2)
        final targetTopToTop = ref.top + halfClipH;
        final distTopToTop = (rawY - targetTopToTop).abs();
        if (distTopToTop <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.topToTop,
            priority: 2,
            snapTargetY: targetTopToTop,
            guideY: ref.top,
            distance: distTopToTop,
          ));
        }

        // 3. Same-Edge: Bottom-to-Bottom (Priority 2)
        final targetBottomToBottom = ref.bottom - halfClipH;
        final distBottomToBottom = (rawY - targetBottomToBottom).abs();
        if (distBottomToBottom <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.bottomToBottom,
            priority: 2,
            snapTargetY: targetBottomToBottom,
            guideY: ref.bottom,
            distance: distBottomToBottom,
          ));
        }

        // 4. Opposite-Edge: Top-to-Bottom (Priority 3)
        final targetTopToBottom = ref.bottom + halfClipH;
        final distTopToBottom = (rawY - targetTopToBottom).abs();
        if (distTopToBottom <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.topToBottom,
            priority: 3,
            snapTargetY: targetTopToBottom,
            guideY: ref.bottom,
            distance: distTopToBottom,
          ));
        }

        // 5. Opposite-Edge: Bottom-to-Top (Priority 3)
        final targetBottomToTop = ref.top - halfClipH;
        final distBottomToTop = (rawY - targetBottomToTop).abs();
        if (distBottomToTop <= TransformSnapConfig.edgeSnapThreshold) {
          candidates.add(_SnapCandidateY(
            layerId: ref.id,
            layerName: ref.name,
            layerType: ref.type,
            relationship: SnapRelationshipY.bottomToTop,
            priority: 3,
            snapTargetY: targetBottomToTop,
            guideY: ref.top,
            distance: distBottomToTop,
          ));
        }
      }
    }

    if (candidates.isEmpty) {
      return (rawY, ActiveSnapTargetY.none, null, SnapTargetY.none);
    }

    // Deterministic priority ordering:
    // 1. Priority tier (1: Center, 2: Same-Edge, 3: Opposite-Edge, 4: Canvas Edge)
    // 2. Smaller distance
    // 3. Explicit layer beats Canvas when distance is identical
    // 4. Stable layerId string -> relationship index
    candidates.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority.compareTo(b.priority);
      }
      if ((a.distance - b.distance).abs() > 0.001) {
        return a.distance.compareTo(b.distance);
      }
      final aIsLayer = a.layerType != LayerType.canvas;
      final bIsLayer = b.layerType != LayerType.canvas;
      if (aIsLayer != bIsLayer) {
        return aIsLayer ? -1 : 1;
      }
      final idCmp = a.layerId.compareTo(b.layerId);
      if (idCmp != 0) return idCmp;
      return a.relationship.index.compareTo(b.relationship.index);
    });

    final winner = candidates.first;
    final activeSnap = ActiveSnapTargetY(
      targetLayerId: winner.layerId,
      targetLayerName: winner.layerName,
      targetLayerType: winner.layerType,
      relationship: winner.relationship,
      snapCoordinate: winner.snapTargetY,
      guideCoordinate: winner.guideY,
    );
    final snapTargetY = _mapRelationshipToSnapTargetY(winner.relationship);

    return (winner.snapTargetY, activeSnap, winner.guideY, snapTargetY);
  }

  static SnapTargetX _mapRelationshipToSnapTargetX(SnapRelationshipX rel) {
    switch (rel) {
      case SnapRelationshipX.canvasCenter:
      case SnapRelationshipX.centerToCenter:
        return SnapTargetX.centerX;
      case SnapRelationshipX.canvasLeftEdge:
        return SnapTargetX.leftEdge;
      case SnapRelationshipX.canvasRightEdge:
        return SnapTargetX.rightEdge;
      case SnapRelationshipX.leftToLeft:
      case SnapRelationshipX.rightToRight:
      case SnapRelationshipX.leftToRight:
      case SnapRelationshipX.rightToLeft:
      case SnapRelationshipX.none:
        return SnapTargetX.none;
    }
  }

  static SnapTargetY _mapRelationshipToSnapTargetY(SnapRelationshipY rel) {
    switch (rel) {
      case SnapRelationshipY.canvasCenter:
      case SnapRelationshipY.centerToCenter:
        return SnapTargetY.centerY;
      case SnapRelationshipY.canvasTopEdge:
        return SnapTargetY.topEdge;
      case SnapRelationshipY.canvasBottomEdge:
        return SnapTargetY.bottomEdge;
      case SnapRelationshipY.topToTop:
      case SnapRelationshipY.bottomToBottom:
      case SnapRelationshipY.topToBottom:
      case SnapRelationshipY.bottomToTop:
      case SnapRelationshipY.none:
        return SnapTargetY.none;
    }
  }

  /// Backward-compatible evaluateSnap delegating directly to [evaluateMultiLayerSnap].
  static SnapEvaluationResult evaluateSnap({
    required double rawX,
    required double rawY,
    required double scale,
    required double rotationAngle,
    required Size canvasSize,
    int legacyRotationDegrees = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
    SnapTargetX currentSnapX = SnapTargetX.none,
    SnapTargetY currentSnapY = SnapTargetY.none,
  }) {
    final halfClipW = calculateHalfExtentX(
      canvasSize: canvasSize,
      scale: scale,
      rotationAngle: rotationAngle,
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    final halfClipH = calculateHalfExtentY(
      canvasSize: canvasSize,
      scale: scale,
      rotationAngle: rotationAngle,
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    final halfCanvasW = canvasSize.width / 2.0;
    final halfCanvasH = canvasSize.height / 2.0;

    ActiveSnapTargetX initialActiveX = ActiveSnapTargetX.none;
    if (currentSnapX == SnapTargetX.centerX) {
      initialActiveX = const ActiveSnapTargetX(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipX.canvasCenter,
        snapCoordinate: 0.0,
        guideCoordinate: 0.0,
      );
    } else if (currentSnapX == SnapTargetX.leftEdge) {
      initialActiveX = ActiveSnapTargetX(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipX.canvasLeftEdge,
        snapCoordinate: -halfCanvasW + halfClipW,
        guideCoordinate: -halfCanvasW,
      );
    } else if (currentSnapX == SnapTargetX.rightEdge) {
      initialActiveX = ActiveSnapTargetX(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipX.canvasRightEdge,
        snapCoordinate: halfCanvasW - halfClipW,
        guideCoordinate: halfCanvasW,
      );
    }

    ActiveSnapTargetY initialActiveY = ActiveSnapTargetY.none;
    if (currentSnapY == SnapTargetY.centerY) {
      initialActiveY = const ActiveSnapTargetY(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipY.canvasCenter,
        snapCoordinate: 0.0,
        guideCoordinate: 0.0,
      );
    } else if (currentSnapY == SnapTargetY.topEdge) {
      initialActiveY = ActiveSnapTargetY(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipY.canvasTopEdge,
        snapCoordinate: -halfCanvasH + halfClipH,
        guideCoordinate: -halfCanvasH,
      );
    } else if (currentSnapY == SnapTargetY.bottomEdge) {
      initialActiveY = ActiveSnapTargetY(
        targetLayerId: '__canvas__',
        targetLayerName: 'Canvas',
        targetLayerType: LayerType.canvas,
        relationship: SnapRelationshipY.canvasBottomEdge,
        snapCoordinate: halfCanvasH - halfClipH,
        guideCoordinate: halfCanvasH,
      );
    }

    return evaluateMultiLayerSnap(
      rawX: rawX,
      rawY: rawY,
      scale: scale,
      rotationAngle: rotationAngle,
      canvasSize: canvasSize,
      legacyRotationDegrees: legacyRotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      currentActiveSnapX: initialActiveX,
      currentActiveSnapY: initialActiveY,
      referenceLayers: const [],
    );
  }
}
