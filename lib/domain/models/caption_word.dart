import 'package:flutter/material.dart';

/// Represents a single word within an animated caption phrase with timestamp boundaries
class CaptionWord {
  final String word;
  final double startOffsetSec; // Time in seconds relative to parent TextOverlay start
  final double durationSec;
  final Color? customColor;

  const CaptionWord({
    required this.word,
    required this.startOffsetSec,
    required this.durationSec,
    this.customColor,
  });

  double get endOffsetSec => startOffsetSec + durationSec;

  CaptionWord copyWith({
    String? word,
    double? startOffsetSec,
    double? durationSec,
    Color? customColor,
  }) {
    return CaptionWord(
      word: word ?? this.word,
      startOffsetSec: startOffsetSec ?? this.startOffsetSec,
      durationSec: durationSec ?? this.durationSec,
      customColor: customColor ?? this.customColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'startOffsetSec': startOffsetSec,
      'durationSec': durationSec,
      'customColorValue': customColor?.value,
    };
  }

  factory CaptionWord.fromJson(Map<String, dynamic> json) {
    final colorVal = json['customColorValue'] as int?;
    return CaptionWord(
      word: json['word'] as String? ?? '',
      startOffsetSec: (json['startOffsetSec'] as num?)?.toDouble() ?? 0.0,
      durationSec: (json['durationSec'] as num?)?.toDouble() ?? 0.4,
      customColor: colorVal != null ? Color(colorVal) : null,
    );
  }
}
