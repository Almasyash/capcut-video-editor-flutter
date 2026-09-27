import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OverlayClip Model Tests', () {
    test('Calculates endTime and duration getters accurately', () {
      const clip = OverlayClip(
        id: 'overlay_1',
        title: 'Test PIP',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 0.8,
        opacity: 0.9,
      );

      expect(clip.startTimeInSeconds, 2.0);
      expect(clip.durationInSeconds, 5.0);
      expect(clip.endTimeInSeconds, 7.0);
      expect(clip.endTimeMs, 7000);
      expect(clip.endTime, const Duration(seconds: 7));
    });

    test('Sanitizes position, scale, opacity, and rotation within valid ranges', () {
      expect(OverlayClip.sanitizePosition(const Offset(-0.8, 1.8)), const Offset(-0.5, 1.5));
      expect(OverlayClip.sanitizeScale(0.02), 0.05);
      expect(OverlayClip.sanitizeScale(6.0), 5.0);
      expect(OverlayClip.sanitizeOpacity(-0.5), 0.0);
      expect(OverlayClip.sanitizeOpacity(1.5), 1.0);
      expect(OverlayClip.sanitizeRotation(10.0), isNotNull);
    });

    test('Serializes to and from JSON accurately preserving all PIP properties', () {
      const clip = OverlayClip(
        id: 'overlay_test_json',
        title: 'Sample Overlay',
        assetId: 'asset_123',
        localPath: '/storage/sample.png',
        thumbnailPath: '/storage/thumb.png',
        isPhoto: true,
        startTime: Duration(milliseconds: 1500),
        duration: Duration(milliseconds: 4000),
        position: Offset(0.3, 0.4),
        scale: 0.65,
        rotation: 0.25,
        opacity: 0.85,
        flipHorizontal: true,
        flipVertical: false,
      );

      final json = clip.toJson();
      final restored = OverlayClip.fromJson(json);

      expect(restored.id, clip.id);
      expect(restored.title, clip.title);
      expect(restored.assetId, clip.assetId);
      expect(restored.localPath, clip.localPath);
      expect(restored.thumbnailPath, clip.thumbnailPath);
      expect(restored.isPhoto, true);
      expect(restored.startTime, clip.startTime);
      expect(restored.duration, clip.duration);
      expect(restored.position.dx, closeTo(0.3, 0.001));
      expect(restored.position.dy, closeTo(0.4, 0.001));
      expect(restored.scale, closeTo(0.65, 0.001));
      expect(restored.rotation, closeTo(0.25, 0.001));
      expect(restored.opacity, closeTo(0.85, 0.001));
      expect(restored.flipHorizontal, true);
      expect(restored.flipVertical, false);
    });
  });

  group('EditorViewModel PIP Overlay Operations Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel(enableMockFallback: false);
    });

    test('addOverlayFromMediaAsset initializes centered overlay with correct timings', () {
      final asset = MediaAsset(
        id: 'asset_pip_test',
        name: 'My PIP Photo',
        type: MediaAssetType.photo,
        localPath: '/data/user/0/com.example/cache/test.png',
        thumbnailPath: '/data/user/0/com.example/cache/test_thumb.png',
        duration: const Duration(seconds: 4),
        createdAt: DateTime.now(),
      );

      viewModel.loadProject(Project(
        id: 'test_proj',
        name: 'Test Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        videoClips: const [
          VideoClip(
            id: 'clip_base',
            assetId: 'asset_base',
            title: 'Base Clip',
            originalDuration: Duration(seconds: 10),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 10),
            previewGradient: [Color(0xFF00C6FF), Color(0xFF0072FF)],
          ),
        ],
      ));

      viewModel.seekTo(1.5);
      viewModel.addOverlayFromMediaAsset(asset);

      expect(viewModel.overlayClips.length, 1);
      final added = viewModel.overlayClips.first;
      expect(added.title, 'My PIP Photo');
      expect(added.assetId, 'asset_pip_test');
      expect(added.startTimeInSeconds, closeTo(1.5, 0.05));
      expect(added.durationInSeconds, 4.0);
      expect(added.position, const Offset(0.5, 0.5));
      expect(viewModel.selectedOverlayIndex, 0);
      expect(viewModel.selectedOverlay?.id, added.id);
    });

    test('selectOverlay and selectOverlayById select and deselect properly', () {
      const clip1 = OverlayClip(
        id: 'ov_1',
        title: 'Layer 1',
        startTime: Duration.zero,
        duration: Duration(seconds: 3),
      );
      const clip2 = OverlayClip(
        id: 'ov_2',
        title: 'Layer 2',
        startTime: Duration(seconds: 3),
        duration: Duration(seconds: 3),
      );

      viewModel.addOverlayClip(clip1);
      viewModel.addOverlayClip(clip2);

      viewModel.selectOverlayById('ov_1');
      expect(viewModel.selectedOverlayIndex, 0);
      expect(viewModel.selectedOverlay?.id, 'ov_1');

      viewModel.selectOverlayById('ov_2');
      expect(viewModel.selectedOverlayIndex, 1);
      expect(viewModel.selectedOverlay?.id, 'ov_2');

      viewModel.selectOverlay(null);
      expect(viewModel.selectedOverlayIndex, isNull);
      expect(viewModel.selectedOverlay, isNull);
    });

    test('updateOverlayClipTiming trims and clamps minimum duration to 0.3s', () {
      const clip = OverlayClip(
        id: 'ov_trim_test',
        title: 'Trim PIP',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      // Valid trim
      viewModel.updateOverlayClipTiming(
        'ov_trim_test',
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      );
      expect(viewModel.overlayClips.first.startTimeInSeconds, 2.0);
      expect(viewModel.overlayClips.first.durationInSeconds, 3.0);

      // Sub-0.3s trim rejected by minimum duration clamp
      viewModel.updateOverlayClipTiming(
        'ov_trim_test',
        const Duration(seconds: 2),
        const Duration(milliseconds: 200),
      );
      // Duration stays at previous valid value
      expect(viewModel.overlayClips.first.durationInSeconds, 3.0);
    });

    test('commitOverlayTiming records exactly one undo snapshot upon gesture completion', () {
      const clip = OverlayClip(
        id: 'ov_undo_test',
        title: 'Undo PIP',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      final initialStart = viewModel.overlayClips.first.startTime;
      final initialDuration = viewModel.overlayClips.first.duration;

      // Simulate dragging right handle: multiple live updates occur during drag
      viewModel.updateOverlayClipTiming(
        'ov_undo_test',
        const Duration(seconds: 1),
        const Duration(seconds: 5),
        saveSnapshot: false,
        notify: false,
      );
      viewModel.updateOverlayClipTiming(
        'ov_undo_test',
        const Duration(seconds: 1),
        const Duration(seconds: 6),
        saveSnapshot: false,
        notify: false,
      );
      expect(viewModel.overlayClips.first.durationInSeconds, 6.0);

      // Finish drag commits single snapshot
      viewModel.commitOverlayTiming(
        'ov_undo_test',
        oldStart: initialStart,
        oldDuration: initialDuration,
      );

      // Now test undo: should revert completely to initial timing in ONE undo step
      expect(viewModel.canUndo, true);
      viewModel.undo();
      expect(viewModel.overlayClips.first.startTime, initialStart);
      expect(viewModel.overlayClips.first.duration, initialDuration);

      // Performing redo reapplies the committed timing
      viewModel.redo();
      expect(viewModel.overlayClips.first.startTime, const Duration(seconds: 1));
      expect(viewModel.overlayClips.first.duration, const Duration(seconds: 6));
    });

    test('updateOverlayTransform and commitOverlayTransform handle live gestures and single undo', () {
      const clip = OverlayClip(
        id: 'ov_trans_test',
        title: 'Transform PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 0.5,
        rotation: 0.0,
      );
      viewModel.addOverlayClip(clip);

      final oldPos = viewModel.overlayClips.first.position;
      final oldScale = viewModel.overlayClips.first.scale;
      final oldRot = viewModel.overlayClips.first.rotation;

      // Gesture updates live
      viewModel.updateOverlayTransform(
        'ov_trans_test',
        position: const Offset(0.7, 0.3),
        scale: 1.2,
        rotation: 0.5,
        notify: false,
      );
      expect(viewModel.overlayClips.first.position, const Offset(0.7, 0.3));
      expect(viewModel.overlayClips.first.scale, 1.2);

      // Gesture finish commits
      viewModel.commitOverlayTransform(
        'ov_trans_test',
        oldPosition: oldPos,
        oldScale: oldScale,
        oldRotation: oldRot,
      );

      viewModel.undo();
      expect(viewModel.overlayClips.first.position, oldPos);
      expect(viewModel.overlayClips.first.scale, oldScale);
      expect(viewModel.overlayClips.first.rotation, oldRot);
    });

    test('updateOverlayOpacity and commitOverlayOpacity update opacity with single undo', () {
      const clip = OverlayClip(
        id: 'ov_opacity_test',
        title: 'Opacity PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        opacity: 1.0,
      );
      viewModel.addOverlayClip(clip);

      const oldOpacity = 1.0;
      viewModel.updateOverlayOpacity('ov_opacity_test', 0.65, saveSnapshot: false);
      expect(viewModel.overlayClips.first.opacity, closeTo(0.65, 0.01));

      viewModel.commitOverlayOpacity('ov_opacity_test', oldOpacity: oldOpacity);

      viewModel.undo();
      expect(viewModel.overlayClips.first.opacity, 1.0);

      viewModel.redo();
      expect(viewModel.overlayClips.first.opacity, closeTo(0.65, 0.01));
    });

    test('toggleOverlayFlipHorizontal and toggleOverlayFlipVertical flip correctly', () {
      const clip = OverlayClip(
        id: 'ov_flip_test',
        title: 'Flip PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
      );
      viewModel.addOverlayClip(clip);

      expect(viewModel.overlayClips.first.flipHorizontal, false);
      viewModel.toggleOverlayFlipHorizontal('ov_flip_test');
      expect(viewModel.overlayClips.first.flipHorizontal, true);

      expect(viewModel.overlayClips.first.flipVertical, false);
      viewModel.toggleOverlayFlipVertical('ov_flip_test');
      expect(viewModel.overlayClips.first.flipVertical, true);
    });

    test('Project duration respects PIP overlays beyond video length', () {
      // Empty project has 0 duration
      expect(viewModel.totalDurationInSeconds, 0.0);

      // Add a 10s overlay
      viewModel.addOverlayClip(
        const OverlayClip(
          id: 'ov_dur_test',
          title: 'Long PIP',
          startTime: Duration(seconds: 2),
          duration: Duration(seconds: 8),
        ),
      );

      expect(viewModel.totalDurationInSeconds, 10.0);
    });

    test('updateOverlaySpeed updates speed and affects playback', () {
      const clip = OverlayClip(
        id: 'speed_pip',
        title: 'Speed PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlaySpeed('speed_pip', 2.0);
      expect(viewModel.overlayClips.first.speed, 2.0);

      viewModel.updateOverlaySpeed('speed_pip', 0.5);
      expect(viewModel.overlayClips.first.speed, 0.5);
    });

    test('updateOverlayAudio updates volume, mute state and audio fades', () {
      const clip = OverlayClip(
        id: 'audio_pip',
        title: 'Audio PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlayAudio('audio_pip', volume: 1.5, isMuted: true, fadeInSec: 0.8, fadeOutSec: 1.2);
      final updated = viewModel.overlayClips.first;
      expect(updated.volume, 1.5);
      expect(updated.isMuted, true);
      expect(updated.fadeInDurationSec, 0.8);
      expect(updated.fadeOutDurationSec, 1.2);
    });

    test('updateOverlayAnimation updates in/overall/out animations and clears them', () {
      const clip = OverlayClip(
        id: 'anim_pip',
        title: 'Anim PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlayAnimation(
        'anim_pip',
        inAnimation: const PipAnimation(type: 'slideLeft', durationSec: 0.6),
        overallAnimation: const PipAnimation(type: 'pulse'),
        outAnimation: const PipAnimation(type: 'fade', durationSec: 0.4),
      );

      var updated = viewModel.overlayClips.first;
      expect(updated.inAnimation?.type, 'slideLeft');
      expect(updated.overallAnimation?.type, 'pulse');
      expect(updated.outAnimation?.type, 'fade');

      viewModel.updateOverlayAnimation('anim_pip', clearInAnim: true, clearOverallAnim: true, clearOutAnim: true);
      updated = viewModel.overlayClips.first;
      expect(updated.inAnimation, isNull);
      expect(updated.overallAnimation, isNull);
      expect(updated.outAnimation, isNull);
    });

    test('updateOverlayCrop applies non-destructive crop and reset', () {
      const clip = OverlayClip(
        id: 'crop_pip',
        title: 'Crop PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlayCrop('crop_pip', cropRect: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8), cropAspectRatio: '16:9');
      var updated = viewModel.overlayClips.first;
      expect(updated.cropRect, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
      expect(updated.cropAspectRatio, '16:9');

      viewModel.updateOverlayCrop('crop_pip', clearCrop: true);
      updated = viewModel.overlayClips.first;
      expect(updated.cropRect, isNull);
    });

    test('updateOverlayCornerPin sets projective perspective points and reset', () {
      const clip = OverlayClip(
        id: 'corner_pip',
        title: 'Corner Pin PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlayCornerPin(
        'corner_pip',
        topLeft: const Offset(0.1, 0.2),
        topRight: const Offset(0.9, 0.1),
        bottomLeft: const Offset(0.0, 1.0),
        bottomRight: const Offset(1.0, 0.95),
      );
      var updated = viewModel.overlayClips.first;
      expect(updated.cornerTopLeft, const Offset(0.1, 0.2));
      expect(updated.cornerTopRight, const Offset(0.9, 0.1));

      viewModel.updateOverlayCornerPin('corner_pip', clearCornerPin: true);
      updated = viewModel.overlayClips.first;
      expect(updated.cornerTopLeft, isNull);
      expect(updated.cornerTopRight, isNull);
    });

    test('updateOverlayBlendMode and updateOverlayChromaKey configure composite modes', () {
      const clip = OverlayClip(
        id: 'blend_pip',
        title: 'Blend PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.updateOverlayBlendMode('blend_pip', BlendMode.screen);
      expect(viewModel.overlayClips.first.blendMode, BlendMode.screen);

      viewModel.updateOverlayChromaKey(
        'blend_pip',
        enabled: true,
        color: const Color(0xFF00FF00),
        similarity: 0.55,
        smoothness: 0.25,
      );
      final updated = viewModel.overlayClips.first;
      expect(updated.enableChromaKey, true);
      expect(updated.chromaKeyColor, const Color(0xFF00FF00));
      expect(updated.chromaSimilarity, 0.55);
      expect(updated.chromaSmoothness, 0.25);
    });

    test('applySplitScreenPreset updates position, scale, and crop according to preset', () {
      const clip = OverlayClip(
        id: 'split_pip',
        title: 'Split PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addOverlayClip(clip);

      viewModel.applySplitScreenPreset('split_pip', 'left');
      var updated = viewModel.overlayClips.first;
      expect(updated.position.dx, 0.25);
      expect(updated.scale, 0.5);

      viewModel.applySplitScreenPreset('split_pip', 'pictureInPicture');
      updated = viewModel.overlayClips.first;
      expect(updated.position, const Offset(0.75, 0.25));
      expect(updated.scale, 0.35);
    });
  });

  group('PIP Overlay Export Payload Serialization Tests', () {
    test('renderAndExportVideo serializes pipOverlays with all transform and timing fields', () async {
      final project = Project(
        id: 'test_proj',
        name: 'Export PIP Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        videoClips: const [
          VideoClip(
            id: 'clip_base',
            title: 'Base Video',
            assetId: 'asset_base',
            originalDuration: Duration(seconds: 6),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 6),
            previewGradient: [Color(0xFF00C6FF), Color(0xFF0072FF)],
          ),
        ],
        overlayClips: const [
          OverlayClip(
            id: 'ov_export_1',
            title: 'Export PIP',
            assetId: 'asset_pip',
            localPath: '/tmp/test_pip.png',
            thumbnailPath: '/tmp/test_pip_thumb.png',
            isPhoto: true,
            startTime: Duration(seconds: 1),
            duration: Duration(seconds: 4),
            position: Offset(0.6, 0.3),
            scale: 0.75,
            rotation: 0.15,
            opacity: 0.85,
            flipHorizontal: true,
            flipVertical: false,
          ),
        ],
      );

      final assets = [
        MediaAsset(
          id: 'asset_base',
          type: MediaAssetType.video,
          name: 'Base Video',
          createdAt: DateTime.now(),
        ),
        MediaAsset(
          id: 'asset_pip',
          type: MediaAssetType.photo,
          name: 'Export PIP',
          localPath: '/tmp/test_pip.png',
          thumbnailPath: '/tmp/test_pip_thumb.png',
          createdAt: DateTime.now(),
        ),
      ];

      // In unit test without native plugin, renderAndExportVideo returns simulated result
      final result = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: const ExportSettings(
          resolution: ExportResolution.res1080p,
          fps: ExportFps.fps30,
        ),
        assets: assets,
      );

      expect(result, isNotNull);
      expect(result['success'], true);
    });
  });
}
