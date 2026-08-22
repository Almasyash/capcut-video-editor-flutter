import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  group('EditorViewModel State & Actions Test', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initial state loads mock clips, audio track, and text overlays', () {
      expect(viewModel.videoClips.isNotEmpty, isTrue);
      expect(viewModel.selectedClipIndex, equals(0));
      expect(viewModel.playheadPosition, equals(0.0));
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.audioTrack, isNotNull);
      expect(viewModel.textOverlays.isNotEmpty, isTrue);
      expect(viewModel.totalDurationInSeconds, greaterThan(0));
    });

    test('Split at playhead splits the target clip into two valid segments', () {
      final initialCount = viewModel.videoClips.length;
      final initialTotalDuration = viewModel.totalDurationInSeconds;

      // Position playhead at 2.5 seconds (inside first clip)
      viewModel.seekTo(2.5);

      final splitSuccess = viewModel.splitClipAtPlayhead();
      expect(splitSuccess, isTrue);
      expect(viewModel.videoClips.length, equals(initialCount + 1));

      // Total timeline duration should remain approximately unchanged
      expect((viewModel.totalDurationInSeconds - initialTotalDuration).abs(), lessThan(0.05));

      // Undo split
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();
      expect(viewModel.videoClips.length, equals(initialCount));

      // Redo split
      expect(viewModel.canRedo, isTrue);
      viewModel.redo();
      expect(viewModel.videoClips.length, equals(initialCount + 1));
    });

    test('Duplicate to timeline vs Duplicate as Overlay PIP layer', () {
      final initialCount = viewModel.videoClips.length;
      expect(viewModel.overlayClips.isEmpty, isTrue);

      // Duplicate to timeline track
      viewModel.selectClip(0);
      viewModel.duplicateSelectedClip();
      expect(viewModel.videoClips.length, equals(initialCount + 1));

      // Duplicate as PIP Overlay layer
      viewModel.selectClip(0);
      viewModel.duplicateSelectedClipAsOverlay();
      expect(viewModel.overlayClips.length, equals(1));
      expect(viewModel.overlayClips.first.title, contains('PIP Layer'));

      // Undo PIP duplication
      viewModel.undo();
      expect(viewModel.overlayClips.isEmpty, isTrue);
    });

    test('Add Clip from Media Picker adds customized clip to sequence', () {
      final initialCount = viewModel.videoClips.length;

      viewModel.addNewClipFromMedia(
        title: 'Drone 4K Mountain',
        duration: const Duration(seconds: 10),
        gradient: const [Colors.blue, Colors.teal],
        icon: Icons.flight_takeoff_rounded,
      );

      expect(viewModel.videoClips.length, equals(initialCount + 1));
      expect(viewModel.videoClips.last.title, equals('Drone 4K Mountain'));
      expect(viewModel.videoClips.last.durationInSeconds, equals(10.0));
    });

    test('Stickers addition and removal', () {
      expect(viewModel.stickerOverlays.isEmpty, isTrue);

      final stickerPreset = StickerPreset.catalog.first;
      viewModel.addSticker(stickerPreset);

      expect(viewModel.stickerOverlays.length, equals(1));
      expect(viewModel.stickerOverlays.first.preset.label, equals(stickerPreset.label));

      viewModel.removeSticker(viewModel.stickerOverlays.first.id);
      expect(viewModel.stickerOverlays.isEmpty, isTrue);
    });

    test('Filter and color adjustments state transitions', () {
      expect(viewModel.activeFilter.type, equals(FilterType.none));

      final cyberpunk = EditorFilter.presets.firstWhere((f) => f.type == FilterType.cyberpunk);
      viewModel.setFilter(cyberpunk);
      expect(viewModel.activeFilter.type, equals(FilterType.cyberpunk));

      viewModel.setFilterIntensity(0.5);
      expect(viewModel.activeFilter.intensity, equals(0.5));

      // Color adjustments
      viewModel.updateColorAdjustments(const ColorAdjustments(brightness: 0.3, contrast: 1.2));
      expect(viewModel.colorAdjustments.brightness, equals(0.3));
      expect(viewModel.colorAdjustments.contrast, equals(1.2));

      viewModel.resetColorAdjustments();
      expect(viewModel.colorAdjustments.isDefault, isTrue);
    });

    test('Drawer navigation opening and closing', () {
      expect(viewModel.activeDrawer, isNull);

      viewModel.openDrawer(EditorCategory.audio);
      expect(viewModel.activeDrawer, equals(EditorCategory.audio));

      viewModel.openDrawer(EditorCategory.adjust);
      expect(viewModel.activeDrawer, equals(EditorCategory.adjust));

      viewModel.closeDrawer();
      expect(viewModel.activeDrawer, isNull);
    });

    test('Aspect ratio and canvas settings', () {
      expect(viewModel.aspectRatio, equals(AspectRatioPreset.ratio9x16));
      viewModel.setAspectRatio(AspectRatioPreset.ratio16x9);
      expect(viewModel.aspectRatio, equals(AspectRatioPreset.ratio16x9));

      viewModel.setCanvasBackgroundColor(Colors.purple);
      expect(viewModel.canvasBackgroundColor, equals(Colors.purple));

      viewModel.setCanvasBlurSigma(10.0);
      expect(viewModel.canvasBlurSigma, equals(10.0));
    });

    test('Universal Timeline Trimming and Dragging on Audio, PIP, Text, and Stickers', () {
      // 1. Audio Track Timing Update
      expect(viewModel.audioTrack, isNotNull);
      viewModel.updateAudioTrackTiming(const Duration(seconds: 2), const Duration(seconds: 14));
      expect(viewModel.audioTrack!.startTimeInSeconds, equals(2.0));
      expect(viewModel.audioTrack!.durationInSeconds, equals(14.0));

      // 2. Text Overlay Timing Update
      final textId = viewModel.textOverlays.first.id;
      viewModel.updateTextOverlayTiming(textId, const Duration(seconds: 3), const Duration(seconds: 6));
      final updatedText = viewModel.textOverlays.firstWhere((t) => t.id == textId);
      expect(updatedText.startTimeInSeconds, equals(3.0));
      expect(updatedText.durationInSeconds, equals(6.0));

      // 3. PIP Overlay Timing Update
      final overlay = const OverlayClip(
        id: 'pip_test_1',
        title: 'PIP Test',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 5),
        previewGradient: [Colors.red, Colors.orange],
      );
      viewModel.addOverlayClip(overlay);
      viewModel.updateOverlayClipTiming('pip_test_1', const Duration(seconds: 2), const Duration(seconds: 8));
      final updatedOverlay = viewModel.overlayClips.firstWhere((o) => o.id == 'pip_test_1');
      expect(updatedOverlay.startTimeInSeconds, equals(2.0));
      expect(updatedOverlay.durationInSeconds, equals(8.0));

      // 4. Sticker Timing Update
      viewModel.addSticker(StickerPreset.catalog.first);
      final stickerId = viewModel.stickerOverlays.first.id;
      viewModel.updateStickerTiming(stickerId, const Duration(seconds: 4), const Duration(seconds: 5));
      final updatedSticker = viewModel.stickerOverlays.firstWhere((s) => s.id == stickerId);
      expect(updatedSticker.startTimeInSeconds, equals(4.0));
      expect(updatedSticker.durationInSeconds, equals(5.0));
    });

    test('DeviceMediaService creates valid video, photo, and audio media results', () {
      final videoResult = DeviceMediaService.createCustomVideoResult(name: 'Trip_Vlog', duration: const Duration(seconds: 15));
      expect(videoResult.fileName, equals('Trip_Vlog.mp4'));
      expect(videoResult.fileType, equals('video'));
      expect(videoResult.estimatedDuration.inSeconds, equals(15));

      final audioResult = DeviceMediaService.createCustomAudioResult(name: 'Theme_Song', duration: const Duration(seconds: 30));
      expect(audioResult.fileName, equals('Theme_Song.mp3'));
      expect(audioResult.fileType, equals('audio'));
      expect(audioResult.estimatedDuration.inSeconds, equals(30));

      final photoResult = DeviceMediaService.createCustomPhotoResult(name: 'Selfie');
      expect(photoResult.fileName, equals('Selfie.jpg'));
      expect(photoResult.fileType, equals('photo'));
    });
  });
}
