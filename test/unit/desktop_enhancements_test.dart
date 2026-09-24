import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
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

  group('Desktop Features - Clipboard & Operations', () {
    test('Copy, Cut and Paste Video Clip at playhead', () {
      final asset = MediaAsset(
        id: 'asset_1',
        type: MediaAssetType.video,
        name: 'test_clip.mp4',
        duration: const Duration(seconds: 8),
        createdAt: DateTime.now(),
      );
      viewModel.addMediaAsset(asset);

      const clip = VideoClip(
        id: 'clip_1',
        assetId: 'asset_1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 8),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      expect(viewModel.canPaste, isFalse);

      // Copy
      final copySuccess = viewModel.copySelected();
      expect(copySuccess, isTrue);
      expect(viewModel.canPaste, isTrue);
      expect(viewModel.clipboardItem, isA<VideoClip>());

      // Paste at playhead 3.0s
      viewModel.seekTo(3.0);
      final pasteSuccess = viewModel.pasteAtPlayhead();
      expect(pasteSuccess, isTrue);
      expect(viewModel.videoClips.length, equals(2));
      expect(viewModel.videoClips[1].title, contains('(Copy)'));

      // Cut
      viewModel.selectClip(1);
      final cutSuccess = viewModel.cutSelected();
      expect(cutSuccess, isTrue);
      expect(viewModel.videoClips.length, equals(1));
      expect(viewModel.canPaste, isTrue);
    });

    test('Duplicate selected item', () {
      const clip1 = VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Main Clip',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip1);
      viewModel.selectClip(0);

      final dupSuccess = viewModel.duplicateSelectedItem();
      expect(dupSuccess, isTrue);
      expect(viewModel.videoClips.length, equals(2));
      expect(viewModel.videoClips[1].id, isNot(equals('c1')));
      expect(viewModel.videoClips[1].title, contains('(Copy)'));
    });

    test('Copy and Paste Text Overlay at playhead', () {
      const clip = VideoClip(
        id: 'bg_clip',
        assetId: 'a1',
        title: 'Background',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);

      const text = TextOverlay(
        id: 'txt_1',
        text: 'Title Text',
        textColor: Colors.white,
        fontSize: 24,
        position: Offset(100, 100),
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
      );
      viewModel.addTextOverlay(text);
      viewModel.selectTextOverlay('txt_1');

      final copySuccess = viewModel.copySelected();
      expect(copySuccess, isTrue);
      expect(viewModel.canPaste, isTrue);

      // Paste at playhead 6.0s
      viewModel.seekTo(6.0);
      final pasteSuccess = viewModel.pasteAtPlayhead();
      expect(pasteSuccess, isTrue);
      expect(viewModel.textOverlays.length, equals(2));

      final pastedText = viewModel.textOverlays.firstWhere((t) => t.id != 'txt_1');
      expect(pastedText.startTime.inMilliseconds, equals(6000));
      expect(pastedText.duration.inMilliseconds, equals(4000));
    });

    test('Add video clip from MediaAsset directly (Desktop Assets Library)', () {
      final asset = MediaAsset(
        id: 'desktop_asset_1',
        type: MediaAssetType.video,
        name: 'desktop_import.mp4',
        duration: const Duration(seconds: 12),
        localPath: 'C:\\Videos\\desktop_import.mp4',
        createdAt: DateTime.now(),
      );

      viewModel.addVideoClipFromAsset(asset);
      expect(viewModel.videoClips.length, equals(1));
      expect(viewModel.videoClips.first.assetId, equals('desktop_asset_1'));
      expect(viewModel.videoClips.first.title, equals('desktop_import.mp4'));
      expect(viewModel.videoClips.first.durationInSeconds, equals(12.0));
      expect(viewModel.mediaLibrary.any((a) => a.id == 'desktop_asset_1'), isTrue);
    });
  });

  group('Desktop Features - Directional Boundary Navigation (Arrow Keys)', () {
    test('seekToNextBoundary and seekToPreviousBoundary jump to cuts and element boundaries', () {
      const clip1 = VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        previewGradient: [Colors.blue, Colors.purple],
      );
      const clip2 = VideoClip(
        id: 'c2',
        assetId: 'a2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.orange, Colors.red],
      );
      viewModel.addVideoClip(clip1);
      viewModel.addVideoClip(clip2);

      const text = TextOverlay(
        id: 't1',
        text: 'Banner',
        fontSize: 20,
        position: Offset(50, 50),
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 3), // ends at 5.0s
      );
      viewModel.addTextOverlay(text);

      final boundaries = viewModel.getAllTimelineBoundaries();
      expect(boundaries, containsAllInOrder([0.0, 2.0, 4.0, 5.0, 9.0]));

      // Start at 0.0s -> Seek next -> 2.0s
      viewModel.seekTo(0.0);
      viewModel.seekToNextBoundary();
      expect(viewModel.playheadPosition, closeTo(2.0, 0.001));

      // At 2.0s -> Seek next -> 4.0s (Cut between Clip 1 and Clip 2)
      viewModel.seekToNextBoundary();
      expect(viewModel.playheadPosition, closeTo(4.0, 0.001));

      // At 4.0s -> Seek next -> 5.0s (Text overlay end)
      viewModel.seekToNextBoundary();
      expect(viewModel.playheadPosition, closeTo(5.0, 0.001));

      // At 5.0s -> Seek next -> 9.0s (End of timeline)
      viewModel.seekToNextBoundary();
      expect(viewModel.playheadPosition, closeTo(9.0, 0.001));

      // At 9.0s -> Seek next -> stays at 9.0s
      viewModel.seekToNextBoundary();
      expect(viewModel.playheadPosition, closeTo(9.0, 0.001));

      // Now reverse navigation:
      // At 9.0s -> Seek previous -> 5.0s
      viewModel.seekToPreviousBoundary();
      expect(viewModel.playheadPosition, closeTo(5.0, 0.001));

      // At 5.0s -> Seek previous -> 4.0s
      viewModel.seekToPreviousBoundary();
      expect(viewModel.playheadPosition, closeTo(4.0, 0.001));

      // At 4.0s -> Seek previous -> 2.0s
      viewModel.seekToPreviousBoundary();
      expect(viewModel.playheadPosition, closeTo(2.0, 0.001));

      // At 2.0s -> Seek previous -> 0.0s
      viewModel.seekToPreviousBoundary();
      expect(viewModel.playheadPosition, closeTo(0.0, 0.001));

      // At 0.0s -> Seek previous -> stays at 0.0s
      viewModel.seekToPreviousBoundary();
      expect(viewModel.playheadPosition, closeTo(0.0, 0.001));
    });

    test('Boundary seeking automatically pauses playback if playing', () {
      const clip = VideoClip(
        id: 'c_pause',
        assetId: 'a1',
        title: 'Pause Test',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);

      viewModel.seekTo(1.0);
      viewModel.play();
      expect(viewModel.isPlaying, isTrue);

      // Seeking next boundary pauses playback
      viewModel.seekToNextBoundary();
      expect(viewModel.isPlaying, isFalse);

      viewModel.play();
      expect(viewModel.isPlaying, isTrue);

      // Seeking previous boundary pauses playback
      viewModel.seekToPreviousBoundary();
      expect(viewModel.isPlaying, isFalse);
    });

    test('Speed adjustment supports high speeds up to 100x and speed curves', () {
      const clip = VideoClip(
        id: 'c_speed',
        assetId: 'a1',
        title: 'Speed Test',
        originalDuration: Duration(seconds: 100),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 100),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      // 10x Speed
      viewModel.setClipSpeed(10.0);
      expect(viewModel.selectedClip!.speed, equals(10.0));
      expect(viewModel.selectedClip!.durationInSeconds, equals(10.0));

      // 50x Speed
      viewModel.setClipSpeed(50.0);
      expect(viewModel.selectedClip!.speed, equals(50.0));
      expect(viewModel.selectedClip!.durationInSeconds, equals(2.0));

      // 100x Speed
      viewModel.setClipSpeed(100.0);
      expect(viewModel.selectedClip!.speed, equals(100.0));
      expect(viewModel.selectedClip!.durationInSeconds, equals(1.0));

      // Speed Curve Montage preset
      final montageCurve = SpeedCurve.montage();
      viewModel.setClipSpeedCurve(montageCurve);
      expect(viewModel.selectedClip!.speedCurve, isNotNull);
      expect(viewModel.selectedClip!.speedCurve!.type, equals(SpeedCurvePresetType.montage));
      expect(viewModel.selectedClip!.speedCurve!.points.length, greaterThanOrEqualTo(4));

      // Evaluate curve at various progress ratios
      final speedStart = montageCurve.evaluateSpeedAt(0.0);
      final speedMiddle = montageCurve.evaluateSpeedAt(0.5);
      final speedEnd = montageCurve.evaluateSpeedAt(1.0);
      expect(speedStart, isPositive);
      expect(speedMiddle, isPositive);
      expect(speedEnd, isPositive);
    });

    test('Keyframe animation system allows adding, toggling, and interpolation', () {
      const clip = VideoClip(
        id: 'c_kf',
        assetId: 'a1',
        title: 'Keyframe Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      // Initially no keyframes
      expect(viewModel.hasKeyframeAtPlayhead, isFalse);

      // Add keyframe at 0s
      viewModel.seekTo(0.0);
      viewModel.toggleKeyframeAtPlayhead();
      expect(viewModel.hasKeyframeAtPlayhead, isTrue);
      expect(viewModel.selectedClip!.keyframes.length, equals(1));

      // Add second keyframe at 4s
      viewModel.seekTo(4.0);
      viewModel.addKeyframeAtPlayhead();
      expect(viewModel.selectedClip!.keyframes.length, equals(2));

      // Interpolate keyframe at 2s (halfway)
      final kfMid = viewModel.getInterpolatedKeyframe(viewModel.selectedClip!, 2.0);
      expect(kfMid, isNotNull);
      expect(kfMid!.scale, equals(1.0));

      // Remove keyframe at 4s
      viewModel.seekTo(4.0);
      viewModel.removeKeyframeAtPlayhead();
      expect(viewModel.hasKeyframeAtPlayhead, isFalse);
      expect(viewModel.selectedClip!.keyframes.length, equals(1));
    });

    test('Masking can be applied, updated, and removed on selected clip', () {
      const clip = VideoClip(
        id: 'c_mask',
        assetId: 'a1',
        title: 'Mask Clip',
        originalDuration: Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 8),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      expect(viewModel.selectedClip!.mask, isNull);

      // Apply circle mask
      const circleMask = VideoMask(type: MaskType.circle, size: 0.8, feather: 0.2);
      viewModel.setClipMask(circleMask);
      expect(viewModel.selectedClip!.mask, isNotNull);
      expect(viewModel.selectedClip!.mask!.type, equals(MaskType.circle));

      // Remove mask
      viewModel.removeClipMask();
      expect(viewModel.selectedClip!.mask, isNull);
    });

    test('Blending mode can be set on selected clip', () {
      const clip = VideoClip(
        id: 'c_blend',
        assetId: 'a1',
        title: 'Blend Clip',
        originalDuration: Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 8),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);

      expect(viewModel.selectedClip!.blendMode, equals(BlendMode.srcOver));

      // Set Screen blend mode
      viewModel.setClipBlendMode(BlendMode.screen);
      expect(viewModel.selectedClip!.blendMode, equals(BlendMode.screen));
    });

    test('Voice recording lifecycle: start recording and stop creates valid track', () async {
      const clip = VideoClip(
        id: 'c_bg',
        assetId: 'a1',
        title: 'Background',
        originalDuration: Duration(seconds: 15),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 15),
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel.addVideoClip(clip);

      expect(viewModel.isRecordingVoice, isFalse);
      expect(viewModel.audioTracks.length, equals(0));

      // Start recording
      viewModel.startVoiceRecording();
      expect(viewModel.isRecordingVoice, isTrue);

      // Stop recording
      await viewModel.stopVoiceRecording();
      expect(viewModel.isRecordingVoice, isFalse);
      expect(viewModel.audioTracks.length, equals(1));
      expect(viewModel.audioTracks.first.title, contains('Voiceover'));
    });
  });
}
