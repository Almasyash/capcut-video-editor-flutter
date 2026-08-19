import 'package:flutter/material.dart';

/// Immutable model representing an individual video segment/clip on the timeline
class VideoClip {
  final String id;
  final String title;
  final Duration originalDuration;
  final Duration trimStart;
  final Duration trimEnd;
  final double speed;
  final double volume;
  final List<Color> previewGradient;
  final IconData previewIcon;
  final String? assetPath;

  const VideoClip({
    required this.id,
    required this.title,
    required this.originalDuration,
    required this.trimStart,
    required this.trimEnd,
    this.speed = 1.0,
    this.volume = 1.0,
    required this.previewGradient,
    this.previewIcon = Icons.movie_creation_outlined,
    this.assetPath,
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
    String? title,
    Duration? originalDuration,
    Duration? trimStart,
    Duration? trimEnd,
    double? speed,
    double? volume,
    List<Color>? previewGradient,
    IconData? previewIcon,
    String? assetPath,
  }) {
    return VideoClip(
      id: id ?? this.id,
      title: title ?? this.title,
      originalDuration: originalDuration ?? this.originalDuration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      previewGradient: previewGradient ?? this.previewGradient,
      previewIcon: previewIcon ?? this.previewIcon,
      assetPath: assetPath ?? this.assetPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoClip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          trimStart == other.trimStart &&
          trimEnd == other.trimEnd &&
          speed == other.speed &&
          volume == other.volume;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      trimStart.hashCode ^
      trimEnd.hashCode ^
      speed.hashCode ^
      volume.hashCode;
}
