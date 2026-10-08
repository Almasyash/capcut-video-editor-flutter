import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';

/// Available geometric mask types for compositing
enum MaskType {
  none,
  rectangle,
  ellipse,
  polygon,
  linear,
  radial,
  // Legacy / preset shape types for 100% backward compatibility
  split,
  filmstrip,
  circle,
  heart,
  star,
}

extension MaskTypeExtension on MaskType {
  String get displayName {
    switch (this) {
      case MaskType.none:
        return 'None';
      case MaskType.rectangle:
        return 'Rectangle';
      case MaskType.ellipse:
        return 'Ellipse';
      case MaskType.polygon:
        return 'Polygon';
      case MaskType.linear:
        return 'Linear';
      case MaskType.radial:
        return 'Radial';
      case MaskType.split:
        return 'Split';
      case MaskType.filmstrip:
        return 'Filmstrip';
      case MaskType.circle:
        return 'Circle';
      case MaskType.heart:
        return 'Heart';
      case MaskType.star:
        return 'Star';
    }
  }

  IconData get icon {
    switch (this) {
      case MaskType.none:
        return Icons.block_rounded;
      case MaskType.rectangle:
        return Icons.crop_square_rounded;
      case MaskType.ellipse:
        return Icons.circle_outlined;
      case MaskType.polygon:
        return Icons.polyline_rounded;
      case MaskType.linear:
        return Icons.linear_scale_rounded;
      case MaskType.radial:
        return Icons.blur_circular_rounded;
      case MaskType.split:
        return Icons.splitscreen_rounded;
      case MaskType.filmstrip:
        return Icons.view_stream_rounded;
      case MaskType.circle:
        return Icons.circle_outlined;
      case MaskType.heart:
        return Icons.favorite_border_rounded;
      case MaskType.star:
        return Icons.star_border_rounded;
    }
  }
}

/// Boolean combination modes for multi-mask evaluation
enum MaskCombineMode {
  add, // Union (A + B)
  intersect, // Intersection (A ∩ B)
  subtract, // Difference (A - B)
  xor, // Symmetric Difference (A ⊕ B)
}

extension MaskCombineModeExtension on MaskCombineMode {
  String get displayName {
    switch (this) {
      case MaskCombineMode.add:
        return 'Add';
      case MaskCombineMode.intersect:
        return 'Intersect';
      case MaskCombineMode.subtract:
        return 'Subtract';
      case MaskCombineMode.xor:
        return 'Difference';
    }
  }

  PathOperation get pathOperation {
    switch (this) {
      case MaskCombineMode.add:
        return PathOperation.union;
      case MaskCombineMode.intersect:
        return PathOperation.intersect;
      case MaskCombineMode.subtract:
        return PathOperation.difference;
      case MaskCombineMode.xor:
        return PathOperation.xor;
    }
  }
}

/// Production Mask Model for Editor FS v1.6.0
/// Supports 5 standard geometries (rectangle, ellipse, polygon, linear, radial)
/// plus legacy shapes, feathering, inversion, expansion, multi-mask combination,
/// and keyframe animation integration.
class VideoMask {
  final String? _id;
  final String? _name;
  final MaskType type;
  final bool enabled;
  final bool inverted;
  final double opacity; // 0.0 to 1.0
  final double feather; // 0.0 to 100.0 (edge softness)
  final double expansion; // -100.0 to 100.0 (boundary dilation/erosion)
  final double positionX; // Normalized center X (-1.0 to 1.0)
  final double positionY; // Normalized center Y (-1.0 to 1.0)
  final double scale; // Uniform scale (0.05 to 10.0)
  final double size; // Legacy alias to scale
  final double rotation; // In degrees (-360 to 360)
  final double width; // Normalized width (0.01 to 2.0)
  final double height; // Normalized height (0.01 to 2.0)
  final double? rectWidth; // Legacy field
  final double? rectHeight; // Legacy field
  final double cornerRadius; // Rectangle corner rounding (0.0 to 100.0)
  final MaskCombineMode combineMode;
  final List<Offset> points; // Polygon points (normalized coordinates [-0.5, 0.5])
  final Offset linearStart; // Linear mask start point
  final Offset linearEnd; // Linear mask end point
  final Offset radialCenter; // Radial mask center
  final double radialRadius; // Radial mask radius (0.01 to 2.0)
  final KeyframeTrackGroup? keyframeTracks;

