import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorViewModel viewModel;

  setUp(() {
    viewModel = EditorViewModel();
    viewModel.clearVideoClips();
    viewModel.clearAudioTracks();
    viewModel.clearOverlayClips();
    viewModel.clearTextOverlays();
  });

  tearDown(() {
    viewModel.dispose();
  });

  VideoClip createTestClip({
    required String id,
    required String assetId,
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
      assetId: assetId,
      title: title,
      originalDuration: duration,
      trimStart: trimStart,
      trimEnd: effectiveTrimEnd,
      speed: speed,
      volume: volume,
      previewGradient: const [Colors.black, Colors.blue],
    );
  }

  MediaAsset createTestAsset({
    required String id,
    required String name,
    required Duration duration,
    String? localPath,
  }) {
    return MediaAsset(
      id: id,
      type: MediaAssetType.video,
      name: name,
      duration: duration,
      localPath: localPath ?? '/mock/.mp4',
      createdAt: DateTime.now(),
    );
  }

  group('CapCut-like Delete & Ripple Delete Engine Test Suite', () {
    // 1. Normal video delete
    test('1. Normal video delete removes selected clip without deleting MediaAsset', () {
      final asset = createTestAsset(id: 'asset_v1', name: 'Video 1', duration: const Duration(seconds: 10));
      viewModel.addMediaAsset(asset);

      final clip1 = createTestClip(id: 'c1', assetId: 'asset_v1', title: 'Clip 1', duration: const Duration(seconds: 5));
      final clip2 = createTestClip(id: 'c2', assetId: 'asset_v1', title: 'Clip 2', duration: const Duration(seconds: 5));

      viewModel.addVideoClip(clip1);
      viewModel.addVideoClip(clip2);
      expect(viewModel.videoClips.length, 2);

      viewModel.selectClip(0);
      final success = viewModel.deleteSelectedClip();

      expect(success, isTrue);
      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'c2');
      expect(viewModel.mediaLibrary.any((a) => a.id == 'asset_v1'), isTrue);
    });

    // 2. Normal audio delete
    test('2. Normal audio delete removes selected audio track and disposes service if empty', () {
      final audioAsset = MediaAsset(
        id: 'asset_a1',
        type: MediaAssetType.audio,
        name: 'BGM.mp3',
        duration: const Duration(seconds: 20),
        localPath: '/mock/bgm.mp3',
        createdAt: DateTime.now(),
      );
      viewModel.addMediaAsset(audioAsset);

      const track = AudioTrack(
        id: 'track_bgm',
        assetId: 'asset_a1',
        title: 'BGM',
        artist: 'Artist',
        duration: Duration(seconds: 20),
        startTime: Duration(seconds: 2),
      );
      viewModel.addAudioTrack(track);
      expect(viewModel.audioTracks.length, 1);

      viewModel.deleteSelectedAudioTrack();
      expect(viewModel.audioTracks, isEmpty);
      expect(viewModel.selectedAudioTrack, isNull);
      expect(viewModel.mediaLibrary.any((a) => a.id == 'asset_a1'), isTrue);
    });

    // 3. Extracted audio delete
    test('3. Extracted audio delete removes extracted track without mutating source video clip', () {
      final videoClip = createTestClip(id: 'c_src', assetId: 'asset_src', title: 'Source', duration: const Duration(seconds: 8), volume: 0.0);
      viewModel.addVideoClip(videoClip);

      const extractedTrack = AudioTrack(
        id: 'audio_extracted_001',
        assetId: 'asset_extracted_wav',
        title: 'Extracted Track',
        artist: 'Extracted Audio',
        duration: Duration(seconds: 8),
        startTime: Duration.zero,
      );
      viewModel.addAudioTrack(extractedTrack);

      expect(viewModel.videoClips.first.volume, 0.0);
      expect(viewModel.audioTracks.length, 1);

      viewModel.selectAudioTrack('audio_extracted_001');
      viewModel.deleteSelectedAudioTrack();

      expect(viewModel.audioTracks, isEmpty);
      // Source video clip still has its volume intact
      expect(viewModel.videoClips.first.volume, 0.0);
    });

    // 4. Overlay delete
    test('4. Overlay delete removes overlay without modifying main video timeline', () {
      viewModel.addVideoClip(createTestClip(id: 'v1', assetId: 'a1', title: 'Main', duration: const Duration(seconds: 10)));

      const overlay = OverlayClip(
        id: 'pip_1',
        title: 'PIP Layer',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 4),
        previewGradient: [],
      );
      viewModel.addOverlayClip(overlay);
      expect(viewModel.overlayClips.length, 1);

      viewModel.removeOverlayClip('pip_1');
      expect(viewModel.overlayClips, isEmpty);
      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.durationInSeconds, 10.0);
    });

    // 5. Text delete
    test('5. Text delete removes text overlay without modifying other layers', () {
      const text = TextOverlay(
        id: 'txt_title',
        text: 'Hello World',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 5),
      );
      viewModel.addTextOverlay(text);
      expect(viewModel.textOverlays.length, 1);

      viewModel.deleteSelectedText();
      expect(viewModel.textOverlays, isEmpty);
      expect(viewModel.selectedTextId, isNull);
    });

    // 6. Main-track ripple delete
    test('6. Main-track ripple delete closes gap cleanly', () {
      // A: 0-5, B: 5-10, C: 10-15
      viewModel.addVideoClip(createTestClip(id: 'A', assetId: 'a', title: 'A', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'B', assetId: 'b', title: 'B', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'C', assetId: 'c', title: 'C', duration: const Duration(seconds: 5)));

      expect(viewModel.totalDurationInSeconds, 15.0);

      viewModel.selectClip(1); // Select B
      final success = viewModel.rippleDeleteSelectedClip();

      expect(success, isTrue);
      expect(viewModel.videoClips.length, 2);
      expect(viewModel.videoClips[0].id, 'A');
      expect(viewModel.videoClips[1].id, 'C');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.getClipStartTime(1), 5.0);
      expect(viewModel.totalDurationInSeconds, 10.0);
    });

    // 7. Ripple delete middle clip
    test('7. Ripple delete middle clip shifts subsequent clips and preserves their durations', () {
      // Clip 1 (3s), Clip 2 (4s), Clip 3 (5s) -> total 12s
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 3)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 5)));

      viewModel.selectClip(1); // Delete C2 (4s)
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.videoClips.length, 2);
      expect(viewModel.videoClips[0].id, 'c1');
      expect(viewModel.videoClips[1].id, 'c3');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.getClipStartTime(1), 3.0);
      expect(viewModel.totalDurationInSeconds, 8.0);
    });

    // 8. Ripple delete first clip
    test('8. Ripple delete first clip shifts all subsequent clips to start at 0.0', () {
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 6)));

      viewModel.selectClip(0);
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'c2');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.totalDurationInSeconds, 6.0);
      expect(viewModel.selectedClip?.id, 'c2');
    });

    // 9. Ripple delete last clip
    test('9. Ripple delete last clip shrinks total duration without shifting preceding clips', () {
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 6)));

      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'c1');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.totalDurationInSeconds, 4.0);
      expect(viewModel.selectedClip?.id, 'c1');
    });

    // 10. Split -> delete
    test('10. Split then normal delete removes split segment', () {
      viewModel.addVideoClip(createTestClip(id: 'c_orig', assetId: 'asset_split', title: 'Original', duration: const Duration(seconds: 10)));
      viewModel.seekTo(4.0);

      final splitSuccess = viewModel.splitClipAtPlayhead();
      expect(splitSuccess, isTrue);
      expect(viewModel.videoClips.length, 2);

      // Part B is selected by default (index 1)
      expect(viewModel.selectedClipIndex, 1);
      final delSuccess = viewModel.deleteSelectedClip();
      expect(delSuccess, isTrue);

      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.durationInSeconds, 4.0);
      expect(viewModel.totalDurationInSeconds, 4.0);
    });

    // 11. Split -> ripple delete
    test('11. Split B at 7s in [A (0-5), B (5-10), C (10-15)] then ripple delete B1 gives [A (0-5), B2 (5-8), C (8-13)]', () {
      viewModel.addVideoClip(createTestClip(id: 'A', assetId: 'a', title: 'A', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'B', assetId: 'b', title: 'B', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'C', assetId: 'c', title: 'C', duration: const Duration(seconds: 5)));

      // Split B at 7.0s (2.0s into B)
      viewModel.seekTo(7.0);
      viewModel.selectClip(1);
      final splitOk = viewModel.splitClipAtPlayhead();
      expect(splitOk, isTrue);

      // We have A (5s), B1 (2s), B2 (3s), C (5s)
      expect(viewModel.videoClips.length, 4);
      expect(viewModel.videoClips[1].durationInSeconds, 2.0);
      expect(viewModel.videoClips[2].durationInSeconds, 3.0);

      // Select B1 (index 1) and Ripple Delete
      viewModel.selectClip(1);
      final rippleOk = viewModel.rippleDeleteSelectedClip();
      expect(rippleOk, isTrue);

      // Expected: A (0-5), B2 (5-8), C (8-13)
      expect(viewModel.videoClips.length, 3);
      expect(viewModel.videoClips[0].id, 'A');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.videoClips[0].durationInSeconds, 5.0);

      expect(viewModel.getClipStartTime(1), 5.0);
      expect(viewModel.videoClips[1].durationInSeconds, 3.0);

      expect(viewModel.getClipStartTime(2), 8.0);
      expect(viewModel.videoClips[2].durationInSeconds, 5.0);

      expect(viewModel.totalDurationInSeconds, 13.0);
    });

    // 12. Multiple sequential ripple deletes
    test('12. Multiple sequential ripple deletes consistently close gaps', () {
      for (int i = 0; i < 5; i++) {
        viewModel.addVideoClip(createTestClip(id: 'clip_$i', assetId: 'asset_$i', title: 'Clip $i', duration: const Duration(seconds: 2)));
      }
      expect(viewModel.totalDurationInSeconds, 10.0);

      // Delete clip 1 (2-4s)
      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();
      expect(viewModel.totalDurationInSeconds, 8.0);
      expect(viewModel.videoClips.length, 4);

      // Delete clip 2 (now at index 1, originally clip 2)
      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();
      expect(viewModel.totalDurationInSeconds, 6.0);
      expect(viewModel.videoClips.length, 3);

      expect(viewModel.videoClips[0].id, 'clip_0');
      expect(viewModel.videoClips[1].id, 'clip_3');
      expect(viewModel.videoClips[2].id, 'clip_4');
    });

    // 13. Correct following-clip shift
    test('13. Following clips keep exact internal speed, volume, and trim parameters after shift', () {
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a1', title: 'C1', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(
        id: 'c2',
        assetId: 'a2',
        title: 'C2',
        duration: const Duration(seconds: 10),
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 8),
        speed: 2.0,
        volume: 0.75,
      ));

      viewModel.selectClip(0);
      viewModel.rippleDeleteSelectedClip();

      final remaining = viewModel.videoClips.first;
      expect(remaining.id, 'c2');
      expect(remaining.speed, 2.0);
      expect(remaining.volume, 0.75);
      expect(remaining.trimStart, const Duration(seconds: 2));
      expect(remaining.trimEnd, const Duration(seconds: 8));
      // (8s - 2s) / 2.0x = 3s active duration
      expect(remaining.durationInSeconds, 3.0);
      expect(viewModel.getClipStartTime(0), 0.0);
    });

    // 14. No gap after ripple
    test('14. No gap between clips after ripple delete', () {
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 3)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 5)));

      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();

      final c1End = viewModel.getClipStartTime(0) + viewModel.videoClips[0].durationInSeconds;
      final c3Start = viewModel.getClipStartTime(1);
      expect(c1End, equals(c3Start));
    });

    // 15. No overlap after ripple
    test('15. No overlap between adjacent clips after ripple delete', () {
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 2)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 3)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 4)));

      viewModel.selectClip(0);
      viewModel.rippleDeleteSelectedClip();

      for (int i = 0; i < viewModel.videoClips.length - 1; i++) {
        final currentEnd = viewModel.getClipStartTime(i) + viewModel.videoClips[i].durationInSeconds;
        final nextStart = viewModel.getClipStartTime(i + 1);
        expect(currentEnd, equals(nextStart));
      }
    });

    // 16. Playhead before deleted region
    test('16. Playhead before deleted region remains unchanged', () {
      // c1: 0-5, c2: 5-10, c3: 10-15
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 5)));

      viewModel.seekTo(2.5);
      viewModel.selectClip(1); // Delete c2 (5-10)
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.playheadPosition, 2.5);
    });

    // 17. Playhead inside deleted region
    test('17. Playhead inside deleted region is placed at beginning of deleted region', () {
      // c1: 0-5, c2: 5-10, c3: 10-15
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 5)));

      viewModel.seekTo(7.5); // inside c2 (5-10)
      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.playheadPosition, 5.0);
    });

    // 18. Playhead after deleted region
    test('18. Playhead after deleted region is shifted backward by deleted duration', () {
      // c1: 0-5, c2: 5-10, c3: 10-15
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a', title: 'C1', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'b', title: 'C2', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c3', assetId: 'c', title: 'C3', duration: const Duration(seconds: 5)));

      viewModel.seekTo(12.0); // inside c3 (10-15)
      viewModel.selectClip(1); // Delete c2 (duration 5s)
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.playheadPosition, 7.0); // 12.0 - 5.0 = 7.0
    });

    // 19. Project duration recalculation
    test('19. Project duration recalculates based on longest remaining content across layers', () {
      // Video: 10s (5s + 5s)
      viewModel.addVideoClip(createTestClip(id: 'v1', assetId: 'a1', title: 'V1', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'v2', assetId: 'a2', title: 'V2', duration: const Duration(seconds: 5)));

      // Text: 0-12s
      const text = TextOverlay(
        id: 't_long',
        text: 'Long Text',
        startTime: Duration.zero,
        duration: Duration(seconds: 12),
      );
      viewModel.addTextOverlay(text);

      expect(viewModel.totalDurationInSeconds, 12.0);

      // Ripple delete v2 (5s) -> Video total becomes 5s, but text is 12s
      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.totalDurationInSeconds, 12.0);
    });

    // 20. MediaAsset remains after timeline deletion
    test('20. Deleting all timeline clips does NOT remove MediaAsset from library', () {
      final asset = createTestAsset(id: 'asset_keep', name: 'Master.mp4', duration: const Duration(seconds: 10));
      viewModel.addMediaAsset(asset);
      viewModel.addVideoClip(createTestClip(id: 'clip_only', assetId: 'asset_keep', title: 'Clip Only', duration: const Duration(seconds: 10)));

      viewModel.selectClip(0);
      viewModel.deleteSelectedClip();

      expect(viewModel.videoClips, isEmpty);
      expect(viewModel.mediaLibrary.any((a) => a.id == 'asset_keep'), isTrue);
    });

    // 21. Shared MediaAsset after split/delete
    test('21. Split clips sharing assetId: deleting one does not invalidate the other or the MediaAsset', () {
      final asset = createTestAsset(id: 'asset_shared', name: 'Shared.mp4', duration: const Duration(seconds: 10));
      viewModel.addMediaAsset(asset);

      final part1 = createTestClip(id: 'part_1', assetId: 'asset_shared', title: 'Part 1', duration: const Duration(seconds: 10), trimEnd: const Duration(seconds: 4));
      final part2 = createTestClip(id: 'part_2', assetId: 'asset_shared', title: 'Part 2', duration: const Duration(seconds: 10), trimStart: const Duration(seconds: 4));

      viewModel.addVideoClip(part1);
      viewModel.addVideoClip(part2);

      viewModel.selectClip(1);
      viewModel.deleteSelectedClip();

      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'part_1');
      expect(viewModel.videoClips.first.assetId, 'asset_shared');
      expect(viewModel.mediaLibrary.any((a) => a.id == 'asset_shared'), isTrue);
    });

    // 22. Selection after delete
    test('22. Selection shifts to replacement clip or nearest remaining item', () {
      viewModel.addVideoClip(createTestClip(id: 'c0', assetId: 'a0', title: 'C0', duration: const Duration(seconds: 3)));
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a1', title: 'C1', duration: const Duration(seconds: 3)));
      viewModel.addVideoClip(createTestClip(id: 'c2', assetId: 'a2', title: 'C2', duration: const Duration(seconds: 3)));

      viewModel.selectClip(1); // Select C1
      viewModel.rippleDeleteSelectedClip();

      // C2 moved to index 1 -> C2 should now be selected
      expect(viewModel.selectedClipIndex, 1);
      expect(viewModel.selectedClip?.id, 'c2');
    });

    // 23. Undo delete
    test('23. Undo delete restores the removed clip and original total duration', () {
      viewModel.addVideoClip(createTestClip(id: 'c0', assetId: 'a0', title: 'C0', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a1', title: 'C1', duration: const Duration(seconds: 5)));

      viewModel.selectClip(0);
      viewModel.deleteSelectedClip();
      expect(viewModel.videoClips.length, 1);

      viewModel.undo();
      expect(viewModel.videoClips.length, 2);
      expect(viewModel.videoClips[0].id, 'c0');
      expect(viewModel.videoClips[1].id, 'c1');
      expect(viewModel.totalDurationInSeconds, 10.0);
    });

    // 24. Redo delete
    test('24. Redo delete re-applies the deletion correctly', () {
      viewModel.addVideoClip(createTestClip(id: 'c0', assetId: 'a0', title: 'C0', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'c1', assetId: 'a1', title: 'C1', duration: const Duration(seconds: 5)));

      viewModel.selectClip(0);
      viewModel.deleteSelectedClip();
      viewModel.undo();
      viewModel.redo();

      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'c1');
    });

    // 25. Undo ripple delete
    test('25. Undo ripple delete restores deleted clip and re-shifts subsequent clips to original positions', () {
      viewModel.addVideoClip(createTestClip(id: 'A', assetId: 'a', title: 'A', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'B', assetId: 'b', title: 'B', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'C', assetId: 'c', title: 'C', duration: const Duration(seconds: 4)));

      viewModel.selectClip(1); // Delete B
      viewModel.rippleDeleteSelectedClip();

      expect(viewModel.videoClips.length, 2);
      expect(viewModel.getClipStartTime(1), 4.0);

      viewModel.undo();

      expect(viewModel.videoClips.length, 3);
      expect(viewModel.videoClips[0].id, 'A');
      expect(viewModel.videoClips[1].id, 'B');
      expect(viewModel.videoClips[2].id, 'C');
      expect(viewModel.getClipStartTime(0), 0.0);
      expect(viewModel.getClipStartTime(1), 4.0);
      expect(viewModel.getClipStartTime(2), 8.0);
      expect(viewModel.totalDurationInSeconds, 12.0);
    });

    // 26. Redo ripple delete
    test('26. Redo ripple delete re-applies ripple deletion with exact timings', () {
      viewModel.addVideoClip(createTestClip(id: 'A', assetId: 'a', title: 'A', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'B', assetId: 'b', title: 'B', duration: const Duration(seconds: 4)));
      viewModel.addVideoClip(createTestClip(id: 'C', assetId: 'c', title: 'C', duration: const Duration(seconds: 4)));

      viewModel.selectClip(1);
      viewModel.rippleDeleteSelectedClip();
      viewModel.undo();
      viewModel.redo();

      expect(viewModel.videoClips.length, 2);
      expect(viewModel.videoClips[0].id, 'A');
      expect(viewModel.videoClips[1].id, 'C');
      expect(viewModel.getClipStartTime(1), 4.0);
      expect(viewModel.totalDurationInSeconds, 8.0);
    });

    // 27. Draft persistence
    test('27. Draft persistence saves and reloads timeline state after ripple delete with full fidelity', () {
      final clip1 = createTestClip(id: 'draft_c1', assetId: 'asset_d1', title: 'Draft 1', duration: const Duration(seconds: 5));
      final clip2 = createTestClip(id: 'draft_c2', assetId: 'asset_d2', title: 'Draft 2', duration: const Duration(seconds: 5));
      final clip3 = createTestClip(id: 'draft_c3', assetId: 'asset_d3', title: 'Draft 3', duration: const Duration(seconds: 5));

      viewModel.addVideoClip(clip1);
      viewModel.addVideoClip(clip2);
      viewModel.addVideoClip(clip3);

      viewModel.selectClip(1); // Delete middle clip
      viewModel.rippleDeleteSelectedClip();

      final project = viewModel.currentProject;
      expect(project.videoClips.length, 2);

      final newVm = EditorViewModel();
      newVm.loadProject(project);

      expect(newVm.videoClips.length, 2);
      expect(newVm.videoClips[0].id, 'draft_c1');
      expect(newVm.videoClips[1].id, 'draft_c3');
      expect(newVm.videoClips[0].durationInSeconds, 5.0);
      expect(newVm.videoClips[1].durationInSeconds, 5.0);
      expect(newVm.getClipStartTime(1), 5.0);
      expect(newVm.totalDurationInSeconds, 10.0);

      newVm.dispose();
    });

    // 28. Playback after delete
    test('28. Playback after delete safely handles state without crash or infinite loops', () {
      viewModel.addVideoClip(createTestClip(id: 'p1', assetId: 'ap1', title: 'P1', duration: const Duration(seconds: 6)));
      viewModel.seekTo(2.0);
      viewModel.play();
      expect(viewModel.isPlaying, isTrue);

      viewModel.selectClip(0);
      viewModel.deleteSelectedClip();

      // Timeline is empty -> paused safely
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.videoClips, isEmpty);
    });

    // 29. Extracted audio regression
    test('29. Extracted audio regression: ripple deleting main video segment preserves extracted audio track position', () {
      // Main video: A (0-5), B (5-10)
      viewModel.addVideoClip(createTestClip(id: 'vA', assetId: 'va', title: 'VA', duration: const Duration(seconds: 5)));
      viewModel.addVideoClip(createTestClip(id: 'vB', assetId: 'vb', title: 'VB', duration: const Duration(seconds: 5)));

      // Extracted audio aligned at 5.0s
      const extractedTrack = AudioTrack(
        id: 'extracted_at_5',
        assetId: 'asset_ext_wav',
        title: 'Extracted Audio',
        artist: 'Extracted Audio',
        duration: Duration(seconds: 5),
        startTime: Duration(seconds: 5),
      );
      viewModel.addAudioTrack(extractedTrack);

      // Ripple delete vA (0-5s)
      viewModel.selectClip(0);
      viewModel.rippleDeleteSelectedClip();

      // Main video now has vB at 0.0s (5s duration)
      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips.first.id, 'vB');
      expect(viewModel.getClipStartTime(0), 0.0);

      // Extracted audio retained its global start time at 5.0s (Phase 5 rule)
      expect(viewModel.audioTracks.length, 1);
      expect(viewModel.audioTracks.first.startTimeInSeconds, 5.0);
    });

    // 30. Multiple audio tracks remain independent
    test('30. Multiple audio tracks: deleting one leaves others completely unaffected', () {
      const track1 = AudioTrack(id: 't1', assetId: 'a1', title: 'T1', artist: 'Art', duration: Duration(seconds: 10), startTime: Duration.zero);
      const track2 = AudioTrack(id: 't2', assetId: 'a2', title: 'T2', artist: 'Art', duration: Duration(seconds: 10), startTime: Duration(seconds: 5));
      const track3 = AudioTrack(id: 't3', assetId: 'a3', title: 'T3', artist: 'Art', duration: Duration(seconds: 10), startTime: Duration(seconds: 10));

      viewModel.addAudioTrack(track1);
      viewModel.addAudioTrack(track2);
      viewModel.addAudioTrack(track3);

      expect(viewModel.audioTracks.length, 3);

      viewModel.removeAudioTrack('t2');

      expect(viewModel.audioTracks.length, 2);
      expect(viewModel.audioTracks.any((t) => t.id == 't2'), isFalse);
      expect(viewModel.audioTracks[0].id, 't1');
      expect(viewModel.audioTracks[1].id, 't3');
      expect(viewModel.audioTracks[1].startTimeInSeconds, 10.0);
    });
  });
}
