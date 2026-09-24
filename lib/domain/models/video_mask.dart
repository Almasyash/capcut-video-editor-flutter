import 'package:flutter/material.dart';

enum MaskType {
  none,
  split,
  filmstrip,
  rectangle,
  circle,
  heart,
  star,
}

extension MaskTypeExtension on MaskType {
  String get displayName {
    switch (this) {
      case MaskType.none:
        return 'None';
      case MaskType.split:
        return 'Split';
      case MaskType.filmstrip:
        return 'Filmstrip';
      case MaskType.rectangle:
        return 'Rectangle';
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
      case MaskType.split:
        return Icons.splitscreen_rounded;
      case MaskType.filmstrip:
        return Icons.view_stream_rounded;
      case MaskType.rectangle:
        return Icons.crop_square_rounded;
      case MaskType.circle:
        return Icons.circle_outlined;
      case MaskType.heart:
        return Icons.favorite_border_rounded;
      case MaskType.star:
        return Icons.star_border_rounded;
    }
  }
}

class VideoMask {
  final MaskType type;
  final double size; // 0.1 to 2.0
  final double feather; // 0.0 to 50.0 (blur softness)
  final double positionX; // Normalized center X (-1.0 to 1.0)
  final double positionY; // Normalized center Y (-1.0 to 1.0)
  final double rotation; // In degrees (-180 to 180)
  final bool inverted;

  const VideoMask({
    this.type = MaskType.none,
    this.size = 1.0,
    this.feather = 0.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
    this.rotation = 0.0,
    this.inverted = false,
  });

  bool get isActive => type != MaskType.none;

  VideoMask copyWith({
    MaskType? type,
    double? size,
    double? feather,
    double? positionX,
    double? positionY,
    double? rotation,
    bool? inverted,
  }) {
    return VideoMask(
      type: type ?? this.type,
      size: size ?? this.size,
      feather: feather ?? this.feather,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      rotation: rotation ?? this.rotation,
      inverted: inverted ?? this.inverted,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'size': size,
    'feather': feather,
    'positionX': positionX,
    'positionY': positionY,
    'rotation': rotation,
    'inverted': inverted,
  };

  factory VideoMask.fromJson(Map<String, dynamic> json) {
    return VideoMask(
      type: MaskType.values.firstWhere(
        (m) => m.name == json['type'],
        orElse: () => MaskType.none,
      ),
      size: (json['size'] as num?)?.toDouble() ?? 1.0,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.0,
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      inverted: json['inverted'] as bool? ?? false,
    );
  }
}