  String get id => _id ?? 'mask_${identityHashCode(this)}';
  String get name => _name ?? (type == MaskType.none ? 'No Mask' : '${type.displayName} Mask');
  double get effectiveScale => (scale != 1.0 ? scale : size).clamp(0.05, 10.0);

  const VideoMask({
    String? id,
    String? name,
    this.type = MaskType.none,
    this.enabled = true,
    this.inverted = false,
    this.opacity = 1.0,
    this.feather = 0.0,
    this.expansion = 0.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.scale = 1.0,
    this.size = 1.0,
    this.rotation = 0.0,
    this.width = 0.5,
    this.height = 0.5,
    this.rectWidth,
    this.rectHeight,
    this.cornerRadius = 0.0,
    this.combineMode = MaskCombineMode.add,
    this.points = defaultPolygonPoints,
    this.linearStart = const Offset(-0.35, 0.0),
    this.linearEnd = const Offset(0.35, 0.0),
    this.radialCenter = Offset.zero,
    this.radialRadius = 0.35,
    this.keyframeTracks,
  })  : _id = id,
        _name = name;

  static const List<Offset> defaultPolygonPoints = [
    Offset(0.0, -0.35), // Top
    Offset(0.35, -0.1), // Top Right
    Offset(0.22, 0.35), // Bottom Right
    Offset(-0.22, 0.35), // Bottom Left
    Offset(-0.35, -0.1), // Top Left
  ];

  bool get isActive => enabled && type != MaskType.none;

  VideoMask copyWith({
    String? id,
    String? name,
    MaskType? type,
    bool? enabled,
    bool? inverted,
    double? opacity,
    double? feather,
    double? expansion,
    double? positionX,
    double? positionY,
    double? scale,
    double? size,
    double? rotation,
    double? width,
    double? height,
    double? rectWidth,
    double? rectHeight,
    double? cornerRadius,
    MaskCombineMode? combineMode,
    List<Offset>? points,
    Offset? linearStart,
    Offset? linearEnd,
    Offset? radialCenter,
    double? radialRadius,
    KeyframeTrackGroup? keyframeTracks,
  }) {
    return VideoMask(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      inverted: inverted ?? this.inverted,
      opacity: opacity ?? this.opacity,
      feather: feather ?? this.feather,
      expansion: expansion ?? this.expansion,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      scale: scale ?? (size ?? this.scale),
      size: size ?? (scale ?? this.size),
      rotation: rotation ?? this.rotation,
      width: width ?? (rectWidth ?? this.width),
      height: height ?? (rectHeight ?? this.height),
      rectWidth: rectWidth ?? this.rectWidth,
      rectHeight: rectHeight ?? this.rectHeight,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      combineMode: combineMode ?? this.combineMode,
      points: points ?? this.points,
      linearStart: linearStart ?? this.linearStart,
      linearEnd: linearEnd ?? this.linearEnd,
      radialCenter: radialCenter ?? this.radialCenter,
      radialRadius: radialRadius ?? this.radialRadius,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
    );
  }

  /// Evaluates animated mask state at the given time in seconds
  VideoMask evaluateAt(double timeInSeconds) {
    if (keyframeTracks == null || keyframeTracks!.isEmpty) return this;
    final tracks = keyframeTracks!;
    return copyWith(
      positionX: tracks.evaluate(AnimatableProperty.maskPositionX, timeInSeconds, fallback: positionX),
      positionY: tracks.evaluate(AnimatableProperty.maskPositionY, timeInSeconds, fallback: positionY),
      scale: tracks.evaluate(AnimatableProperty.maskScale, timeInSeconds, fallback: scale),
      rotation: tracks.evaluate(AnimatableProperty.maskRotation, timeInSeconds, fallback: rotation),
      opacity: tracks.evaluate(AnimatableProperty.maskOpacity, timeInSeconds, fallback: opacity),
      feather: tracks.evaluate(AnimatableProperty.maskFeather, timeInSeconds, fallback: feather),
      expansion: tracks.evaluate(AnimatableProperty.maskExpansion, timeInSeconds, fallback: expansion),
      width: tracks.evaluate(AnimatableProperty.maskWidth, timeInSeconds, fallback: width),
      height: tracks.evaluate(AnimatableProperty.maskHeight, timeInSeconds, fallback: height),
    );
  }

