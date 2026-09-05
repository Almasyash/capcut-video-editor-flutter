import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';

/// Top-level immutable Project model for draft management and persistent storage
class Project {
  final String id;
  final String name;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AspectRatioPreset aspectRatio;
  final List<VideoClip> videoClips;
  final List<OverlayClip> overlayClips;
  final List<StickerOverlay> stickerOverlays;
  final List<TextOverlay> textOverlays;
  final List<AudioTrack> audioTracks;
  final List<MediaAsset> mediaLibrary;
  final EditorFilter activeFilter;
  final ColorAdjustments colorAdjustments;
  final VideoEffect activeEffect;
  final Color canvasBackgroundColor;
  final List<Transition> transitions;
  final double canvasBlurSigma;
  final double playheadPosition;

  const Project({
    required this.id,
    required this.name,
    this.thumbnailPath,
    required this.createdAt,
    required this.updatedAt,
    this.aspectRatio = AspectRatioPreset.ratio9x16,
    this.videoClips = const [],
    this.overlayClips = const [],
    this.stickerOverlays = const [],
    this.textOverlays = const [],
    this.audioTracks = const [],
    this.mediaLibrary = const [],
    this.activeFilter = const EditorFilter(
      type: FilterType.none,
      name: 'Normal',
      icon: Icons.filter_none_rounded,
      previewColors: [Colors.grey, Colors.blueGrey],
      intensity: 0.0,
    ),
    this.colorAdjustments = const ColorAdjustments(),
    this.activeEffect = const VideoEffect(
      type: VideoEffectType.none,
      name: 'None',
      icon: Icons.block_rounded,
      color: Colors.grey,
    ),
    this.canvasBackgroundColor = Colors.black,
    this.transitions = const [],
    this.canvasBlurSigma = 0.0,
    this.playheadPosition = 0.0,
  });

  /// Convenient getter for primary/single audio track
  AudioTrack? get audioTrack => audioTracks.isNotEmpty ? audioTracks.first : null;

  /// Computed total duration in seconds across video clips, audio tracks, and text overlays
  double get durationInSeconds {
    double videoTotal = 0.0;
    for (final clip in videoClips) {
      videoTotal += clip.durationInSeconds;
    }
    double audioEnd = 0.0;
    for (final track in audioTracks) {
      final trackEnd = track.startTimeInSeconds + track.durationInSeconds;
      if (trackEnd > audioEnd) audioEnd = trackEnd;
    }
    double textEnd = 0.0;
    for (final text in textOverlays) {
      final tEnd = text.startTimeInSeconds + text.durationInSeconds;
      if (tEnd > textEnd) textEnd = tEnd;
    }
    return math.max(videoTotal, math.max(audioEnd, textEnd));
  }

