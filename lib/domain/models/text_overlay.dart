import 'package:flutter/material.dart';

/// Model representing a subtitle / text overlay on the timeline
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
  }) : textColor = color ?? textColor;

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
      'colorValue': textColor.toARGB32(),
      'fontSize': fontSize,
      'posX': position.dx,
      'posY': position.dy,
      'fontFamily': fontFamily,
      'backgroundColorValue': backgroundColor?.toARGB32(),
      'textAlignIndex': textAlign.index,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'shadowColorValue': shadowColor?.toARGB32(),
    };
  }

  factory TextOverlay.fromJson(Map<String, dynamic> json) {
    final colorVal = json['colorValue'] as int?;
    final bgVal = json['backgroundColorValue'] as int?;
    final shadowVal = json['shadowColorValue'] as int?;
    final alignIdx = json['textAlignIndex'] as int?;

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
    );
  }
}