  /// Generates the mathematical Path in canvas dimensions
  Path toPath(Size canvasSize) {
    if (type == MaskType.none) {
      return Path()..addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
    }

    final double cx = canvasSize.width / 2.0 + (positionX * canvasSize.width / 2.0);
    final double cy = canvasSize.height / 2.0 + (positionY * canvasSize.height / 2.0);
    final Offset center = Offset(cx, cy);

    final double effectiveScale = scale * (size != 1.0 && scale == 1.0 ? size : scale);
    final double expPixel = expansion * (canvasSize.shortestSide / 200.0);

    final double w = (canvasSize.width * width * effectiveScale + expPixel * 2).clamp(2.0, canvasSize.width * 4.0);
    final double h = (canvasSize.height * height * effectiveScale + expPixel * 2).clamp(2.0, canvasSize.height * 4.0);

    Path rawPath = Path();

    switch (type) {
      case MaskType.none:
        rawPath.addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
        break;

      case MaskType.rectangle:
        final rect = Rect.fromCenter(center: center, width: w, height: h);
        if (cornerRadius > 0.0) {
          rawPath.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)));
        } else {
          rawPath.addRect(rect);
        }
        break;

      case MaskType.ellipse:
      case MaskType.circle:
        final rect = Rect.fromCenter(center: center, width: w, height: h);
        rawPath.addOval(rect);
        break;

      case MaskType.polygon:
        if (points.length >= 3) {
          final matrix = Matrix4.identity()
            ..translate(center.dx, center.dy)
            ..rotateZ(rotation * math.pi / 180.0)
            ..scale(canvasSize.width * effectiveScale, canvasSize.height * effectiveScale);

          final transformedPoints = points.map((p) {
            final vec = matrix.transform3Boxed(Vector3(p.dx, p.dy, 0.0));
            return Offset(vec.x, vec.y);
          }).toList();

          rawPath.moveTo(transformedPoints.first.dx, transformedPoints.first.dy);
          for (int i = 1; i < transformedPoints.length; i++) {
            rawPath.lineTo(transformedPoints[i].dx, transformedPoints[i].dy);
          }
          rawPath.close();
          // Skip standard rotation transform since polygon applies rotation matrix above
          return _finalizePath(rawPath, canvasSize, skipRotation: true);
        }
        break;

      case MaskType.linear:
        // Half-plane defined by normal from linearStart to linearEnd
        final pStart = Offset(
          canvasSize.width / 2.0 + linearStart.dx * canvasSize.width,
          canvasSize.height / 2.0 + linearStart.dy * canvasSize.height,
        );
        final pEnd = Offset(
          canvasSize.width / 2.0 + linearEnd.dx * canvasSize.width,
          canvasSize.height / 2.0 + linearEnd.dy * canvasSize.height,
        );
        final dir = pEnd - pStart;
        final angle = math.atan2(dir.dy, dir.dx);
        final normalAngle = angle + math.pi / 2.0;

        final mid = Offset((pStart.dx + pEnd.dx) / 2.0, (pStart.dy + pEnd.dy) / 2.0);
        final span = canvasSize.longestSide * 4.0;
        final p1 = mid + Offset(math.cos(normalAngle) * span, math.sin(normalAngle) * span);
        final p2 = mid - Offset(math.cos(normalAngle) * span, math.sin(normalAngle) * span);
        final p3 = p2 + Offset(math.cos(angle) * span, math.sin(angle) * span);
        final p4 = p1 + Offset(math.cos(angle) * span, math.sin(angle) * span);

        rawPath.moveTo(p1.dx, p1.dy);
        rawPath.lineTo(p2.dx, p2.dy);
        rawPath.lineTo(p3.dx, p3.dy);
        rawPath.lineTo(p4.dx, p4.dy);
        rawPath.close();
        break;

      case MaskType.radial:
        final rCenter = Offset(
          canvasSize.width / 2.0 + radialCenter.dx * canvasSize.width,
          canvasSize.height / 2.0 + radialCenter.dy * canvasSize.height,
        );
        final radius = (canvasSize.shortestSide * radialRadius * effectiveScale + expPixel).clamp(2.0, canvasSize.longestSide * 2.0);
        rawPath.addOval(Rect.fromCircle(center: rCenter, radius: radius));
        break;

      case MaskType.split:
        final splitH = canvasSize.height * 0.5 * effectiveScale + canvasSize.height * 0.25;
        rawPath.addRect(Rect.fromLTWH(0, 0, canvasSize.width, splitH));
        break;

      case MaskType.filmstrip:
        final barHeight = (canvasSize.height * (1.0 - effectiveScale.clamp(0.2, 0.9))) / 2.0;
        rawPath.addRect(Rect.fromLTWH(0, barHeight, canvasSize.width, canvasSize.height - barHeight * 2.0));
        break;

      case MaskType.heart:
        final scaleVal = effectiveScale;
        final hw = center.dx;
        final hh = center.dy;
        rawPath.moveTo(hw, hh + 40.0 * scaleVal);
        rawPath.cubicTo(hw - 60.0 * scaleVal, hh, hw - 60.0 * scaleVal, hh - 40.0 * scaleVal, hw, hh - 15.0 * scaleVal);
        rawPath.cubicTo(hw + 60.0 * scaleVal, hh - 40.0 * scaleVal, hw + 60.0 * scaleVal, hh, hw, hh + 40.0 * scaleVal);
        rawPath.close();
        break;

      case MaskType.star:
        final outerR = w / 2.0;
        final innerR = outerR * 0.45;
        for (int i = 0; i < 5; i++) {
          final outerAngle = -math.pi / 2.0 + (i * 2.0 * math.pi / 5.0);
          final innerAngle = outerAngle + math.pi / 5.0;
          final ox = center.dx + outerR * math.cos(outerAngle);
          final oy = center.dy + outerR * math.sin(outerAngle);
          final ix = center.dx + innerR * math.cos(innerAngle);
          final iy = center.dy + innerR * math.sin(innerAngle);
          if (i == 0) {
            rawPath.moveTo(ox, oy);
          } else {
            rawPath.lineTo(ox, oy);
          }
          rawPath.lineTo(ix, iy);
        }
        rawPath.close();
        break;
    }

    return _finalizePath(rawPath, canvasSize, center: center);
  }

  Path _finalizePath(Path path, Size canvasSize, {Offset? center, bool skipRotation = false}) {
    Path finalPath = path;
    if (!skipRotation && rotation != 0.0 && center != null) {
      final rad = rotation * math.pi / 180.0;
      final matrix = Matrix4.identity()
        ..translate(center.dx, center.dy)
        ..rotateZ(rad)
        ..translate(-center.dx, -center.dy);
      finalPath = path.transform(matrix.storage);
    }

    if (inverted) {
      final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
      return Path.combine(PathOperation.difference, fullRect, finalPath);
    }

    return finalPath;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'enabled': enabled,
        'inverted': inverted,
        'opacity': opacity,
        'feather': feather,
        'expansion': expansion,
        'positionX': positionX,
        'positionY': positionY,
        'scale': scale,
        'size': size,
        'rotation': rotation,
        'width': width,
        'height': height,
        if (rectWidth != null) 'rectWidth': rectWidth,
        if (rectHeight != null) 'rectHeight': rectHeight,
        'cornerRadius': cornerRadius,
        'combineMode': combineMode.name,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'linearStartX': linearStart.dx,
        'linearStartY': linearStart.dy,
        'linearEndX': linearEnd.dx,
        'linearEndY': linearEnd.dy,
        'radialCenterX': radialCenter.dx,
        'radialCenterY': radialCenter.dy,
        'radialRadius': radialRadius,
        if (keyframeTracks != null) 'keyframeTracks': keyframeTracks!.toJson(),
      };

  factory VideoMask.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'none';
    final type = MaskType.values.firstWhere(
      (m) => m.name == typeName,
      orElse: () => MaskType.none,
    );

    final combineName = json['combineMode'] as String? ?? 'add';
    final combineMode = MaskCombineMode.values.firstWhere(
      (c) => c.name == combineName,
      orElse: () => MaskCombineMode.add,
    );

    List<Offset>? points;
    if (json['points'] is List) {
      final list = json['points'] as List<dynamic>;
      points = list.map((item) {
        if (item is Map) {
          final x = (item['x'] as num?)?.toDouble() ?? 0.0;
          final y = (item['y'] as num?)?.toDouble() ?? 0.0;
          return Offset(x, y);
        } else if (item is List && item.length >= 2) {
          final x = (item[0] as num?)?.toDouble() ?? 0.0;
          final y = (item[1] as num?)?.toDouble() ?? 0.0;
          return Offset(x, y);
        }
        return Offset.zero;
      }).toList();
    }

    KeyframeTrackGroup? keyframes;
    if (json['keyframeTracks'] is Map<String, dynamic>) {
      keyframes = KeyframeTrackGroup.fromJson(json['keyframeTracks'] as Map<String, dynamic>);
    }

    return VideoMask(
      id: json['id'] as String?,
      name: json['name'] as String?,
      type: type,
      enabled: json['enabled'] as bool? ?? true,
      inverted: json['inverted'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.0,
      expansion: (json['expansion'] as num?)?.toDouble() ?? 0.0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? ((json['size'] as num?)?.toDouble() ?? 1.0),
      size: (json['size'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? ((json['rectWidth'] as num?)?.toDouble() ?? 0.5),
      height: (json['height'] as num?)?.toDouble() ?? ((json['rectHeight'] as num?)?.toDouble() ?? 0.5),
      rectWidth: (json['rectWidth'] as num?)?.toDouble(),
      rectHeight: (json['rectHeight'] as num?)?.toDouble(),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0.0,
      combineMode: combineMode,
      points: points ?? defaultPolygonPoints,
      linearStart: (json['linearStartX'] != null && json['linearStartY'] != null)
          ? Offset((json['linearStartX'] as num).toDouble(), (json['linearStartY'] as num).toDouble())
          : const Offset(-0.35, 0.0),
      linearEnd: (json['linearEndX'] != null && json['linearEndY'] != null)
          ? Offset((json['linearEndX'] as num).toDouble(), (json['linearEndY'] as num).toDouble())
          : const Offset(0.35, 0.0),
      radialCenter: (json['radialCenterX'] != null && json['radialCenterY'] != null)
          ? Offset((json['radialCenterX'] as num).toDouble(), (json['radialCenterY'] as num).toDouble())
          : Offset.zero,
      radialRadius: (json['radialRadius'] as num?)?.toDouble() ?? 0.35,
      keyframeTracks: keyframes,
    );
  }
}

/// Helper 3D vector for polygon matrix transformations without extra dependencies
class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);
}

extension Matrix4Vector3Extension on Matrix4 {
  Vector3 transform3Boxed(Vector3 arg) {
    final s = storage;
    final x = arg.x;
    final y = arg.y;
    final z = arg.z;
    final rx = s[0] * x + s[4] * y + s[8] * z + s[12];
    final ry = s[1] * x + s[5] * y + s[9] * z + s[13];
    final rz = s[2] * x + s[6] * y + s[10] * z + s[14];
    return Vector3(rx, ry, rz);
  }
}

/// Type alias for MaskDefinition
typedef MaskDefinition = VideoMask;
