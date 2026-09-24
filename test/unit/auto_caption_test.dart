import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/caption_word.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/core/services/auto_caption_service.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  group('CaptionWord & TextOverlay Animation Domain Tests', () {
    test('CaptionWord serialization and end offset calculation', () {
      const word = CaptionWord(
        word: 'VIRAL',
        startOffsetSec: 0.5,
        durationSec: 0.35,
        customColor: Color(0xFFFFEB3B),
      );

      expect(word.endOffsetSec, closeTo(0.85, 1e-4));

      final json = word.toJson();
      final revived = CaptionWord.fromJson(json);

      expect(revived.word, equals('VIRAL'));
      expect(revived.startOffsetSec, equals(0.5));
      expect(revived.durationSec, equals(0.35));
      expect(revived.customColor?.value, equals(const Color(0xFFFFEB3B).value));
    });

    test('TextOverlay getActiveWordIndex with explicit words', () {
      const overlay = TextOverlay(
        id: 'cap_1',
        text: 'MAKE IT HAPPEN',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 3),
        animationType: TextAnimationType.karaoke,
        words: [
          CaptionWord(word: 'MAKE', startOffsetSec: 0.0, durationSec: 0.8),
          CaptionWord(word: 'IT', startOffsetSec: 0.8, durationSec: 0.6),
          CaptionWord(word: 'HAPPEN', startOffsetSec: 1.4, durationSec: 1.2),
        ],
      );

      // At 0.4s: "MAKE" is active (index 0)
      expect(overlay.getActiveWordIndex(0.4), equals(0));
      // At 1.0s: "IT" is active (index 1)
      expect(overlay.getActiveWordIndex(1.0), equals(1));
      // At 2.0s: "HAPPEN" is active (index 2)
      expect(overlay.getActiveWordIndex(2.0), equals(2));
      // At 3.0s: clamps to last word
      expect(overlay.getActiveWordIndex(3.0), equals(2));
    });

    test('TextOverlay getActiveWordIndex fallback proportional calculation', () {
      const overlay = TextOverlay(
        id: 'cap_2',
        text: 'FOCUS ON GOALS',
        startTime: Duration.zero,
        duration: Duration(seconds: 3), // 3 words across 3 seconds -> ~1.0s per word
        animationType: TextAnimationType.karaoke,
      );

      expect(overlay.getActiveWordIndex(0.5), equals(0));
      expect(overlay.getActiveWordIndex(1.5), equals(1));
      expect(overlay.getActiveWordIndex(2.5), equals(2));
    });

    test('TextOverlay backwards compatible serialization with stroke and animations', () {
      const overlay = TextOverlay(
        id: 'cap_hormozi',
        text: 'START NOW',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 2),
        animationType: TextAnimationType.karaoke,
        highlightColor: Color(0xFFFFEB3B),
        strokeWidth: 3.0,
        strokeColor: Colors.black,
      );

      final json = overlay.toJson();
      final revived = TextOverlay.fromJson(json);

      expect(revived.id, equals('cap_hormozi'));
      expect(revived.text, equals('START NOW'));
      expect(revived.animationType, equals(TextAnimationType.karaoke));
      expect(revived.highlightColor?.value, equals(const Color(0xFFFFEB3B).value));
      expect(revived.strokeWidth, equals(3.0));
    });
  });

  group('AutoCaptionService Generation Tests', () {
    late AutoCaptionService service;

    setUp(() {
      service = AutoCaptionService.instance;
    });

    test('generateFromScript breaks script into specified word chunks', () {
      const script = 'ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE';
      final captions = service.generateFromScript(
        script: script,
        totalDurationInSeconds: 10.0,
        wordsPerChunk: 3,
        preset: CaptionStylePreset.findById(CaptionStylePresetId.hormozi),
      );

      expect(captions.length, equals(3)); // 9 words / 3 = 3 chunks
      expect(captions[0].text, equals('ONE TWO THREE'));
      expect(captions[1].text, equals('FOUR FIVE SIX'));
      expect(captions[2].text, equals('SEVEN EIGHT NINE'));

      // Check Hormozi preset applied
      expect(captions[0].strokeWidth, equals(3.0));
      expect(captions[0].highlightColor, equals(const Color(0xFFFFEB3B)));
      expect(captions[0].animationType, equals(TextAnimationType.karaoke));
      expect(captions[0].words.length, equals(3));
    });

    test('generateFromScript aligns start times with musical beats', () {
      const script = 'DROP THE BASS NOW';
      final beatTimestamps = [1.0, 2.5, 4.0];

      final captions = service.generateFromScript(
        script: script,
        totalDurationInSeconds: 6.0,
        startTimelineOffsetSec: 0.8, // Close to beat 1.0s
        wordsPerChunk: 2,
        beatTimestamps: beatTimestamps,
      );

      expect(captions, isNotEmpty);
      // First caption snapped to the nearby 1.0s beat!
      expect(captions[0].startTimeInSeconds, closeTo(1.0, 0.05));
    });

    test('generateTrending loads preconfigured viral script templates', () {
      final motivationCaptions = service.generateTrending(
        genre: 'Motivation',
        totalDurationInSeconds: 8.0,
        wordsPerChunk: 3,
      );

      expect(motivationCaptions, isNotEmpty);
      expect(motivationCaptions.first.text, contains('STOP'));
    });
  });

  group('EditorViewModel Auto Captions Workflow Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
      viewModel.initForTesting();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('generateAutoCaptions adds synced captions to timeline', () {
      expect(viewModel.textOverlays, isEmpty);

      final count = viewModel.generateAutoCaptions(
        script: 'BUILD SOMETHING AWESOME WITH FLUTTER TODAY',
        wordsPerChunk: 3,
        preset: CaptionStylePreset.findById(CaptionStylePresetId.cyberNeon),
      );

      expect(count, greaterThan(0));
      expect(viewModel.textOverlays.length, equals(count));
      expect(viewModel.textOverlays.first.animationType, equals(TextAnimationType.karaoke));
      expect(viewModel.textOverlays.first.highlightColor, equals(const Color(0xFF00E5FF)));
    });

    test('applyCaptionStyleToAll propagates visual styling across all subtitles', () {
      // Generate initial captions
      viewModel.generateAutoCaptions(
        script: 'FIRST LINE SECOND LINE THIRD LINE',
        wordsPerChunk: 2,
      );
      expect(viewModel.textOverlays, isNotEmpty);

      // Create Golden VIP template style
      const vipStyle = TextOverlay(
        id: 'vip_template',
        text: 'TEST',
        startTime: Duration.zero,
        duration: Duration(seconds: 2),
        textColor: Color(0xFFFFD54F),
        highlightColor: Colors.white,
        strokeWidth: 2.0,
        strokeColor: Color(0xFFFFA000),
        animationType: TextAnimationType.glowPulse,
      );

      viewModel.applyCaptionStyleToAll(vipStyle);

      for (final text in viewModel.textOverlays) {
        expect(text.textColor.value, equals(const Color(0xFFFFD54F).value));
        expect(text.highlightColor?.value, equals(Colors.white.value));
        expect(text.strokeWidth, equals(2.0));
        expect(text.animationType, equals(TextAnimationType.glowPulse));
      }
    });

    test('updateTextAnimation updates single caption animation type', () {
      viewModel.generateAutoCaptions(
        script: 'TESTING ANIMATION UPDATES',
        wordsPerChunk: 3,
      );
      final id = viewModel.textOverlays.first.id;

      viewModel.updateTextAnimation(
        id,
        TextAnimationType.pop,
        highlightColor: const Color(0xFFFF5252),
      );

      final updated = viewModel.textOverlays.firstWhere((t) => t.id == id);
      expect(updated.animationType, equals(TextAnimationType.pop));
      expect(updated.highlightColor?.value, equals(const Color(0xFFFF5252).value));
    });
  });
}
