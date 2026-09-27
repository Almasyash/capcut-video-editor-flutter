import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';

/// Animation configuration for PIP overlay entrance, overall loop, or exit
class PipAnimation {
  final String type; // e.g. 'fade', 'slideLeft', 'slideRight', 'slideUp', 'slideDown', 'zoomIn', 'spin', 'pulse', 'float', 'shake'
  final double durationSec;
  final String easing; // 'linear', 'easeIn', 'easeOut', 'easeInOut'
  final bool enabled;

  const PipAnimation({
    required this.type,
    this.durationSec = 0.5,
    this.easing = 'easeInOut',
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'durationSec': durationSec,
    'easing': easing,
    'enabled': enabled,
  };

  factory PipAnimation.fromJson(Map<String, dynamic> json) => PipAnimation(
    type: json['type'] as String? ?? 'fade',
    durationSec: (json['durationSec'] as num?)?.toDouble() ?? 0.5,
    easing: json['easing'] as String? ?? 'easeInOut',
    enabled: json['enabled'] as bool? ?? true,
  );

  PipAnimation copyWith({
    String? type,
    double? durationSec,
    String? easing,
    bool? enabled,
  }) => PipAnimation(
    type: type ?? this.type,
    durationSec: durationSec ?? this.durationSec,
    easing: easing ?? this.easing,
    enabled: enabled ?? this.enabled,
  );
}

/// Color adjustment settings for PIP overlay (normalized ranges)
class PipAdjustments {
  final double brightness; // -1.0 to 1.0 (default 0.0)
  final double contrast;   // -1.0 to 1.0 (default 0.0)
  final double saturation; // -1.0 to 1.0 (default 0.0)
  final double exposure;   // -1.0 to 1.0 (default 0.0)
  final double temperature;// -1.0 to 1.0 (warm > 0, cool < 0)
  final double tint;       // -1.0 to 1.0 (default 0.0)
  final double vignette;   // 0.0 to 1.0 (default 0.0)
  final double sharpness;  // 0.0 to 1.0 (default 0.0)

  const PipAdjustments({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.exposure = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.vignette = 0.0,
    this.sharpness = 0.0,
  });

  bool get isDefault =>
      brightness == 0.0 &&
      contrast == 0.0 &&
      saturation == 0.0 &&
      exposure == 0.0 &&
      temperature == 0.0 &&
      tint == 0.0 &&
      vignette == 0.0 &&
      sharpness == 0.0;

  Map<String, dynamic> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'exposure': exposure,
    'temperature': temperature,
    'tint': tint,
    'vignette': vignette,
    'sharpness': sharpness,
  };

  factory PipAdjustments.fromJson(Map<String, dynamic> json) => PipAdjustments(
    brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
    contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
    exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
    tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
    vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
    sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
  );

  PipAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? temperature,
    double? tint,
    double? vignette,
    double? sharpness,
  }) => PipAdjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    exposure: exposure ?? this.exposure,
    temperature: temperature ?? this.temperature,
    tint: tint ?? this.tint,
    vignette: vignette ?? this.vignette,
    sharpness: sharpness ?? this.sharpness,
  );
}

/// Outline effect configuration for PIP overlay
class PipOutline {
  final bool enabled;
  final Color color;
  final double width;
  final double opacity;

  const PipOutline({
    this.enabled = false,
    this.color = const Color(0xFF00C6FF),
    this.width = 2.0,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'color': color.value,
    'width': width,
    'opacity': opacity,
  };

  factory PipOutline.fromJson(Map<String, dynamic> json) => PipOutline(
    enabled: json['enabled'] as bool? ?? false,
    color: json['color'] != null ? Color((json['color'] as num).toInt()) : const Color(0xFF00C6FF),
    width: (json['width'] as num?)?.toDouble() ?? 2.0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
  );

  PipOutline copyWith({
    bool? enabled,
    Color? color,
    double? width,
    double? opacity,
  }) => PipOutline(
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
    width: width ?? this.width,
    opacity: opacity ?? this.opacity,
  );
}

/// Shadow effect configuration for PIP overlay
class PipShadow {
  final bool enabled;
  final Color color;
  final double blur;
  final double dx;
  final double dy;
  final double opacity;

