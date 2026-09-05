import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VideoClip createTestClip({
    required String id,
    required String title,
    required Duration duration,
    Duration trimStart = Duration.zero,
    Duration? trimEnd,
    double speed = 1.0,
    double volume = 1.0,
  }) {
    final effectiveTrimEnd = trimEnd ?? duration;
    return VideoClip(
      id: id,
      assetId: 'asset_$id',
      title: title,
      originalDuration: duration,
      trimStart: trimStart,
      trimEnd: effectiveTrimEnd,
      speed: speed,
      volume: volume,
      previewGradient: const [Colors.black, Colors.blue],
    );
  }

  group('Timeline Playhead Synchronization Tests (STEP 29C)', () {
    late EditorViewModel viewModel;

    setUp(() {
      VideoPlaybackService.instance.disposeAll();
      viewModel = EditorViewModel();
      viewModel.clearVideoClips();
      viewModel.clearAudioTracks();
      viewModel.clearOverlayClips();
      viewModel.clearTextOverlays();
    });

    tearDown(() {
      viewModel.dispose();
      VideoPlaybackService.instance.disposeAll();
    });

    test('1. Video controller position updates drive the timeline playhead accurately', () {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 10),
      );
      viewModel.addVideoClip(clip);
      expect(viewModel.totalDurationInSeconds, 10.0);

      // Register simulated native session
      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 10));
      viewModel.play();
      expect(viewModel.isPlaying, isTrue);

      // Simulate native position update at 3.5s
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 3500),
        const Duration(seconds: 10),
      );

      expect(viewModel.playheadPosition, closeTo(3.5, 0.001));

      // Simulate native position update at 7.2s
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 7200),
        const Duration(seconds: 10),
      );

      expect(viewModel.playheadPosition, closeTo(7.2, 0.001));
    });

    test('2. Fallback timer does not drift or advance when native session is emitting updates', () async {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 10),
      );
      viewModel.addVideoClip(clip);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 10));
      viewModel.play();

      // Emit 4.0s from native controller
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 4000),
        const Duration(seconds: 10),
      );
      expect(viewModel.playheadPosition, closeTo(4.0, 0.001));

      // Wait 100ms - since fallback timer is not running, position must not drift from 4.0
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(viewModel.playheadPosition, closeTo(4.0, 0.001));
    });

    test('3. Controller completion immediately clamps playhead to totalDurationInSeconds and pauses', () {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
      );
      viewModel.addVideoClip(clip);
      expect(viewModel.totalDurationInSeconds, 5.0);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 5));
      viewModel.play();

      // Emit completion from native player
      VideoPlaybackService.instance.emitSimulatedCompletion(
        1,
        const Duration(milliseconds: 5000),
      );

      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.playheadPosition, 5.0);
    });

    test('4. Position event reaching or exceeding clipEnd stops at exact boundary without overshoot', () {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
      );
      viewModel.addVideoClip(clip);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 5));
      viewModel.play();

      // Emit position beyond clip duration (e.g. 5.1s hardware clock overshoot)
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 5100),
        const Duration(seconds: 5),
      );

      // Must be strictly clamped to totalDurationInSeconds (5.0s) and paused
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.playheadPosition, 5.0);
    });

    test('5. Multi-clip boundary handoff smoothly advances to next clip start', () {
      final clip1 = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 4),
      );
      final clip2 = createTestClip(
        id: 'clip_2',
        title: 'Clip 2',
        duration: const Duration(seconds: 6),
      );
      viewModel.addVideoClip(clip1);
      viewModel.addVideoClip(clip2);
      expect(viewModel.totalDurationInSeconds, 10.0);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 4));
      viewModel.play();

      // Clip 1 finishes at 4.0s
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 4000),
        const Duration(seconds: 4),
      );

      // Playhead should be clamped to clip 1 end (4.0s) and still playing ready for clip 2
      expect(viewModel.isPlaying, isTrue);
      expect(viewModel.playheadPosition, 4.0);
      expect(viewModel.currentActiveClipAtPlayhead?.id, 'clip_2');
    });

    test('6. Stale callbacks after pause are rejected and do not move the playhead', () {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 10),
      );
      viewModel.addVideoClip(clip);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 10));
      viewModel.play();

      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 3000),
        const Duration(seconds: 10),
      );
      expect(viewModel.playheadPosition, closeTo(3.0, 0.001));

      // User pauses
      viewModel.pause();
      expect(viewModel.isPlaying, isFalse);

      // Stale hardware message arrives later
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 3500),
        const Duration(seconds: 10),
      );

      // Playhead must not have moved from 3.0
      expect(viewModel.playheadPosition, closeTo(3.0, 0.001));
    });

    test('7. Looping restarts playhead to 0.0 upon completion', () {
      final clip = createTestClip(
        id: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
      );
      viewModel.addVideoClip(clip);
      viewModel.setLooping(true);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_1.mp4', const Duration(seconds: 5));
      viewModel.play();

      VideoPlaybackService.instance.emitSimulatedCompletion(
        1,
        const Duration(milliseconds: 5000),
      );

      expect(viewModel.isPlaying, isTrue);
      expect(viewModel.playheadPosition, 0.0);
    });

    test('8. Respects clip trimStart, trimEnd, and speed in position calculations', () {
      // 10s video trimmed from 2s to 6s (duration = 4s), 2x speed -> timeline duration = 2s
      final clip = createTestClip(
        id: 'clip_trimmed',
        title: 'Trimmed Clip',
        duration: const Duration(seconds: 10),
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 6),
        speed: 2.0,
      );
      viewModel.addVideoClip(clip);
      expect(viewModel.totalDurationInSeconds, 2.0);

      VideoPlaybackService.instance.registerSimulatedSession(1, '/mock/path/clip_trimmed.mp4', const Duration(seconds: 10));
      viewModel.play();

      // Controller is at 4s in source media: delta = (4s - 2s) / 2.0 = 1.0s on timeline
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 4000),
        const Duration(seconds: 10),
      );

      expect(viewModel.playheadPosition, closeTo(1.0, 0.001));

      // Controller reaches 6s in source media: delta = (6s - 2s) / 2.0 = 2.0s -> completion
      VideoPlaybackService.instance.emitSimulatedPosition(
        1,
        const Duration(milliseconds: 6000),
        const Duration(seconds: 10),
      );

      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.playheadPosition, 2.0);
    });
  });
}
