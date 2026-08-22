import 'package:flutter/material.dart';

/// Model representing a subtitle / text overlay on the timeline
class TextOverlay {
  final String id;
  final String text;
  final Duration startTime;
  final Duration duration;
  final Color textColor;
  final double fontSize;
  final Offset position;

  const TextOverlay({
    required this.id,
    required this.text,
    required this.startTime,
    required this.duration,
    Color? color,
    Color textColor = Colors.white,
    this.fontSize = 24.0,
    this.position = const Offset(0.5, 0.75),
  }) : textColor = color ?? textColor;

  Color get color => textColor;

  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;
  double get durationInSeconds => duration.inMilliseconds / 1000.0;

  TextOverlay copyWith({
    String? id,
    String? text,
    Duration? startTime,
    Duration? duration,
    Color? color,
    Color? textColor,
    double? fontSize,
    Offset? position,
  }) {
    return TextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      textColor: color ?? textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      position: position ?? this.position,
    );
  }
}