  const PipShadow({
    this.enabled = false,
    this.color = Colors.black,
    this.blur = 8.0,
    this.dx = 2.0,
    this.dy = 4.0,
    this.opacity = 0.6,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'color': color.value,
    'blur': blur,
    'dx': dx,
    'dy': dy,
    'opacity': opacity,
  };

  factory PipShadow.fromJson(Map<String, dynamic> json) => PipShadow(
    enabled: json['enabled'] as bool? ?? false,
    color: json['color'] != null ? Color((json['color'] as num).toInt()) : Colors.black,
    blur: (json['blur'] as num?)?.toDouble() ?? 8.0,
    dx: (json['dx'] as num?)?.toDouble() ?? 2.0,
    dy: (json['dy'] as num?)?.toDouble() ?? 4.0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 0.6,
  );

  PipShadow copyWith({
    bool? enabled,
    Color? color,
    double? blur,
    double? dx,
    double? dy,
    double? opacity,
  }) => PipShadow(
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
    blur: blur ?? this.blur,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    opacity: opacity ?? this.opacity,
  );
}

/// Glow effect configuration for PIP overlay
class PipGlow {
  final bool enabled;
  final Color color;
  final double radius;
  final double intensity;

  const PipGlow({
    this.enabled = false,
    this.color = const Color(0xFF00FFFF),
    this.radius = 12.0,
    this.intensity = 0.7,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'color': color.value,
    'radius': radius,
    'intensity': intensity,
  };

  factory PipGlow.fromJson(Map<String, dynamic> json) => PipGlow(
    enabled: json['enabled'] as bool? ?? false,
    color: json['color'] != null ? Color((json['color'] as num).toInt()) : const Color(0xFF00FFFF),
    radius: (json['radius'] as num?)?.toDouble() ?? 12.0,
    intensity: (json['intensity'] as num?)?.toDouble() ?? 0.7,
  );

  PipGlow copyWith({
    bool? enabled,
    Color? color,
    double? radius,
    double? intensity,
  }) => PipGlow(
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
    radius: radius ?? this.radius,
    intensity: intensity ?? this.intensity,
  );
}

/// Audio effects and DSP settings for PIP video
class PipAudioEffects {
  final double eqLow;   // -12.0 to 12.0 dB
  final double eqMid;   // -12.0 to 12.0 dB
  final double eqHigh;  // -12.0 to 12.0 dB
  final double reverbAmount; // 0.0 to 1.0
  final bool noiseReductionEnabled;
  final double noiseReductionStrength; // 0.0 to 1.0
  final String aiVoiceEffect; // 'none', 'deep', 'chipmunk', 'robot', 'echo'

  const PipAudioEffects({
    this.eqLow = 0.0,
    this.eqMid = 0.0,
    this.eqHigh = 0.0,
    this.reverbAmount = 0.0,
    this.noiseReductionEnabled = false,
    this.noiseReductionStrength = 0.5,
    this.aiVoiceEffect = 'none',
  });

  Map<String, dynamic> toJson() => {
    'eqLow': eqLow,
    'eqMid': eqMid,
    'eqHigh': eqHigh,
    'reverbAmount': reverbAmount,
    'noiseReductionEnabled': noiseReductionEnabled,
    'noiseReductionStrength': noiseReductionStrength,
    'aiVoiceEffect': aiVoiceEffect,
  };

  factory PipAudioEffects.fromJson(Map<String, dynamic> json) => PipAudioEffects(
    eqLow: (json['eqLow'] as num?)?.toDouble() ?? 0.0,
    eqMid: (json['eqMid'] as num?)?.toDouble() ?? 0.0,
    eqHigh: (json['eqHigh'] as num?)?.toDouble() ?? 0.0,
    reverbAmount: (json['reverbAmount'] as num?)?.toDouble() ?? 0.0,
    noiseReductionEnabled: json['noiseReductionEnabled'] as bool? ?? false,
    noiseReductionStrength: (json['noiseReductionStrength'] as num?)?.toDouble() ?? 0.5,
    aiVoiceEffect: json['aiVoiceEffect'] as String? ?? 'none',
  );

