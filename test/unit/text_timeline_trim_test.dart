import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/caption_word.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_text_track_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Timeline Text Duration Trimming & Gesture Hardening Suite', () {
    late EditorViewModel viewModel;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      viewModel = EditorViewModel();
      viewModel.loadProject(
        Project(
          id: 'test_trim_proj',
          name: 'Text Trim Project',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          videoClips: const [],
          audioTracks: const [],
          textOverlays: const [],
        ),
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('1. Right handle dragging extends text duration smoothly without arbitrary 5s/10s caps', () {
      const initialText = TextOverlay(
        id: 'txt_right_trim',
        text: 'Extended Caption',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 3),
      );
      viewModel.addTextOverlay(initialText);
      expect(viewModel.canUndo, isTrue);

      final oldStart = viewModel.textOverlays.first.startTime;
      final oldDur = viewModel.textOverlays.first.duration;

      // Simulate dragging right handle to extend duration from 3s to 25s
      const proposedEndSec = 2.0 + 25.0; // 27.0s
      final maxBound = TimelineTextTrackItem.getMaxProjectDuration(
        viewModel,
        viewModel.textOverlays.first,
      );
      expect(maxBound, greaterThanOrEqualTo(600.0)); // Empty project boundary is >= 600s

      final newEndSec = proposedEndSec.clamp(2.0 + 0.3, maxBound);
      final newDurSec = newEndSec - 2.0;

      // Real-time drag updates with saveSnapshot: false (0 undo spam)
      for (double step = 3.0; step <= newDurSec; step += 1.0) {
        viewModel.updateTextOverlayTiming(
          'txt_right_trim',
          oldStart,
          Duration(milliseconds: (step * 1000).round()),
          saveSnapshot: false,
          notify: true,
        );
      }

      // Timing updated correctly
      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 2)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 25)));

      // Commit gesture once onDragEnd
      viewModel.commitTextTiming(
        'txt_right_trim',
        oldStart: oldStart,
        oldDuration: oldDur,
      );

      // Verify exactly ONE undo action added
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();

      // Restored back to initial timing!
      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 2)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 3)));

      // Redo restores extended timing
      expect(viewModel.canRedo, isTrue);
      viewModel.redo();
      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 2)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 25)));
    });

    test('2. Right handle dragging clamps to minimum 0.3s duration', () {
      const initialText = TextOverlay(
        id: 'txt_min_dur',
        text: 'Short Clip',
        startTime: Duration(seconds: 5),
        duration: Duration(seconds: 4), // ends at 9s
      );
      viewModel.addTextOverlay(initialText);

      const initialStartSec = 5.0;
      // Try dragging right handle far to the left (e.g. -10s delta)
      const deltaSec = -10.0;
      const proposedEndSec = initialStartSec + 4.0 + deltaSec; // -1.0s
      const minEndSec = initialStartSec + 0.3; // 5.3s
      const maxEndSec = 600.0;
      final newEndSec = proposedEndSec.clamp(minEndSec, maxEndSec);
      final newDurSec = newEndSec - initialStartSec;

      expect(newDurSec, closeTo(0.3, 0.001));

      viewModel.updateTextOverlayTiming(
        'txt_min_dur',
        initialText.startTime,
        Duration(milliseconds: (newDurSec * 1000).round()),
        saveSnapshot: false,
      );

      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 5)));
      expect(viewModel.textOverlays.first.durationInSeconds, closeTo(0.3, 0.001));
    });

    test('3. Left handle dragging trims start time while preserving end time', () {
      const initialText = TextOverlay(
        id: 'txt_left_trim',
        text: 'Left Trim Test',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 6), // ends at 8.0s
      );
      viewModel.addTextOverlay(initialText);

      final oldStart = initialText.startTime;
      final oldDur = initialText.duration;
      const initialStartSec = 2.0;
      const initialDurSec = 6.0;
      const initialEndSec = initialStartSec + initialDurSec; // 8.0s

      // Drag left handle forward by +3.0s
      const deltaSec = 3.0;
      const proposedStartSec = initialStartSec + deltaSec; // 5.0s
      const minStart = 0.0;
      const maxStart = initialEndSec - 0.3; // 7.7s
      final newStartSec = proposedStartSec.clamp(minStart, maxStart);
      final newDurSec = initialEndSec - newStartSec; // 8.0 - 5.0 = 3.0s

      expect(newStartSec, equals(5.0));
      expect(newDurSec, equals(3.0));

      viewModel.updateTextOverlayTiming(
        'txt_left_trim',
        Duration(milliseconds: (newStartSec * 1000).round()),
        Duration(milliseconds: (newDurSec * 1000).round()),
        saveSnapshot: false,
      );

      viewModel.commitTextTiming(
        'txt_left_trim',
        oldStart: oldStart,
        oldDuration: oldDur,
      );

      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 5)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 3)));
      expect(viewModel.textOverlays.first.endTimeInSeconds, equals(8.0));

      // Test undo reverts left trim
      viewModel.undo();
      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 2)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 6)));
      expect(viewModel.textOverlays.first.endTimeInSeconds, equals(8.0));
    });

    test('4. Left handle dragging clamps to 0.0s min start and 0.3s min duration', () {
      const initialText = TextOverlay(
        id: 'txt_left_clamp',
        text: 'Clamp Test',
        startTime: Duration(seconds: 3),
        duration: Duration(seconds: 2), // ends at 5.0s
      );
      viewModel.addTextOverlay(initialText);

      const initialStartSec = 3.0;
      const initialEndSec = 5.0;

      // Attempt drag to the left beyond 0s (-10s delta)
      const backwardDelta = -10.0;
      const proposedBackwardStart = initialStartSec + backwardDelta;
      const minStart = 0.0;
      const maxStart = initialEndSec - 0.3; // 4.7s
      final clampedBackwardStart = proposedBackwardStart.clamp(minStart, maxStart);
      expect(clampedBackwardStart, equals(0.0));
      final backwardDur = initialEndSec - clampedBackwardStart;
      expect(backwardDur, equals(5.0)); // expanded start back to 0.0 while preserving 5.0s end

      // Attempt drag to the right past clip duration (+10s delta)
      const forwardDelta = 10.0;
      const proposedForwardStart = initialStartSec + forwardDelta;
      final clampedForwardStart = proposedForwardStart.clamp(minStart, maxStart);
      expect(clampedForwardStart, equals(4.7)); // clamped to leave 0.3s duration
      final forwardDur = initialEndSec - clampedForwardStart;
      expect(forwardDur, closeTo(0.3, 0.001));
    });

    test('5. Timeline body drag slides start time while keeping duration identical', () {
      const initialText = TextOverlay(
        id: 'txt_body_drag',
        text: 'Slide Translation',
        startTime: Duration(seconds: 4),
        duration: Duration(seconds: 5),
      );
      viewModel.addTextOverlay(initialText);

      final oldStart = initialText.startTime;
      final oldDur = initialText.duration;

      // Slide right by 6 seconds
      const deltaSec = 6.0;
      const newStartSec = 4.0 + deltaSec; // 10.0s

      viewModel.updateTextOverlayTiming(
        'txt_body_drag',
        Duration(milliseconds: (newStartSec * 1000).round()),
        oldDur,
        saveSnapshot: false,
      );

      viewModel.commitTextTiming(
        'txt_body_drag',
        oldStart: oldStart,
        oldDuration: oldDur,
      );

      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 10)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 5)));

      viewModel.undo();
      expect(viewModel.textOverlays.first.startTime, equals(const Duration(seconds: 4)));
      expect(viewModel.textOverlays.first.duration, equals(const Duration(seconds: 5)));
    });

    test('6. Project with video clips respects video duration boundary for text extension', () {
      const videoClip = VideoClip(
        id: 'clip_main',
        assetId: 'asset_video_orig',
        title: 'Main_Video.mp4',
        originalDuration: Duration(seconds: 15),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 15),
        previewGradient: [Colors.indigo, Colors.blue],
      );
      viewModel.addVideoClip(videoClip);

      const text = TextOverlay(
        id: 'txt_bounded',
        text: 'Bounded by video',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4), // ends at 5s
      );
      viewModel.addTextOverlay(text);

      final maxBound = TimelineTextTrackItem.getMaxProjectDuration(
        viewModel,
        viewModel.textOverlays.first,
      );

      expect(maxBound, equals(15.0)); // Bound to video length (15s)
    });

    test('7. Transparent text preview verification: default text has null background (100% transparent)', () {
      const defaultText = TextOverlay(
        id: 'txt_transparent',
        text: 'No Background Fill',
        startTime: Duration.zero,
        duration: Duration(seconds: 3),
      );

      expect(defaultText.backgroundColor, isNull);
      final effectiveBgColor = defaultText.backgroundColor ?? Colors.transparent;
      expect(effectiveBgColor, equals(Colors.transparent));

      // With custom background color set
      final styledText = defaultText.copyWith(
        backgroundColor: Colors.blue.withOpacity(0.5),
      );
      final effectiveStyledBg = styledText.backgroundColor ?? Colors.transparent;
      expect(effectiveStyledBg, equals(Colors.blue.withOpacity(0.5)));
    });

    test('8. Animated text extends to full project boundary (30s video, text at 5s extends to 25s) across all animation types', () {
      const videoClip = VideoClip(
        id: 'clip_30s',
        assetId: 'asset_30s',
        title: '30s_Video.mp4',
        originalDuration: Duration(seconds: 30),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 30),
        previewGradient: [Colors.purple, Colors.deepPurple],
      );
      viewModel.addVideoClip(videoClip);
      expect(viewModel.totalDurationInSeconds, equals(30.0));

      for (final anim in TextAnimationType.values) {
        final animatedText = TextOverlay(
          id: 'txt_anim_${anim.name}',
          text: 'Title with ${anim.displayName}',
          startTime: const Duration(seconds: 5),
          duration: const Duration(seconds: 4), // 5s -> 9s
          animationType: anim,
        );
        viewModel.addTextOverlay(animatedText);

        final maxBound = TimelineTextTrackItem.getMaxProjectDuration(
          viewModel,
          viewModel.textOverlays.last,
        );
        expect(maxBound, equals(30.0));

        // Simulate dragging right handle all the way to 25s duration (ends at 30s)
        const targetDuration = Duration(seconds: 20); // 5s + 20s = 25s endTime
        viewModel.updateTextOverlayTiming(
          animatedText.id,
          animatedText.startTime,
          targetDuration,
          saveSnapshot: false,
          notify: true,
        );

        final updated = viewModel.textOverlays.firstWhere((t) => t.id == animatedText.id);
        expect(updated.startTime, equals(const Duration(seconds: 5)));
        expect(updated.duration, equals(targetDuration));
        expect(updated.durationInSeconds, equals(20.0));
        expect(updated.endTimeInSeconds, equals(25.0));
        expect(updated.animationType, equals(anim));

        // Extend further up to full project boundary (30.0s)
        viewModel.updateTextOverlayTiming(
          animatedText.id,
          animatedText.startTime,
          const Duration(seconds: 25), // ends at 30.0s
          saveSnapshot: false,
          notify: true,
        );

        final fullyExtended = viewModel.textOverlays.firstWhere((t) => t.id == animatedText.id);
        expect(fullyExtended.endTimeInSeconds, equals(30.0));
        expect(fullyExtended.durationInSeconds, equals(25.0));

        viewModel.removeTextOverlay(animatedText.id);
      }
    });

    test('9. Text pacing speed adjustment does NOT compress or clamp text layer duration', () {
      const animatedText = TextOverlay(
        id: 'txt_speed_decoupled',
        text: 'Fast Paced Title',
        startTime: Duration(seconds: 3),
        duration: Duration(seconds: 6),
        speed: 2.0, // 2x animation pacing speed
        animationType: TextAnimationType.fade,
      );
      viewModel.addTextOverlay(animatedText);

      // Duration must remain 6.0 seconds (decoupled from animation pacing speed)
      expect(viewModel.textOverlays.first.durationInSeconds, equals(6.0));
      expect(viewModel.textOverlays.first.effectiveDuration, equals(const Duration(seconds: 6)));
      expect(viewModel.textOverlays.first.speed, equals(2.0));

      // Right handle extend from 6s to 18s works with 1:1 math without dividing by 2.0
      viewModel.updateTextOverlayTiming(
        'txt_speed_decoupled',
        const Duration(seconds: 3),
        const Duration(seconds: 18),
        saveSnapshot: false,
      );

      final updated = viewModel.textOverlays.first;
      expect(updated.durationInSeconds, equals(18.0));
      expect(updated.endTimeInSeconds, equals(21.0));
      expect(updated.speed, equals(2.0));
    });

    test('10. Karaoke animation dynamically scales word timestamps proportionally when text is extended', () {
      final initialWords = [
        const CaptionWord(word: 'CREATE', startOffsetSec: 0.0, durationSec: 1.0),
        const CaptionWord(word: 'AMAZING', startOffsetSec: 1.0, durationSec: 1.0),
        const CaptionWord(word: 'VIDEOS', startOffsetSec: 2.0, durationSec: 1.0),
      ]; // Spans 3.0 seconds total

      final caption = TextOverlay(
        id: 'txt_karaoke_scale',
        text: 'CREATE AMAZING VIDEOS',
        startTime: const Duration(seconds: 2),
        duration: const Duration(seconds: 3),
        animationType: TextAnimationType.karaoke,
        words: initialWords,
      );
      viewModel.addTextOverlay(caption);

      // At 1.5s in original 3s duration, active word is index 1 ("AMAZING")
      expect(caption.getActiveWordIndex(1.5), equals(1));

      // User extends duration from 3s to 12s (4x duration expansion)
      viewModel.updateTextOverlayTiming(
        'txt_karaoke_scale',
        const Duration(seconds: 2),
        const Duration(seconds: 12),
        saveSnapshot: false,
      );

      final extended = viewModel.textOverlays.first;
      expect(extended.durationInSeconds, equals(12.0));

      // Scaled words should span 12s proportionally
      final scaledWords = extended.effectiveWords;
      expect(scaledWords.length, equals(3));
      expect(scaledWords[0].startOffsetSec, closeTo(0.0, 0.001));
      expect(scaledWords[0].durationSec, closeTo(4.0, 0.001));
      expect(scaledWords[1].startOffsetSec, closeTo(4.0, 0.001));
      expect(scaledWords[1].durationSec, closeTo(4.0, 0.001));
      expect(scaledWords[2].startOffsetSec, closeTo(8.0, 0.001));
      expect(scaledWords[2].durationSec, closeTo(4.0, 0.001));

      // At 6.0s (halfway through 12s), active word is correctly index 1 ("AMAZING")
      expect(extended.getActiveWordIndex(6.0), equals(1));
      // At 10.0s (in the last third), active word is correctly index 2 ("VIDEOS")
      expect(extended.getActiveWordIndex(10.0), equals(2));
    });

    test('11. Animated text left handle trimming preserves end time and records single undo', () {
      const animatedText = TextOverlay(
        id: 'txt_left_anim_trim',
        text: 'Typewriter Headline',
        startTime: Duration(seconds: 4),
        duration: Duration(seconds: 8), // ends at 12.0s
        animationType: TextAnimationType.typewriter,
      );
      viewModel.addTextOverlay(animatedText);

      final oldStart = animatedText.startTime;
      final oldDur = animatedText.duration;

      // Trim left edge forward by +3s (new start = 7s, new duration = 5s, end remains 12s)
      viewModel.updateTextOverlayTiming(
        'txt_left_anim_trim',
        const Duration(seconds: 7),
        const Duration(seconds: 5),
        saveSnapshot: false,
        notify: true,
      );

      viewModel.commitTextTiming(
        'txt_left_anim_trim',
        oldStart: oldStart,
        oldDuration: oldDur,
      );

      final trimmed = viewModel.textOverlays.first;
      expect(trimmed.startTimeInSeconds, equals(7.0));
      expect(trimmed.durationInSeconds, equals(5.0));
      expect(trimmed.endTimeInSeconds, equals(12.0));
      expect(trimmed.animationType, equals(TextAnimationType.typewriter));

      // Undo restores exact start and duration
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();

      final undone = viewModel.textOverlays.first;
      expect(undone.startTimeInSeconds, equals(4.0));
      expect(undone.durationInSeconds, equals(8.0));
      expect(undone.endTimeInSeconds, equals(12.0));
      expect(undone.animationType, equals(TextAnimationType.typewriter));
    });

    test('12. TimelineTextTrackItem drag delta calculation with scroll offset handles extended dragging', () {
      // Test the math used in _onRightHandleDragUpdate:
      // deltaPx = (globalX - dragStartX) + (scrollOffset - dragStartScrollOffset)
      const pps = 50.0;
      const initialStartSec = 5.0;
      const initialDurSec = 4.0;
      const dragStartX = 250.0;
      const dragStartScrollOffset = 0.0;

      // User holds finger near right edge at globalX = 360, while timeline auto-scrolls to offset = 800.0
      const currentGlobalX = 360.0;
      const currentScrollOffset = 800.0;

      final deltaPx = (currentGlobalX - dragStartX) + (currentScrollOffset - dragStartScrollOffset);
      final deltaSec = deltaPx / pps; // (110 + 800) / 50 = 910 / 50 = 18.2s
      expect(deltaSec, closeTo(18.2, 0.001));

      final proposedEndSec = initialStartSec + initialDurSec + deltaSec; // 5 + 4 + 18.2 = 27.2s
      expect(proposedEndSec, closeTo(27.2, 0.001));

      const maxProjectDuration = 30.0;
      final newEndSec = proposedEndSec.clamp(initialStartSec + 0.3, maxProjectDuration);
      final newDurSec = newEndSec - initialStartSec; // 22.2s

      expect(newEndSec, closeTo(27.2, 0.001));
      expect(newDurSec, closeTo(22.2, 0.001));
    });
  });
}
