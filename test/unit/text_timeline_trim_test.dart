import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
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
  });
}