  PipAudioEffects copyWith({
    double? eqLow,
    double? eqMid,
    double? eqHigh,
    double? reverbAmount,
    bool? noiseReductionEnabled,
    double? noiseReductionStrength,
    String? aiVoiceEffect,
  }) => PipAudioEffects(
    eqLow: eqLow ?? this.eqLow,
    eqMid: eqMid ?? this.eqMid,
    eqHigh: eqHigh ?? this.eqHigh,
    reverbAmount: reverbAmount ?? this.reverbAmount,
    noiseReductionEnabled: noiseReductionEnabled ?? this.noiseReductionEnabled,
    noiseReductionStrength: noiseReductionStrength ?? this.noiseReductionStrength,
    aiVoiceEffect: aiVoiceEffect ?? this.aiVoiceEffect,
  );
}

/// Represents a secondary Picture-in-Picture (PIP) overlay clip layer on top of main video
class OverlayClip {
  final String id;
  final String title;
  final Duration startTime;
  final Duration duration;
  final Offset position; // Relative (0.0 to 1.0) on canvas
  final double scale; // 0.05 to 5.0
  final double opacity; // 0.0 to 1.0
  final double rotation; // In radians
  final bool flipHorizontal;
  final bool flipVertical;
  final List<Color> previewGradient;
  final IconData previewIcon;
  final List<VideoKeyframe> keyframes;
  final VideoMask? mask;
  final BlendMode blendMode;

  // Real Media Asset linkage
  final String? assetId;
  final String? localPath;
  final String? thumbnailPath;
  final bool isPhoto;

  // Speed Control (0.25x to 4.0x)
  final double speed;

  // Audio Mixer (0% to 200% volume, mute, fades)
  final double volume;
  final bool isMuted;
  final double fadeInDurationSec;
  final double fadeOutDurationSec;

  // Animations (In, Overall, Out)
  final PipAnimation? inAnimation;
  final PipAnimation? overallAnimation;
  final PipAnimation? outAnimation;

  // Non-destructive Crop
  final Rect? cropRect; // Normalized (0.0, 0.0, 1.0, 1.0)
  final String? cropAspectRatio; // 'free', '1:1', '16:9', '9:16', '4:3'

  // Corner Pin (4 independent control points, relative coordinates)
  final Offset? cornerTopLeft;
  final Offset? cornerTopRight;
  final Offset? cornerBottomLeft;
  final Offset? cornerBottomRight;

  // Filters & Adjustments
  final String? filterId; // 'none', 'grayscale', 'sepia', 'vintage', 'cool', 'warm', 'vivid', 'cinema', 'noir'
  final double filterIntensity; // 0.0 to 1.0
  final PipAdjustments adjustments;

  // Visual Effects (Outline, Shadow, Glow)
  final PipOutline? outline;
  final PipShadow? shadow;
  final PipGlow? glow;
  final String? effectId; // 'blur', 'pixelate', 'rgbSplit', 'glitch', 'noise'
  final double effectIntensity;

  // Chroma Key (Green / Blue Screen Removal)
  final bool enableChromaKey;
  final Color chromaKeyColor; // Target color to key out (Default: pure green 0xFF00FF00)
  final double chromaSimilarity; // 0.0 to 1.0 (Default: 0.40)
  final double chromaSmoothness; // 0.0 to 1.0 (Default: 0.10)
  final double chromaSpill; // 0.0 to 1.0 (Default: 0.15)

  // Audio DSP & Effects
  final PipAudioEffects audioEffects;

  // Split Screen Preset
  final String? splitScreenPreset;

  const OverlayClip({
    required this.id,
    required this.title,
    required this.startTime,
    required this.duration,
    this.position = const Offset(0.5, 0.5),
    this.scale = 0.45,
    this.opacity = 1.0,
    this.rotation = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.previewGradient = const [Color(0xFF8A2387), Color(0xFFE94057)],
    this.previewIcon = Icons.layers_rounded,
    this.keyframes = const [],
    this.mask,
    this.blendMode = BlendMode.srcOver,
    this.assetId,
    this.localPath,
    this.thumbnailPath,
    this.isPhoto = false,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.fadeInDurationSec = 0.0,
    this.fadeOutDurationSec = 0.0,
    this.inAnimation,
    this.overallAnimation,
    this.outAnimation,
    this.cropRect,
    this.cropAspectRatio,
    this.cornerTopLeft,
    this.cornerTopRight,
    this.cornerBottomLeft,
    this.cornerBottomRight,
    this.filterId,
    this.filterIntensity = 1.0,
    this.adjustments = const PipAdjustments(),
    this.outline,
    this.shadow,
    this.glow,
    this.effectId,
    this.effectIntensity = 0.5,
    this.enableChromaKey = false,
    this.chromaKeyColor = const Color(0xFF00FF00),
    this.chromaSimilarity = 0.40,
    this.chromaSmoothness = 0.10,
    this.chromaSpill = 0.15,
    this.audioEffects = const PipAudioEffects(),
    this.splitScreenPreset,
  });

  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;
  double get durationInSeconds => duration.inMilliseconds / 1000.0;
  double get endTimeInSeconds => (startTime.inMilliseconds + duration.inMilliseconds) / 1000.0;
  Duration get endTime => startTime + duration;
  int get startTimeMs => startTime.inMilliseconds;
  int get durationMs => duration.inMilliseconds;
  int get endTimeMs => startTime.inMilliseconds + duration.inMilliseconds;

