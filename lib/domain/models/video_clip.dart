import 'package:flutter/material.dart';

/// Immutable model representing an individual video segment/clip on the timeline
class VideoClip {
  final String id;

  /// Canonical reference to the source MediaAsset in central MediaLibrary
  final String assetId;

  final String title;
  final Duration originalDuration;
  final Duration trimStart;
  final Duration trimEnd;
  final double speed;
  final double volume;
  final double opacity; // 0.0 to 1.0
  final int rotationDegrees; // 0, 90, 180, 270
  final bool flipHorizontal;
  final bool flipVertical;
  final bool isReversed;
  final bool isFrozen;
  final List<Color> previewGradient;
  final IconData previewIcon;

  const VideoClip({
    required this.id,
    required this.assetId,
    required this.title,
    required this.originalDuration,
    required this.trimStart,
    required this.trimEnd,
    this.speed = 1.0,
    this.volume = 1.0,
    this.opacity = 1.0,
    this.rotationDegrees = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.isReversed = false,
    this.isFrozen = false,
    required this.previewGradient,
    this.previewIcon = Icons.movie_creation_outlined,
  });

  /// Effective duration on the timeline after trimming and speed adjustment
  Duration get activeDuration {
    final trimmedMs = (trimEnd.inMilliseconds - trimStart.inMilliseconds).clamp(0, originalDuration.inMilliseconds);
    final adjustedMs = (trimmedMs / (speed > 0 ? speed : 1.0)).round();
    return Duration(milliseconds: adjustedMs);
  }

  /// Active duration in seconds (double)
  double get durationInSeconds => activeDuration.inMilliseconds / 1000.0;

  VideoClip copyWith({
    String? id,
    String? assetId,
    String? title,
    Duration? originalDuration,
    Duration? trimStart,
    Duration? trimEnd,
    double? speed,
    double? volume,
    double? opacity,
    int? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    bool? isReversed,
    bool? isFrozen,
    List<Color>? previewGradient,
    IconData? previewIcon,
  }) {
    return VideoClip(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      title: title ?? this.title,
      originalDuration: originalDuration ?? this.originalDuration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      opacity: opacity ?? this.opacity,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      isReversed: isReversed ?? this.isReversed,
      isFrozen: isFrozen ?? this.isFrozen,
      previewGradient: previewGradient ?? this.previewGradient,
      previewIcon: previewIcon ?? this.previewIcon,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'title': title,
      'originalDurationMs': originalDuration.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'trimEndMs': trimEnd.inMilliseconds,
      'speed': speed,
      'volume': volume,
      'opacity': opacity,
      'rotationDegrees': rotationDegrees,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'isReversed': isReversed,
      'isFrozen': isFrozen,
    };
  }

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    return VideoClip(
      id: json['id'] as String,
      assetId: json['assetId'] as String? ?? '',
      title: json['title'] as String? ?? 'Video Clip',
      originalDuration: Duration(milliseconds: (json['originalDurationMs'] as num?)?.toInt() ?? 5000),
      trimStart: Duration(milliseconds: (json['trimStartMs'] as num?)?.toInt() ?? 0),
      trimEnd: Duration(milliseconds: (json['trimEndMs'] as num?)?.toInt() ?? (json['originalDurationMs'] as num?)?.toInt() ?? 5000),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      rotationDegrees: (json['rotationDegrees'] as num?)?.toInt() ?? 0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      isReversed: json['isReversed'] as bool? ?? false,
      isFrozen: json['isFrozen'] as bool? ?? false,
      previewGradient: const [Color(0xFF141E30), Color(0xFF243B55)],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoClip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          assetId == other.assetId &&
          title == other.title &&
          trimStart == other.trimStart &&
          trimEnd == other.trimEnd &&
          speed == other.speed &&
          volume == other.volume &&
          opacity == other.opacity &&
          rotationDegrees == other.rotationDegrees &&
          flipHorizontal == other.flipHorizontal &&
          flipVertical == other.flipVertical &&
          isReversed == other.isReversed &&
          isFrozen == other.isFrozen;

  @override
  int get hashCode =>
      id.hashCode ^
      assetId.hashCode ^
      title.hashCode ^
      trimStart.hashCode ^
      trimEnd.hashCode ^
      speed.hashCode ^
      volume.hashCode ^
      opacity.hashCode ^
      rotationDegrees.hashCode ^
      flipHorizontal.hashCode ^
      flipVertical.hashCode ^
      isReversed.hashCode ^
      isFrozen.hashCode;
}
