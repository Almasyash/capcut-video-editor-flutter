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
    viewModel.clearTextOverlays();
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('CapCut-like Split / Cut Engine Tests', () {
    // -------------------------------------------------------------
    // SECTION 1: VIDEO CLIP SPLIT
    // -------------------------------------------------------------
    test('1. Video Split (1.0x Speed): Splits into Part 1 and Part 2 with exact duration conservation', () {
      final asset = MediaAsset(
        id: 'asset_vid_1',
        type: MediaAssetType.video,
        name: 'sample_video.mp4',
        duration: const Duration(seconds: 10),
        localPath: '/data/sample_video.mp4',
        createdAt: DateTime.now(),
      );
      viewModel.addMediaAsset(asset);

      const clip = VideoClip(
        id: 'clip_1',
        assetId: 'asset_vid_1',
        title: 'Original Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        speed: 1.0,
        volume: 0.9,
        rotationDegrees: 90,
        opacity: 0.8,
        previewGradient: [Colors.black, Colors.white],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      // Playhead at 4.0s
      viewModel.seekTo(4.0);
      final splitResult = viewModel.splitClipAtPlayhead();

      expect(splitResult, isTrue);
      expect(viewModel.videoClips.length, equals(2));

      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      // Part A checks
      expect(partA.assetId, equals('asset_vid_1'));
      expect(partA.title, contains('Part 1'));
      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd, equals(const Duration(seconds: 4)));
      expect(partA.durationInSeconds, equals(4.0));
      expect(partA.speed, equals(1.0));
      expect(partA.volume, equals(0.9));
      expect(partA.rotationDegrees, equals(90));
      expect(partA.opacity, equals(0.8));

      // Part B checks
      expect(partB.assetId, equals('asset_vid_1'));
      expect(partB.title, contains('Part 2'));
      expect(partB.trimStart, equals(const Duration(seconds: 4)));
      expect(partB.trimEnd, equals(const Duration(seconds: 10)));
      expect(partB.durationInSeconds, equals(6.0));
      expect(partB.speed, equals(1.0));
      expect(partB.volume, equals(0.9));
      expect(partB.rotationDegrees, equals(90));
      expect(partB.opacity, equals(0.8));

      // Selection & Duration invariants
      expect(viewModel.selectedClipIndex, equals(1)); // Right segment selected
      expect(partA.durationInSeconds + partB.durationInSeconds, equals(10.0));
      expect(viewModel.mediaLibrary.length, equals(1)); // No duplicate MediaAsset created
    });

    test('2. Video Split (2.0x Fast Speed): Correctly scales source offsets', () {
      const clip = VideoClip(
        id: 'clip_fast',
        assetId: 'asset_vid_fast',
        title: 'Fast Motion Clip',
        originalDuration: Duration(seconds: 20),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 20),
        speed: 2.0, // Active duration is 10.0s
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);
      expect(viewModel.videoClips[0].durationInSeconds, equals(10.0));

      // Playhead at 3.0s (3.0s * 2.0x speed = 6.0s in source)
      viewModel.seekTo(3.0);
      final splitResult = viewModel.splitClipAtPlayhead();

      expect(splitResult, isTrue);
      expect(viewModel.videoClips.length, equals(2));

      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd, equals(const Duration(seconds: 6)));
      expect(partA.durationInSeconds, equals(3.0));

      expect(partB.trimStart, equals(const Duration(seconds: 6)));
      expect(partB.trimEnd, equals(const Duration(seconds: 20)));
      expect(partB.durationInSeconds, equals(7.0));

      expect(partA.durationInSeconds + partB.durationInSeconds, equals(10.0));
    });

    test('3. Video Split (0.5x Slow Speed): Correctly scales source offsets', () {
      const clip = VideoClip(
        id: 'clip_slow',
        assetId: 'asset_vid_slow',
        title: 'Slow Motion Clip',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        speed: 0.5, // Active duration is 8.0s
        previewGradient: [Colors.orange, Colors.red],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);
      expect(viewModel.videoClips[0].durationInSeconds, equals(8.0));

      // Playhead at 5.0s (5.0s * 0.5x speed = 2.5s in source)
      viewModel.seekTo(5.0);
      final splitResult = viewModel.splitClipAtPlayhead();

      expect(splitResult, isTrue);
      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd.inMilliseconds, equals(2500));
      expect(partA.durationInSeconds, equals(5.0));

      expect(partB.trimStart.inMilliseconds, equals(2500));
      expect(partB.trimEnd, equals(const Duration(seconds: 4)));
      expect(partB.durationInSeconds, equals(3.0));

      expect(partA.durationInSeconds + partB.durationInSeconds, equals(8.0));
    });

    test('4. Video Split with Pre-existing Trim Offsets: Accurately preserves trims', () {
      const clip = VideoClip(
        id: 'clip_pretrimmed',
        assetId: 'asset_vid_trim',
        title: 'Pretrimmed Clip',
        originalDuration: Duration(seconds: 30),
        trimStart: Duration(seconds: 5),
        trimEnd: Duration(seconds: 25),
        speed: 1.0, // Active duration is 20.0s
        previewGradient: [Colors.green, Colors.teal],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      // Playhead at 8.0s (8.0s into clip => source offset is 5s + 8s = 13s)
      viewModel.seekTo(8.0);
      final splitResult = viewModel.splitClipAtPlayhead();

      expect(splitResult, isTrue);
      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      expect(partA.trimStart, equals(const Duration(seconds: 5)));
      expect(partA.trimEnd, equals(const Duration(seconds: 13)));
      expect(partA.durationInSeconds, equals(8.0));

      expect(partB.trimStart, equals(const Duration(seconds: 13)));
      expect(partB.trimEnd, equals(const Duration(seconds: 25)));
      expect(partB.durationInSeconds, equals(12.0));

      expect(partA.durationInSeconds + partB.durationInSeconds, equals(20.0));
    });

    test('5. Video Split Boundary Rejection: Rejects splits too close to boundary or outside', () {
      const clip = VideoClip(
        id: 'clip_bound',
        assetId: 'asset_vid_bound',
        title: 'Boundary Test Clip',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        speed: 1.0,
        previewGradient: [Colors.grey, Colors.black],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      // 1. Playhead at start boundary (0.02s < 0.05s)
      viewModel.seekTo(0.02);
      expect(viewModel.splitClipAtPlayhead(), isFalse);
      expect(viewModel.videoClips.length, equals(1));

      // 2. Playhead at end boundary (4.98s > 5.0 - 0.05s)
      viewModel.seekTo(4.98);
      expect(viewModel.splitClipAtPlayhead(), isFalse);
      expect(viewModel.videoClips.length, equals(1));

      // 3. Playhead completely outside (6.0s)
      viewModel.seekTo(6.0);
      expect(viewModel.splitClipAtPlayhead(), isFalse);
      expect(viewModel.videoClips.length, equals(1));
    });

    test('6. Video Repeated / Multi-Split: Splits clip into 3 consecutive parts', () {
      const clip = VideoClip(
        id: 'clip_multi',
        assetId: 'asset_vid_multi',
        title: 'Multi Split Clip',
        originalDuration: Duration(seconds: 15),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 15),
        speed: 1.0,
        previewGradient: [Colors.amber, Colors.orange],
      );
      viewModel.addVideoClip(clip);

      // Split 1 at 5.0s
      viewModel.seekTo(5.0);
      expect(viewModel.splitClipAtPlayhead(), isTrue);
      expect(viewModel.videoClips.length, equals(2));
      expect(viewModel.selectedClipIndex, equals(1)); // Part B (5s to 15s) selected

      // Split 2 at 10.0s (inside Part B)
      viewModel.seekTo(10.0);
      expect(viewModel.splitClipAtPlayhead(), isTrue);
      expect(viewModel.videoClips.length, equals(3));
      expect(viewModel.selectedClipIndex, equals(2)); // Part C (10s to 15s) selected

      final p1 = viewModel.videoClips[0];
      final p2 = viewModel.videoClips[1];
      final p3 = viewModel.videoClips[2];

      expect(p1.durationInSeconds, equals(5.0));
      expect(p2.durationInSeconds, equals(5.0));
      expect(p3.durationInSeconds, equals(5.0));
      expect(p1.durationInSeconds + p2.durationInSeconds + p3.durationInSeconds, equals(15.0));
    });

    // -------------------------------------------------------------
    // SECTION 2: AUDIO TRACK SPLIT
    // -------------------------------------------------------------
    test('7. Audio Split (1.0x Speed): Splits into Part 1 and Part 2 sharing assetId', () {
      const track = AudioTrack(
        id: 'audio_track_1',
        assetId: 'asset_audio_1',
        title: 'Background_Music.mp3',
        artist: 'Artist A',
        duration: Duration(seconds: 60),
        startTime: Duration(seconds: 5), // Starts at 5.0s on timeline
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 60),
        speed: 1.0,
        volume: 0.75,
        waveformPoints: [0.2, 0.4, 0.6, 0.8],
      );
      viewModel.addAudioTrack(track);
      viewModel.selectAudioTrack('audio_track_1');

      // Playhead at 20.0s (15.0s into the track)
      viewModel.seekTo(20.0);
      final splitResult = viewModel.splitAudioAtPlayhead();

      expect(splitResult, isTrue);
      expect(viewModel.audioTracks.length, equals(2));

      final partA = viewModel.audioTracks[0];
      final partB = viewModel.audioTracks[1];

      // Part A checks
      expect(partA.assetId, equals('asset_audio_1'));
      expect(partA.title, contains('Part 1'));
      expect(partA.artist, equals('Artist A'));
      expect(partA.startTimeInSeconds, equals(5.0));
      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd, equals(const Duration(seconds: 15)));
      expect(partA.durationInSeconds, equals(15.0));
      expect(partA.volume, equals(0.75));
      expect(partA.waveformPoints, equals([0.2, 0.4, 0.6, 0.8]));

      // Part B checks
      expect(partB.assetId, equals('asset_audio_1'));
      expect(partB.title, contains('Part 2'));
      expect(partB.artist, equals('Artist A'));
      expect(partB.startTimeInSeconds, equals(20.0));
      expect(partB.trimStart, equals(const Duration(seconds: 15)));
      expect(partB.trimEnd, equals(const Duration(seconds: 60)));
      expect(partB.durationInSeconds, equals(45.0));
      expect(partB.volume, equals(0.75));

      // Right segment selected
      expect(viewModel.selectedAudioTrackId, equals(partB.id));
      expect(viewModel.isAudioSelected, isTrue);
      expect(partA.durationInSeconds + partB.durationInSeconds, equals(60.0));
    });

    test('8. Audio Split (1.5x Speed): Correctly scales source offsets', () {
      const track = AudioTrack(
        id: 'audio_fast',
        assetId: 'asset_audio_fast',
        title: 'Fast_Audio.mp3',
        duration: Duration(seconds: 30),
        startTime: Duration.zero,
        speed: 1.5, // Effective duration is 20.0s
      );
      viewModel.addAudioTrack(track);
      viewModel.selectAudioTrack('audio_fast');
      expect(viewModel.audioTracks[0].durationInSeconds, equals(20.0));

      // Playhead at 6.0s (6.0s * 1.5 = 9.0s in source)
      viewModel.seekTo(6.0);
      final splitResult = viewModel.splitAudioAtPlayhead();

      expect(splitResult, isTrue);
      final partA = viewModel.audioTracks[0];
      final partB = viewModel.audioTracks[1];

      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd, equals(const Duration(seconds: 9)));
      expect(partA.durationInSeconds, equals(6.0));

      expect(partB.startTimeInSeconds, equals(6.0));
      expect(partB.trimStart, equals(const Duration(seconds: 9)));
      expect(partB.trimEnd, equals(const Duration(seconds: 30)));
      expect(partB.durationInSeconds, equals(14.0));

      expect(partA.durationInSeconds + partB.durationInSeconds, equals(20.0));
    });

    test('9. Audio Split with Pre-existing Trims: Maintains source alignment', () {
      const track = AudioTrack(
        id: 'audio_pretrim',
        assetId: 'asset_audio_trim',
        title: 'Pretrimmed_Audio.mp3',
        duration: Duration(seconds: 40),
        startTime: Duration(seconds: 2),
        trimStart: Duration(seconds: 10),
        trimEnd: Duration(seconds: 30), // 20.0s effective
        speed: 1.0,
      );
      viewModel.addAudioTrack(track);
      viewModel.selectAudioTrack('audio_pretrim');

      // Playhead at 7.0s (5.0s into track => source is 10s + 5s = 15s)
      viewModel.seekTo(7.0);
      final splitResult = viewModel.splitAudioAtPlayhead();

      expect(splitResult, isTrue);
      final partA = viewModel.audioTracks[0];
      final partB = viewModel.audioTracks[1];

      expect(partA.startTimeInSeconds, equals(2.0));
      expect(partA.trimStart, equals(const Duration(seconds: 10)));
      expect(partA.trimEnd, equals(const Duration(seconds: 15)));
      expect(partA.durationInSeconds, equals(5.0));

      expect(partB.startTimeInSeconds, equals(7.0));
      expect(partB.trimStart, equals(const Duration(seconds: 15)));
      expect(partB.trimEnd, equals(const Duration(seconds: 30)));
      expect(partB.durationInSeconds, equals(15.0));

      expect(partA.durationInSeconds + partB.durationInSeconds, equals(20.0));
    });

    // -------------------------------------------------------------
    // SECTION 3: EXTRACTED AUDIO TRACK SPLIT
    // -------------------------------------------------------------
    test('10. Extracted Audio Split: Splits independent extracted audio track without affecting video clip or unmuting', () {
      // 1. Setup video clip (muted because audio was extracted)
      const videoClip = VideoClip(
        id: 'clip_with_extracted_audio',
        assetId: 'asset_video_orig',
        title: 'Interview_Video.mp4',
        originalDuration: Duration(seconds: 20),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 20),
        volume: 0.0, // Muted after extraction
        previewGradient: [Colors.indigo, Colors.blue],
      );
      viewModel.addVideoClip(videoClip);

      // 2. Setup extracted audio track
      const extractedTrack = AudioTrack(
        id: 'audio_extracted_from_video',
        assetId: 'asset_extracted_audio_1',
        title: 'Interview_Video_Audio.aac',
        artist: 'Extracted Audio',
        duration: Duration(seconds: 20),
        startTime: Duration.zero,
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 20),
        volume: 1.0,
      );
      viewModel.addAudioTrack(extractedTrack);
      viewModel.selectAudioTrack('audio_extracted_from_video');

      // 3. Split extracted audio at 8.0s
      viewModel.seekTo(8.0);
      final splitSuccess = viewModel.splitAudioAtPlayhead();

      expect(splitSuccess, isTrue);
      expect(viewModel.audioTracks.length, equals(2));
      expect(viewModel.videoClips.length, equals(1)); // Video clip is untouched!
      expect(viewModel.videoClips[0].volume, equals(0.0)); // Video clip remains muted!

      final partA = viewModel.audioTracks[0];
      final partB = viewModel.audioTracks[1];

      expect(partA.assetId, equals('asset_extracted_audio_1'));
      expect(partA.durationInSeconds, equals(8.0));
      expect(partB.assetId, equals('asset_extracted_audio_1'));
      expect(partB.startTimeInSeconds, equals(8.0));
      expect(partB.durationInSeconds, equals(12.0));
    });

    // -------------------------------------------------------------
    // SECTION 4: TEXT OVERLAY & PIP OVERLAY SPLIT
    // -------------------------------------------------------------
    test('11. Text Overlay Split: Splits text into two contiguous segments', () {
      const text = TextOverlay(
        id: 'text_overlay_1',
        text: 'Title Text Layer',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 10),
      );
      viewModel.addTextOverlay(text);
      viewModel.selectTextOverlay('text_overlay_1');

      // Playhead at 6.0s (4.0s into text)
      viewModel.seekTo(6.0);
      final splitResult = viewModel.splitTextAtPlayhead();

      expect(splitResult, isTrue);
      expect(viewModel.textOverlays.length, equals(2));

      final partA = viewModel.textOverlays[0];
      final partB = viewModel.textOverlays[1];

      expect(partA.startTimeInSeconds, equals(2.0));
      expect(partA.durationInSeconds, equals(4.0));
      expect(partB.startTimeInSeconds, equals(6.0));
      expect(partB.durationInSeconds, equals(6.0));
      expect(viewModel.selectedTextId, equals(partB.id));
    });

    test('12. PIP / Overlay Clip Split: Splits PIP layer into two contiguous segments', () {
      const overlay = OverlayClip(
        id: 'overlay_pip_1',
        title: 'Reaction Camera PIP',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 8),
      );
      viewModel.addOverlayClip(overlay);
      expect(viewModel.selectedOverlayIndex, equals(0));

      // Playhead at 4.0s (3.0s into overlay)
      viewModel.seekTo(4.0);
      final splitResult = viewModel.splitOverlayAtPlayhead();

      expect(splitResult, isTrue);
      expect(viewModel.overlayClips.length, equals(2));

      final partA = viewModel.overlayClips[0];
      final partB = viewModel.overlayClips[1];

      expect(partA.startTimeInSeconds, equals(1.0));
      expect(partA.durationInSeconds, equals(3.0));
      expect(partB.startTimeInSeconds, equals(4.0));
      expect(partB.durationInSeconds, equals(5.0));
      expect(viewModel.selectedOverlayIndex, equals(1));
    });

    // -------------------------------------------------------------
    // SECTION 5: UNDO / REDO RESTORATION
    // -------------------------------------------------------------
    test('13. Undo Split: Restores original clip exactly upon undo', () {
      const clip = VideoClip(
        id: 'clip_undo_test',
        assetId: 'asset_undo',
        title: 'Original Undo Clip',
        originalDuration: Duration(seconds: 12),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 12),
        speed: 1.0,
        previewGradient: [Colors.deepOrange, Colors.amber],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      viewModel.seekTo(5.0);
      expect(viewModel.splitClipAtPlayhead(), isTrue);
      expect(viewModel.videoClips.length, equals(2));

      // Undo the split
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();

      expect(viewModel.videoClips.length, equals(1));
      expect(viewModel.videoClips[0].id, equals('clip_undo_test'));
      expect(viewModel.videoClips[0].durationInSeconds, equals(12.0));
    });

    // -------------------------------------------------------------
    // SECTION 6: DRAFT STATE RESTORATION
    // -------------------------------------------------------------
    test('14. Draft State: Split clips load into new ViewModel with full fidelity', () {
      const clip = VideoClip(
        id: 'clip_draft_source',
        assetId: 'asset_draft_media',
        title: 'Draft Clip',
        originalDuration: Duration(seconds: 16),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 16),
        speed: 1.0,
        previewGradient: [Colors.cyan, Colors.blue],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      viewModel.seekTo(7.0);
      expect(viewModel.splitClipAtPlayhead(), isTrue);

      final project = viewModel.currentProject;
      expect(project.videoClips.length, equals(2));

      // Create new ViewModel and load project
      final newVm = EditorViewModel();
      newVm.loadProject(project);

      expect(newVm.videoClips.length, equals(2));
      expect(newVm.videoClips[0].durationInSeconds, equals(7.0));
      expect(newVm.videoClips[1].durationInSeconds, equals(9.0));
      expect(newVm.videoClips[0].assetId, equals('asset_draft_media'));
      expect(newVm.videoClips[1].assetId, equals('asset_draft_media'));

      newVm.dispose();
    });
  });
}