  bool get hasCornerPin =>
      cornerTopLeft != null ||
      cornerTopRight != null ||
      cornerBottomLeft != null ||
      cornerBottomRight != null;

  bool get hasCrop =>
      cropRect != null &&
      (cropRect!.left > 0.001 ||
          cropRect!.top > 0.001 ||
          cropRect!.right < 0.999 ||
          cropRect!.bottom < 0.999);

  static Offset sanitizePosition(Offset pos, {Offset fallback = const Offset(0.5, 0.5)}) {
    if (pos.dx.isNaN || pos.dx.isInfinite || pos.dy.isNaN || pos.dy.isInfinite) {
      return fallback;
    }
    return Offset(
      pos.dx.clamp(-0.5, 1.5),
      pos.dy.clamp(-0.5, 1.5),
    );
  }

  static double sanitizeScale(double s, {double fallback = 0.45}) {
    if (s.isNaN || s.isInfinite || s <= 0.0) return fallback;
    return s.clamp(0.05, 5.0);
  }

  static double sanitizeOpacity(double o, {double fallback = 1.0}) {
    if (o.isNaN || o.isInfinite) return fallback;
    return o.clamp(0.0, 1.0);
  }

  static double sanitizeRotation(double r, {double fallback = 0.0}) {
    if (r.isNaN || r.isInfinite) return fallback;
    return r;
  }

  static double sanitizeSpeed(double s, {double fallback = 1.0}) {
    if (s.isNaN || s.isInfinite || s <= 0.0) return fallback;
    return s.clamp(0.25, 4.0);
  }

  static double sanitizeVolume(double v, {double fallback = 1.0}) {
    if (v.isNaN || v.isInfinite || v < 0.0) return fallback;
    return v.clamp(0.0, 2.0);
  }