  Project copyWith({
    String? id,
    String? name,
    String? thumbnailPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    AspectRatioPreset? aspectRatio,
    List<VideoClip>? videoClips,
    List<OverlayClip>? overlayClips,
    List<StickerOverlay>? stickerOverlays,
    List<TextOverlay>? textOverlays,
    List<AudioTrack>? audioTracks,
    AudioTrack? audioTrack,
    bool clearAudioTrack = false,
    List<MediaAsset>? mediaLibrary,
    EditorFilter? activeFilter,
    ColorAdjustments? colorAdjustments,
    VideoEffect? activeEffect,
    Color? canvasBackgroundColor,
    List<Transition>? transitions,
    double? canvasBlurSigma,
    double? playheadPosition,
  }) {
    final newAudioTracks = clearAudioTrack
        ? const <AudioTrack>[]
        : (audioTracks ?? (audioTrack != null ? [audioTrack] : this.audioTracks));
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      videoClips: videoClips ?? this.videoClips,
      overlayClips: overlayClips ?? this.overlayClips,
      stickerOverlays: stickerOverlays ?? this.stickerOverlays,
      textOverlays: textOverlays ?? this.textOverlays,
      audioTracks: newAudioTracks,
      mediaLibrary: mediaLibrary ?? this.mediaLibrary,
      activeFilter: activeFilter ?? this.activeFilter,
      colorAdjustments: colorAdjustments ?? this.colorAdjustments,
      activeEffect: activeEffect ?? this.activeEffect,
      canvasBackgroundColor: canvasBackgroundColor ?? this.canvasBackgroundColor,
      transitions: transitions ?? this.transitions,
      canvasBlurSigma: canvasBlurSigma ?? this.canvasBlurSigma,
      playheadPosition: playheadPosition ?? this.playheadPosition,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'aspectRatio': aspectRatio.name,
      'videoClips': videoClips.map((c) => c.toJson()).toList(),
      'overlayClips': overlayClips.map((o) => o.toJson()).toList(),
      'stickerOverlays': stickerOverlays.map((s) => s.toJson()).toList(),
      'textOverlays': textOverlays.map((t) => t.toJson()).toList(),
      'audioTracks': audioTracks.map((a) => a.toJson()).toList(),
      'audioTrack': audioTrack?.toJson(),
      'mediaLibrary': mediaLibrary.map((m) => m.toJson()).toList(),
      'activeFilter': activeFilter.toJson(),
      'colorAdjustments': colorAdjustments.toJson(),
      'activeEffect': activeEffect.name,
      'canvasBackgroundColor': canvasBackgroundColor.toARGB32(),
      'transitions': transitions.map((tr) => tr.toJson()).toList(),
      'canvasBlurSigma': canvasBlurSigma,
      'playheadPosition': playheadPosition,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    final aspectName = json['aspectRatio'] as String? ?? 'ratio9x16';
    final aspect = AspectRatioPreset.values.firstWhere(
      (a) => a.name == aspectName,
      orElse: () => AspectRatioPreset.ratio9x16,
    );

    // Resolve activeEffect
    final effectRaw = json['activeEffect'];
    final String effectName;
    if (effectRaw is String) {
      effectName = effectRaw;
    } else if (effectRaw is Map) {
      effectName = effectRaw['name'] as String? ?? effectRaw['type'] as String? ?? 'none';
    } else {
      effectName = 'none';
    }
    final effect = VideoEffect.presets.firstWhere(
      (e) => e.name.toLowerCase() == effectName.toLowerCase() || e.type.name.toLowerCase() == effectName.toLowerCase(),
      orElse: () => VideoEffect.presets.first,
    );

    final colorVal = json['canvasBackgroundColor'] as int?;

    // Audio tracks handling
    List<AudioTrack> parsedAudioTracks = [];
    if (json['audioTracks'] is List) {
      parsedAudioTracks = (json['audioTracks'] as List)
          .map((a) => AudioTrack.fromJson(a as Map<String, dynamic>))
          .toList();
    } else if (json['audioTrack'] is Map) {
      parsedAudioTracks = [AudioTrack.fromJson(json['audioTrack'] as Map<String, dynamic>)];
    }

    // Transitions handling
    List<Transition> parsedTransitions = [];
    if (json['transitions'] is List) {
      parsedTransitions = (json['transitions'] as List)
          .map((t) => Transition.fromJson(t as Map<String, dynamic>))
          .toList();
    }

    return Project(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Project',
      thumbnailPath: json['thumbnailPath'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      aspectRatio: aspect,
      videoClips: (json['videoClips'] as List?)?.map((c) => VideoClip.fromJson(c as Map<String, dynamic>)).toList() ?? const [],
      overlayClips: (json['overlayClips'] as List?)?.map((o) => OverlayClip.fromJson(o as Map<String, dynamic>)).toList() ?? const [],
      stickerOverlays: (json['stickerOverlays'] as List?)?.map((s) => StickerOverlay.fromJson(s as Map<String, dynamic>)).toList() ?? const [],
      textOverlays: (json['textOverlays'] as List?)?.map((t) => TextOverlay.fromJson(t as Map<String, dynamic>)).toList() ?? const [],
      audioTracks: parsedAudioTracks,
      mediaLibrary: (json['mediaLibrary'] as List?)?.map((m) => MediaAsset.fromJson(m as Map<String, dynamic>)).toList() ?? const [],
      activeFilter: json['activeFilter'] != null ? EditorFilter.fromJson(json['activeFilter'] as Map<String, dynamic>) : EditorFilter.presets.first,
      colorAdjustments: json['colorAdjustments'] != null ? ColorAdjustments.fromJson(json['colorAdjustments'] as Map<String, dynamic>) : const ColorAdjustments(),
      activeEffect: effect,
      canvasBackgroundColor: colorVal != null ? Color(colorVal) : Colors.black,
      transitions: parsedTransitions,
      canvasBlurSigma: (json['canvasBlurSigma'] as num?)?.toDouble() ?? 0.0,
      playheadPosition: (json['playheadPosition'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
