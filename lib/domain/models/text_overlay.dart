import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/caption_word.dart';

/// Animation style for captions and subtitle overlays
enum TextAnimationType {
  none,
  fade,      // Smooth fade in & fade out transition
  zoom,      // Dynamic scale zoom-in entrance & zoom-out exit
  pop,       // Pop-in scale bounce entrance
  slideUp,   // Smooth vertical slide up entrance & exit
  slideDown, // Smooth vertical slide down entrance & exit
  fadeSlide, // Smooth vertical slide & fade
  typewriter,// Progressive character/word reveal
  karaoke,   // Word-by-word energetic active highlight & bounce
  glowPulse, // Radiant rhythmic aura
}

extension TextAnimationTypeExtension on TextAnimationType {
  String get displayName {
    switch (this) {
      case TextAnimationType.none:
        return 'None (Static)';
      case TextAnimationType.fade:
        return 'Fade In/Out';
      case TextAnimationType.zoom:
        return 'Zoom Scale';
      case TextAnimationType.pop:
        return 'Pop-in (Bounce)';
      case TextAnimationType.slideUp:
        return 'Slide Up';
      case TextAnimationType.slideDown:
        return 'Slide Down';
      case TextAnimationType.fadeSlide:
        return 'Fade Slide';
      case TextAnimationType.typewriter:
        return 'Typewriter';
      case TextAnimationType.karaoke:
        return 'Karaoke (Bounce)';
      case TextAnimationType.glowPulse:
        return 'Glow Pulse';
    }
  }

  IconData get icon {
    switch (this) {
      case TextAnimationType.none:
        return Icons.text_fields_rounded;
      case TextAnimationType.fade:
        return Icons.opacity_rounded;
      case TextAnimationType.zoom:
        return Icons.zoom_in_rounded;
      case TextAnimationType.pop:
        return Icons.open_in_full_rounded;
      case TextAnimationType.slideUp:
        return Icons.arrow_upward_rounded;
      case TextAnimationType.slideDown:
        return Icons.arrow_downward_rounded;
      case TextAnimationType.fadeSlide:
        return Icons.vertical_align_top_rounded;
      case TextAnimationType.typewriter:
        return Icons.keyboard_alt_outlined;
      case TextAnimationType.karaoke:
        return Icons.record_voice_over_rounded;
      case TextAnimationType.glowPulse:
        return Icons.wb_incandescent_outlined;
    }
  }
}

/// Model representing a subtitle / text overlay on the timeline with support for
/// word-by-word karaoke animations, outline strokes, and styling presets.
class TextOverlay {
  final String id;
  final String text;
  final Duration startTime;
  final Duration duration;
  final Duration trimStart;
  final Duration? trimEnd;
  final double speed;
  final Color textColor;
  final double fontSize;
  final Offset position;
  final String? fontFamily;
  final Color? backgroundColor;
  final TextAlign textAlign;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final Color? shadowColor;
  final TextAnimationType animationType;
  final Color? highlightColor;
  final double strokeWidth;
  final Color? strokeColor;
  final double scale;
  final List<CaptionWord> words;

  const TextOverlay({
    required this.id,
    required this.text,
    required this.startTime,
    required this.duration,
    this.trimStart = Duration.zero,
    this.trimEnd,
    this.speed = 1.0,
    Color? color,
    Color textColor = Colors.white,
    this.fontSize = 24.0,
    this.position = const Offset(0.5, 0.75),
    this.fontFamily,
    this.backgroundColor,
    this.textAlign = TextAlign.center,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.shadowColor,
    this.animationType = TextAnimationType.none,
    this.highlightColor,
    this.strokeWidth = 0.0,
    this.strokeColor,
    this.scale = 1.0,
    this.words = const [],
  }) : textColor = color ?? textColor;

  /// Minimum allowable text scale factor
  static const double minScale = 0.3;

  /// Maximum allowable text scale factor
  static const double maxScale = 4.0;

  /// Sanitizes text scale ensuring it is positive, finite, and clamped within safe bounds
  static double sanitizeScale(double rawScale, {double fallback = 1.0}) {
    if (rawScale.isNaN || !rawScale.isFinite || rawScale <= 0.0) {
      return fallback;
    }
    return rawScale.clamp(minScale, maxScale);
  }