  OverlayClip copyWith({
    String? id,
    String? title,
    Duration? startTime,
    Duration? duration,
    Offset? position,
    double? scale,
    double? opacity,
    double? rotation,
    bool? flipHorizontal,
    bool? flipVertical,
    List<Color>? previewGradient,
    IconData? previewIcon,
    List<VideoKeyframe>? keyframes,
    VideoMask? mask,
    bool clearMask = false,
    BlendMode? blendMode,
    String? assetId,
    String? localPath,
    String? thumbnailPath,
    bool? isPhoto,
    double? speed,
    double? volume,
    bool? isMuted,
    double? fadeInDurationSec,
    double? fadeOutDurationSec,
    PipAnimation? inAnimation,
    bool clearInAnimation = false,
    PipAnimation? overallAnimation,
    bool clearOverallAnimation = false,
    PipAnimation? outAnimation,
    bool clearOutAnimation = false,
    Rect? cropRect,
    bool clearCropRect = false,
    String? cropAspectRatio,
    Offset? cornerTopLeft,
    Offset? cornerTopRight,
    Offset? cornerBottomLeft,
    Offset? cornerBottomRight,
    bool clearCornerPin = false,
    String? filterId,
    double? filterIntensity,
    PipAdjustments? adjustments,
    PipOutline? outline,
    PipShadow? shadow,
    PipGlow? glow,
    String? effectId,
    double? effectIntensity,
    bool? enableChromaKey,
    Color? chromaKeyColor,
    double? chromaSimilarity,
    double? chromaSmoothness,
    double? chromaSpill,
    PipAudioEffects? audioEffects,
    String? splitScreenPreset,
  }) {
    return OverlayClip(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      previewGradient: previewGradient ?? this.previewGradient,
      previewIcon: previewIcon ?? this.previewIcon,
      keyframes: keyframes ?? this.keyframes,
      mask: clearMask ? null : (mask ?? this.mask),
      blendMode: blendMode ?? this.blendMode,
      assetId: assetId ?? this.assetId,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isPhoto: isPhoto ?? this.isPhoto,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      fadeInDurationSec: fadeInDurationSec ?? this.fadeInDurationSec,
      fadeOutDurationSec: fadeOutDurationSec ?? this.fadeOutDurationSec,
      inAnimation: clearInAnimation ? null : (inAnimation ?? this.inAnimation),
      overallAnimation: clearOverallAnimation ? null : (overallAnimation ?? this.overallAnimation),
      outAnimation: clearOutAnimation ? null : (outAnimation ?? this.outAnimation),
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
      cropAspectRatio: cropAspectRatio ?? this.cropAspectRatio,
      cornerTopLeft: clearCornerPin ? null : (cornerTopLeft ?? this.cornerTopLeft),
      cornerTopRight: clearCornerPin ? null : (cornerTopRight ?? this.cornerTopRight),
      cornerBottomLeft: clearCornerPin ? null : (cornerBottomLeft ?? this.cornerBottomLeft),
      cornerBottomRight: clearCornerPin ? null : (cornerBottomRight ?? this.cornerBottomRight),
      filterId: filterId ?? this.filterId,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      adjustments: adjustments ?? this.adjustments,
      outline: outline ?? this.outline,
      shadow: shadow ?? this.shadow,
      glow: glow ?? this.glow,
      effectId: effectId ?? this.effectId,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      enableChromaKey: enableChromaKey ?? this.enableChromaKey,
      chromaKeyColor: chromaKeyColor ?? this.chromaKeyColor,
      chromaSimilarity: chromaSimilarity ?? this.chromaSimilarity,
      chromaSmoothness: chromaSmoothness ?? this.chromaSmoothness,
      chromaSpill: chromaSpill ?? this.chromaSpill,
      audioEffects: audioEffects ?? this.audioEffects,
      splitScreenPreset: splitScreenPreset ?? this.splitScreenPreset,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startTimeMs': startTime.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'posX': position.dx,
      'posY': position.dy,
      'scale': scale,
      'opacity': opacity,
      'rotation': rotation,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
      if (mask != null) 'mask': mask!.toJson(),
      'blendMode': blendMode.index,
      if (assetId != null) 'assetId': assetId,
      if (localPath != null) 'localPath': localPath,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      'isPhoto': isPhoto,
      'speed': speed,
      'volume': volume,
      'isMuted': isMuted,
      'fadeInDurationSec': fadeInDurationSec,
      'fadeOutDurationSec': fadeOutDurationSec,
      if (inAnimation != null) 'inAnimation': inAnimation!.toJson(),
      if (overallAnimation != null) 'overallAnimation': overallAnimation!.toJson(),
      if (outAnimation != null) 'outAnimation': outAnimation!.toJson(),
      if (cropRect != null)
        'cropRect': [cropRect!.left, cropRect!.top, cropRect!.width, cropRect!.height],
      if (cropAspectRatio != null) 'cropAspectRatio': cropAspectRatio,
      if (cornerTopLeft != null) 'cornerTL': [cornerTopLeft!.dx, cornerTopLeft!.dy],
      if (cornerTopRight != null) 'cornerTR': [cornerTopRight!.dx, cornerTopRight!.dy],
      if (cornerBottomLeft != null) 'cornerBL': [cornerBottomLeft!.dx, cornerBottomLeft!.dy],
      if (cornerBottomRight != null) 'cornerBR': [cornerBottomRight!.dx, cornerBottomRight!.dy],
      if (filterId != null) 'filterId': filterId,
      'filterIntensity': filterIntensity,
      if (!adjustments.isDefault) 'adjustments': adjustments.toJson(),
      if (outline != null) 'outline': outline!.toJson(),
      if (shadow != null) 'shadow': shadow!.toJson(),
      if (glow != null) 'glow': glow!.toJson(),
      if (effectId != null) 'effectId': effectId,
      'effectIntensity': effectIntensity,
      'enableChromaKey': enableChromaKey,
      'chromaKeyColor': chromaKeyColor.value,
      'chromaSimilarity': chromaSimilarity,
      'chromaSmoothness': chromaSmoothness,
      'chromaSpill': chromaSpill,
      'audioEffects': audioEffects.toJson(),
      if (splitScreenPreset != null) 'splitScreenPreset': splitScreenPreset,
    };
  }

