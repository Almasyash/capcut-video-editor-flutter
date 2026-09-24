import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/caption_word.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';

/// Available viral caption style presets
enum CaptionStylePresetId {
  hormozi,
  cyberNeon,
  minimalist,
  hypeFire,
  goldenVip,
}

/// Configuration defining the typography, stroke, highlights, and positioning of a caption preset
class CaptionStylePreset {
  final CaptionStylePresetId id;
  final String name;
  final String tag;
  final String description;
  final Color textColor;
  final Color highlightColor;
  final Color? backgroundColor;
  final double strokeWidth;
  final Color strokeColor;
  final double fontSize;
  final bool isBold;
  final TextAnimationType defaultAnimation;
  final Offset defaultPosition;
  final bool uppercase;

  const CaptionStylePreset({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.textColor,
    required this.highlightColor,
    this.backgroundColor,
    this.strokeWidth = 0.0,
    this.strokeColor = Colors.black,
    this.fontSize = 24.0,
    this.isBold = true,
    this.defaultAnimation = TextAnimationType.karaoke,
    this.defaultPosition = const Offset(0.5, 0.72),
    this.uppercase = true,
  });

  static const List<CaptionStylePreset> presets = [
    CaptionStylePreset(
      id: CaptionStylePresetId.hormozi,
      name: 'Hormozi Punch',
      tag: '🔥 VIRAL REELS',
      description: 'Bold uppercase text with punchy electric yellow highlight and thick black stroke.',
      textColor: Colors.white,
      highlightColor: Color(0xFFFFEB3B),
      backgroundColor: null,
      strokeWidth: 3.0,
      strokeColor: Colors.black,
      fontSize: 26.0,
      isBold: true,
      defaultAnimation: TextAnimationType.karaoke,
      defaultPosition: Offset(0.5, 0.72),
      uppercase: true,
    ),
    CaptionStylePreset(
      id: CaptionStylePresetId.cyberNeon,
      name: 'Cyber Neon',
      tag: '⚡ GLOW FX',
      description: 'Futuristic cyan and magenta aesthetic with dark translucent backdrop tag.',
      textColor: Color(0xFFE040FB),
      highlightColor: Color(0xFF00E5FF),
      backgroundColor: Color(0xCC0E0E18),
      strokeWidth: 1.5,
      strokeColor: Color(0xFF00E5FF),
      fontSize: 23.0,
      isBold: true,
      defaultAnimation: TextAnimationType.karaoke,
      defaultPosition: Offset(0.5, 0.72),
      uppercase: true,
    ),
    CaptionStylePreset(
      id: CaptionStylePresetId.minimalist,
      name: 'Minimalist Pill',
      tag: '✨ CLEAN',
      description: 'Sleek modern white typography nestled on an elegant frosted charcoal pill.',
      textColor: Colors.white,
      highlightColor: Color(0xFF81D4FA),
      backgroundColor: Color(0xAA181820),
      strokeWidth: 0.0,
      strokeColor: Colors.transparent,
      fontSize: 21.0,
      isBold: false,
      defaultAnimation: TextAnimationType.fadeSlide,
      defaultPosition: Offset(0.5, 0.76),
      uppercase: false,
    ),
    CaptionStylePreset(
      id: CaptionStylePresetId.hypeFire,
      name: 'Hype Fire',
      tag: '💥 ENERGETIC',
      description: 'High energy flame red and amber pop entrance for fitness and sports montages.',
      textColor: Color(0xFFFF5252),
      highlightColor: Color(0xFFFFD600),
      backgroundColor: Color(0xB31F0404),
      strokeWidth: 2.5,
      strokeColor: Colors.black,
      fontSize: 25.0,
      isBold: true,
      defaultAnimation: TextAnimationType.pop,
      defaultPosition: Offset(0.5, 0.70),
      uppercase: true,
    ),
    CaptionStylePreset(
      id: CaptionStylePresetId.goldenVip,
      name: 'Golden VIP',
      tag: '👑 LUXURY',
      description: 'Premium gold styling with glowing white active word transitions.',
      textColor: Color(0xFFFFD54F),
      highlightColor: Colors.white,
      backgroundColor: Color(0xDD0D0D14),
      strokeWidth: 2.0,
      strokeColor: Color(0xFFFFA000),
      fontSize: 24.0,
      isBold: true,
      defaultAnimation: TextAnimationType.glowPulse,
      defaultPosition: Offset(0.5, 0.72),
      uppercase: true,
    ),
  ];

  static CaptionStylePreset get defaultPreset => presets.first;

  static CaptionStylePreset findById(CaptionStylePresetId id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => defaultPreset);
  }
}

/// Service that generates speech-cadence aligned subtitles and auto captions
class AutoCaptionService {
  AutoCaptionService._();
  static final AutoCaptionService instance = AutoCaptionService._();