  /// Sanitizes normalized text position coordinates ensuring finite numbers within [0.0, 1.0]
  static Offset sanitizePosition(Offset rawPos, {Offset fallback = const Offset(0.5, 0.75)}) {
    final dx = (rawPos.dx.isNaN || !rawPos.dx.isFinite) ? fallback.dx : rawPos.dx.clamp(0.0, 1.0);
    final dy = (rawPos.dy.isNaN || !rawPos.dy.isFinite) ? fallback.dy : rawPos.dy.clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

  Color get color => textColor;

  /// Effective trim end defaulting to duration if trimEnd is not specified
  Duration get effectiveTrimEnd => trimEnd ?? duration;

  /// Effective duration taking trimming and playback speed into account
  Duration get effectiveDuration {
    final rawMs = effectiveTrimEnd.inMilliseconds - trimStart.inMilliseconds;
    final safeSpeed = speed > 0 ? speed : 1.0;
    return Duration(milliseconds: (rawMs / safeSpeed).round());
  }

  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;
  double get durationInSeconds => effectiveDuration.inMilliseconds / 1000.0;
  double get trimStartInSeconds => trimStart.inMilliseconds / 1000.0;
  double get trimEndInSeconds => effectiveTrimEnd.inMilliseconds / 1000.0;
  double get endTimeInSeconds => startTimeInSeconds + durationInSeconds;

  /// Returns the zero-based index of the currently active spoken word at the specified
  /// time offset (in seconds) relative to the start of this caption.
  int getActiveWordIndex(double elapsedSeconds) {
    if (elapsedSeconds < 0) return 0;

    // 1. Check explicit word timestamps if populated
    if (words.isNotEmpty) {
      for (int i = 0; i < words.length; i++) {
        final w = words[i];
        if (elapsedSeconds >= w.startOffsetSec && elapsedSeconds < w.endOffsetSec) {
          return i;
        }
      }
      if (elapsedSeconds >= words.last.endOffsetSec) {
        return words.length - 1;
      }
      return 0;
    }

    // 2. Proportional fallback based on split words
    final wordTokens = text.trim().split(RegExp(r'\s+'));
    if (wordTokens.isEmpty) return 0;
    final totalSec = durationInSeconds;
    if (totalSec <= 0) return 0;

    final progress = (elapsedSeconds / totalSec).clamp(0.0, 0.999);
    final calculatedIdx = (progress * wordTokens.length).floor();
    return calculatedIdx.clamp(0, wordTokens.length - 1);
  }

  /// Returns either explicitly defined words or automatically generates proportional word tokens
  List<CaptionWord> get effectiveWords {
    if (words.isNotEmpty) return words;

    final tokens = text.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || (tokens.length == 1 && tokens.first.isEmpty)) {
      return const [];
    }

    final totalSec = durationInSeconds;
    final perWordDuration = totalSec / tokens.length;
    return List.generate(tokens.length, (i) {
      return CaptionWord(
        word: tokens[i],
        startOffsetSec: i * perWordDuration,
        durationSec: perWordDuration,
      );
    });
  }

  TextOverlay copyWith({
    String? id,
    String? text,
    Duration? startTime,
    Duration? duration,
    Duration? trimStart,
    Duration? trimEnd,
    double? speed,
    Color? color,
    Color? textColor,
    double? fontSize,
    Offset? position,
    String? fontFamily,
    Color? backgroundColor,
    TextAlign? textAlign,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    Color? shadowColor,
    TextAnimationType? animationType,
    Color? highlightColor,
    double? strokeWidth,
    Color? strokeColor,
    double? scale,
    List<CaptionWord>? words,
  }) {
    return TextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speed: speed ?? this.speed,
      textColor: color ?? textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      position: position ?? this.position,
      fontFamily: fontFamily ?? this.fontFamily,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textAlign: textAlign ?? this.textAlign,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      shadowColor: shadowColor ?? this.shadowColor,
      animationType: animationType ?? this.animationType,
      highlightColor: highlightColor ?? this.highlightColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeColor: strokeColor ?? this.strokeColor,
      scale: scale ?? this.scale,
      words: words ?? this.words,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'startTimeMs': startTime.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'trimEndMs': trimEnd?.inMilliseconds,
      'speed': speed,
      'colorValue': textColor.value,
      'fontSize': fontSize,
      'posX': position.dx,
      'posY': position.dy,
      'fontFamily': fontFamily,
      'backgroundColorValue': backgroundColor?.value,
      'textAlignIndex': textAlign.index,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'shadowColorValue': shadowColor?.value,
      'animationType': animationType.name,
      'highlightColorValue': highlightColor?.value,
      'strokeWidth': strokeWidth,
      'strokeColorValue': strokeColor?.value,
      'scale': scale,
      'words': words.map((w) => w.toJson()).toList(),
    };
  }

  factory TextOverlay.fromJson(Map<String, dynamic> json) {
    final colorVal = json['colorValue'] as int?;
    final bgVal = json['backgroundColorValue'] as int?;
    final shadowVal = json['shadowColorValue'] as int?;
    final alignIdx = json['textAlignIndex'] as int?;
    final hlVal = json['highlightColorValue'] as int?;
    final strokeVal = json['strokeColorValue'] as int?;

    return TextOverlay(
      id: json['id'] as String,
      text: json['text'] as String? ?? 'Subtitle',
      startTime: Duration(milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 4000),
      trimStart: Duration(milliseconds: (json['trimStartMs'] as num?)?.toInt() ?? 0),
      trimEnd: json['trimEndMs'] != null ? Duration(milliseconds: (json['trimEndMs'] as num).toInt()) : null,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      textColor: colorVal != null ? Color(colorVal) : Colors.white,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24.0,
      position: Offset(
        (json['posX'] as num?)?.toDouble() ?? 0.5,
        (json['posY'] as num?)?.toDouble() ?? 0.75,
      ),
      fontFamily: json['fontFamily'] as String?,
      backgroundColor: bgVal != null ? Color(bgVal) : null,
      textAlign: alignIdx != null && alignIdx >= 0 && alignIdx < TextAlign.values.length
          ? TextAlign.values[alignIdx]
          : TextAlign.center,
      isBold: json['isBold'] as bool? ?? false,
      isItalic: json['isItalic'] as bool? ?? false,
      isUnderline: json['isUnderline'] as bool? ?? false,
      shadowColor: shadowVal != null ? Color(shadowVal) : null,
      animationType: TextAnimationType.values.firstWhere(
        (e) => e.name == json['animationType'],
        orElse: () => TextAnimationType.none,
      ),
      highlightColor: hlVal != null ? Color(hlVal) : null,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.0,
      strokeColor: strokeVal != null ? Color(strokeVal) : null,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      words: (json['words'] as List?)
              ?.map((w) => CaptionWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