  factory OverlayClip.fromJson(Map<String, dynamic> json) {
    Rect? parseCrop(dynamic val) {
      if (val is List && val.length == 4) {
        return Rect.fromLTWH(
          (val[0] as num).toDouble(),
          (val[1] as num).toDouble(),
          (val[2] as num).toDouble(),
          (val[3] as num).toDouble(),
        );
      }
      return null;
    }

    Offset? parseOffset(dynamic val) {
      if (val is List && val.length == 2) {
        return Offset((val[0] as num).toDouble(), (val[1] as num).toDouble());
      }
      return null;
    }

    return OverlayClip(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Overlay',
      startTime: Duration(milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 3000),
      position: Offset(
        (json['posX'] as num?)?.toDouble() ?? 0.5,
        (json['posY'] as num?)?.toDouble() ?? 0.5,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 0.45,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((k) => VideoKeyframe.fromJson(k as Map<String, dynamic>))
              .toList() ??
          const [],
      mask: json['mask'] != null ? VideoMask.fromJson(json['mask'] as Map<String, dynamic>) : null,
      blendMode: json['blendMode'] != null
          ? BlendMode.values[(json['blendMode'] as num).toInt().clamp(0, BlendMode.values.length - 1)]
          : BlendMode.srcOver,
      assetId: json['assetId'] as String?,
      localPath: json['localPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      isPhoto: json['isPhoto'] as bool? ?? false,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      isMuted: json['isMuted'] as bool? ?? false,
      fadeInDurationSec: (json['fadeInDurationSec'] as num?)?.toDouble() ?? 0.0,
      fadeOutDurationSec: (json['fadeOutDurationSec'] as num?)?.toDouble() ?? 0.0,
      inAnimation: json['inAnimation'] != null
          ? PipAnimation.fromJson(json['inAnimation'] as Map<String, dynamic>)
          : null,
      overallAnimation: json['overallAnimation'] != null
          ? PipAnimation.fromJson(json['overallAnimation'] as Map<String, dynamic>)
          : null,
      outAnimation: json['outAnimation'] != null
          ? PipAnimation.fromJson(json['outAnimation'] as Map<String, dynamic>)
          : null,
      cropRect: parseCrop(json['cropRect']),
      cropAspectRatio: json['cropAspectRatio'] as String?,
      cornerTopLeft: parseOffset(json['cornerTL']),
      cornerTopRight: parseOffset(json['cornerTR']),
      cornerBottomLeft: parseOffset(json['cornerBL']),
      cornerBottomRight: parseOffset(json['cornerBR']),
      filterId: json['filterId'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
      adjustments: json['adjustments'] != null
          ? PipAdjustments.fromJson(json['adjustments'] as Map<String, dynamic>)
          : const PipAdjustments(),
      outline: json['outline'] != null
          ? PipOutline.fromJson(json['outline'] as Map<String, dynamic>)
          : null,
      shadow: json['shadow'] != null
          ? PipShadow.fromJson(json['shadow'] as Map<String, dynamic>)
          : null,
      glow: json['glow'] != null
          ? PipGlow.fromJson(json['glow'] as Map<String, dynamic>)
          : null,
      effectId: json['effectId'] as String?,
      effectIntensity: (json['effectIntensity'] as num?)?.toDouble() ?? 0.5,
      enableChromaKey: json['enableChromaKey'] as bool? ?? false,
      chromaKeyColor: json['chromaKeyColor'] != null
          ? Color((json['chromaKeyColor'] as num).toInt())
          : const Color(0xFF00FF00),
      chromaSimilarity: (json['chromaSimilarity'] as num?)?.toDouble() ?? 0.40,
      chromaSmoothness: (json['chromaSmoothness'] as num?)?.toDouble() ?? 0.10,
      chromaSpill: (json['chromaSpill'] as num?)?.toDouble() ?? 0.15,
      audioEffects: json['audioEffects'] != null
          ? PipAudioEffects.fromJson(json['audioEffects'] as Map<String, dynamic>)
          : const PipAudioEffects(),
      splitScreenPreset: json['splitScreenPreset'] as String?,
    );
  }
}
