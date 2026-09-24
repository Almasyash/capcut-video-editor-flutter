import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';

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
  final SpeedCurve? speedCurve;
  final double volume;
  final bool isMuted;
  final double opacity; // 0.0 to 1.0
  final int rotationDegrees; // 0, 90, 180, 270
  final bool flipHorizontal;
  final bool flipVertical;
  final bool isReversed;
  final bool isFrozen;
  final List<Color> previewGradient;
  final IconData previewIcon;
  final List<VideoKeyframe> keyframes;
  final VideoMask? mask;
  final BlendMode blendMode;

  /// Spatial transformation properties (Free Transform Canvas)
  /// Horizontal position offset relative to canvas center (default 0.0)
  final double xPos;

  /// Vertical position offset relative to canvas center (default 0.0)
  final double yPos;

  /// Uniform spatial scale factor (default 1.0, positive value)
  final double scale;

  /// Spatial rotation angle in radians (default 0.0)
  final double rotationAngle;

  const VideoClip({
    required this.id,
    required this.assetId,
    required this.title,
    required this.originalDuration,
    required this.trimStart,
    required this.trimEnd,
    this.speed = 1.0,
    this.speedCurve,
    this.volume = 1.0,
    this.isMuted = false,
    this.opacity = 1.0,
    this.rotationDegrees = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.isReversed = false,
    this.isFrozen = false,
    required this.previewGradient,
    this.previewIcon = Icons.movie_creation_outlined,
    this.xPos = 0.0,
    this.yPos = 0.0,
    this.scale = 1.0,
    this.rotationAngle = 0.0,
    this.keyframes = const [],
    this.mask,
    this.blendMode = BlendMode.srcOver,
  });

  /// Effective playback volume respecting mute state
  double get effectiveVolume => isMuted ? 0.0 : volume;

  /// Effective duration on the timeline after trimming and speed adjustment
  Duration get activeDuration {
    final trimmedMs = (trimEnd.inMilliseconds - trimStart.inMilliseconds).clamp(0, originalDuration.inMilliseconds);
    final effectiveSpeed = (speedCurve != null) ? speedCurve!.averageSpeed : (speed > 0 ? speed : 1.0);
    final adjustedMs = (trimmedMs / (effectiveSpeed > 0 ? effectiveSpeed : 1.0)).round();
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
    SpeedCurve? speedCurve,
    bool clearSpeedCurve = false,
    double? volume,
    bool? isMuted,
    double? opacity,
    int? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    bool? isReversed,
    bool? isFrozen,
    List<Color>? previewGradient,
    IconData? previewIcon,
    double? xPos,
    double? yPos,
    double? scale,
    double? rotationAngle,
    List<VideoKeyframe>? keyframes,
    VideoMask? mask,
    bool clearMask = false,
    BlendMode? blendMode,
  }) {
    return VideoClip(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      title: title ?? this.title,
      originalDuration: originalDuration ?? this.originalDuration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speed: speed ?? this.speed,
      speedCurve: clearSpeedCurve ? null : (speedCurve ?? this.speedCurve),
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      opacity: opacity ?? this.opacity,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      isReversed: isReversed ?? this.isReversed,
      isFrozen: isFrozen ?? this.isFrozen,
      previewGradient: previewGradient ?? this.previewGradient,
      previewIcon: previewIcon ?? this.previewIcon,
      xPos: xPos ?? this.xPos,
      yPos: yPos ?? this.yPos,
      scale: scale ?? this.scale,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      keyframes: keyframes ?? this.keyframes,
      mask: clearMask ? null : (mask ?? this.mask),
      blendMode: blendMode ?? this.blendMode,
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
      if (speedCurve != null) 'speedCurve': speedCurve!.toJson(),
      'volume': volume,
      'isMuted': isMuted,
      'opacity': opacity,
      'rotationDegrees': rotationDegrees,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'isReversed': isReversed,
      'isFrozen': isFrozen,
      'xPos': xPos,
      'yPos': yPos,
      'scale': scale,
      'rotationAngle': rotationAngle,
      if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
      if (mask != null) 'mask': mask!.toJson(),
      'blendMode': blendMode.index,
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
      speedCurve: json['speedCurve'] != null
          ? SpeedCurve.fromJson(json['speedCurve'] as Map<String, dynamic>)
          : null,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      isMuted: json['isMuted'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      rotationDegrees: (json['rotationDegrees'] as num?)?.toInt() ?? 0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      isReversed: json['isReversed'] as bool? ?? false,
      isFrozen: json['isFrozen'] as bool? ?? false,
      previewGradient: const [Color(0xFF141E30), Color(0xFF243B55)],
      xPos: (json['xPos'] as num?)?.toDouble() ?? 0.0,
      yPos: (json['yPos'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotationAngle: (json['rotationAngle'] as num?)?.toDouble() ?? 0.0,
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((k) => VideoKeyframe.fromJson(k as Map<String, dynamic>))
              .toList() ??
          const [],
      mask: json['mask'] != null ? VideoMask.fromJson(json['mask'] as Map<String, dynamic>) : null,
      blendMode: json['blendMode'] != null
          ? BlendMode.values[(json['blendMode'] as num).toInt().clamp(0, BlendMode.values.length - 1)]
          : BlendMode.srcOver,
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
          speedCurve == other.speedCurve &&
          volume == other.volume &&
          isMuted == other.isMuted &&
          opacity == other.opacity &&
          rotationDegrees == other.rotationDegrees &&
          flipHorizontal == other.flipHorizontal &&
          flipVertical == other.flipVertical &&
          isReversed == other.isReversed &&
          isFrozen == other.isFrozen &&
          xPos == other.xPos &&
          yPos == other.yPos &&
          scale == other.scale &&
          rotationAngle == other.rotationAngle;

  @override
  int get hashCode =>
      id.hashCode ^
      assetId.hashCode ^
      title.hashCode ^
      trimStart.hashCode ^
      trimEnd.hashCode ^
      speed.hashCode ^
      speedCurve.hashCode ^
      volume.hashCode ^
      isMuted.hashCode ^
      opacity.hashCode ^
      rotationDegrees.hashCode ^
      flipHorizontal.hashCode ^
      flipVertical.hashCode ^
      isReversed.hashCode ^
      isFrozen.hashCode ^
      xPos.hashCode ^
      yPos.hashCode ^
      scale.hashCode ^
      rotationAngle.hashCode;
}

/// Canonical alias for VideoClip to satisfy MediaClip domain naming
typedef MediaClip = VideoClip;