  static const Map<String, String> trendingScripts = {
    'Motivation': 'STOP WAITING FOR PERFECTION • START CREATING TODAY • CONSISTENCY IS THE KEY • YOU HAVE WHAT IT TAKES • NOW GO CRUSH IT',
    'Tech / Viral': 'THIS ONE FLUTTER FEATURE • WILL 10X YOUR VIDEO EDITING • FAST RENDER ENGINE • BUILT WITH LOVE • TRY IT OUT NOW',
    'Vlog / Travel': 'EXPLORING UNKNOWN PATHS • LIVING IN THE MOMENT • CHASING BEAUTIFUL SUNSETS • MEMORIES THAT LAST FOREVER • WHAT A JOURNEY',
    'Short / Punchy': 'WATCH THIS CLOSELY • DO NOT BLINK • THIS CHANGES EVERYTHING • SEE YOU NEXT TIME',
  };

  /// Generates a list of [TextOverlay] subtitle clips from a text script or transcript.
  ///
  /// - Breaks the script into phrases of [wordsPerChunk] words (typically 2-4).
  /// - Calculates realistic speech pause timings across [totalDurationInSeconds].
  /// - If [beatTimestamps] are provided, aligns chunk start times with musical / rhythmic drops!
  List<TextOverlay> generateFromScript({
    required String script,
    required double totalDurationInSeconds,
    double startTimelineOffsetSec = 0.0,
    int wordsPerChunk = 3,
    CaptionStylePreset? preset,
    TextAnimationType? animationOverride,
    List<double>? beatTimestamps,
  }) {
    final effectivePreset = preset ?? CaptionStylePreset.defaultPreset;
    final anim = animationOverride ?? effectivePreset.defaultAnimation;

    // Clean and tokenize script
    final rawTokens = script
        .replaceAll(RegExp(r'[•|]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty)
        .toList();

    if (rawTokens.isEmpty) return [];

    // Group into chunks
    final safeWordsPerChunk = wordsPerChunk.clamp(1, 6);
    final chunks = <List<String>>[];
    for (int i = 0; i < rawTokens.length; i += safeWordsPerChunk) {
      final end = math.min(i + safeWordsPerChunk, rawTokens.length);
      chunks.add(rawTokens.sublist(i, end));
    }

    if (chunks.isEmpty) return [];

    // Determine duration per chunk
    final availableDuration = math.max(1.0, totalDurationInSeconds);
    final baseChunkDuration = math.max(0.8, availableDuration / chunks.length);

    final result = <TextOverlay>[];
    double currentStart = startTimelineOffsetSec;

    for (int i = 0; i < chunks.length; i++) {
      final chunkWords = chunks[i];
      final formattedText = effectivePreset.uppercase
          ? chunkWords.join(' ').toUpperCase()
          : chunkWords.join(' ');

      // Snap start to closest beat if within 0.35s
      if (beatTimestamps != null && beatTimestamps.isNotEmpty) {
        for (final beat in beatTimestamps) {
          if ((beat - currentStart).abs() < 0.35 && beat >= currentStart - 0.2) {
            currentStart = beat;
            break;
          }
        }
      }

      // Word-level relative timings
      final chunkDuration = math.min(baseChunkDuration, availableDuration - (currentStart - startTimelineOffsetSec));
      final safeChunkDuration = math.max(0.6, chunkDuration);

      final wordTokens = <CaptionWord>[];
      final perWordDuration = safeChunkDuration / chunkWords.length;
      for (int w = 0; w < chunkWords.length; w++) {
        wordTokens.add(
          CaptionWord(
            word: effectivePreset.uppercase ? chunkWords[w].toUpperCase() : chunkWords[w],
            startOffsetSec: w * perWordDuration,
            durationSec: perWordDuration,
          ),
        );
      }

      final overlay = TextOverlay(
        id: 'caption_${DateTime.now().millisecondsSinceEpoch}_$i',
        text: formattedText,
        startTime: Duration(milliseconds: (currentStart * 1000).round()),
        duration: Duration(milliseconds: (safeChunkDuration * 1000).round()),
        textColor: effectivePreset.textColor,
        highlightColor: effectivePreset.highlightColor,
        backgroundColor: effectivePreset.backgroundColor,
        strokeWidth: effectivePreset.strokeWidth,
        strokeColor: effectivePreset.strokeColor,
        fontSize: effectivePreset.fontSize,
        isBold: effectivePreset.isBold,
        position: effectivePreset.defaultPosition,
        animationType: anim,
        words: wordTokens,
      );

      result.add(overlay);
      currentStart += safeChunkDuration + 0.15; // Natural 150ms speech cadence pause

      if (currentStart >= startTimelineOffsetSec + availableDuration) {
        break;
      }
    }

    return result;
  }

  /// Generates captions from a trending script genre
  List<TextOverlay> generateTrending({
    required String genre,
    required double totalDurationInSeconds,
    double startTimelineOffsetSec = 0.0,
    int wordsPerChunk = 3,
    CaptionStylePreset? preset,
    TextAnimationType? animationOverride,
    List<double>? beatTimestamps,
  }) {
    final script = trendingScripts[genre] ?? trendingScripts.values.first;
    return generateFromScript(
      script: script,
      totalDurationInSeconds: totalDurationInSeconds,
      startTimelineOffsetSec: startTimelineOffsetSec,
      wordsPerChunk: wordsPerChunk,
      preset: preset,
      animationOverride: animationOverride,
      beatTimestamps: beatTimestamps,
    );
  }
}
