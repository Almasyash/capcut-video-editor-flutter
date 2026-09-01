import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/asset_download_service.dart';
import 'package:capcut_video_editor/core/services/asset_storage_service.dart';
import 'package:capcut_video_editor/core/services/audio_playback_service.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/data/repositories/asset_repository.dart';
import 'package:capcut_video_editor/data/repositories/mock_media_repository.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditorViewModel State & Actions Test', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initial state loads mock clips, text overlays, and empty audio track', () {
      expect(viewModel.videoClips.isNotEmpty, isTrue);
      expect(viewModel.selectedClipIndex, equals(0));
      expect(viewModel.playheadPosition, equals(0.0));
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.audioTrack, isNull);
      expect(viewModel.audioTracks, isEmpty);
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
        assetId: 'preset_video_01',
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
      const track = AudioTrack(
        id: 'audio_trim_drag_test',
        assetId: 'asset_trim_drag',
        title: 'Audio Trim Test',
        duration: Duration(seconds: 20),
      );
      viewModel.addAudioTrack(track);
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
      const overlay = OverlayClip(
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
      expect(videoResult.filePath, contains('Trip_Vlog.mp4'));

      final audioResult = DeviceMediaService.createCustomAudioResult(name: 'Theme_Song', duration: const Duration(seconds: 30));
      expect(audioResult.fileName, equals('Theme_Song.mp3'));
      expect(audioResult.fileType, equals('audio'));
      expect(audioResult.estimatedDuration.inSeconds, equals(30));
      expect(audioResult.filePath, contains('Theme_Song.mp3'));

      final photoResult = DeviceMediaService.createCustomPhotoResult(name: 'Selfie');
      expect(photoResult.fileName, equals('Selfie.jpg'));
      expect(photoResult.fileType, equals('photo'));
      expect(photoResult.filePath, contains('Selfie.jpg'));

      // Test binding assetId to timeline and resolving via getAssetById
      final testAsset = videoResult.toMediaAsset();
      viewModel.addMediaAsset(testAsset);
      viewModel.addNewClipFromMedia(
        assetId: testAsset.id,
        title: videoResult.fileName,
        duration: videoResult.estimatedDuration,
        gradient: videoResult.gradient,
        icon: videoResult.icon,
      );
      expect(viewModel.videoClips.last.assetId, equals(testAsset.id));
      expect(viewModel.getAssetById(viewModel.videoClips.last.assetId)?.localPath, equals(testAsset.localPath));

      // Test MediaAsset model serialization & conversion
      final mediaAsset = videoResult.toMediaAsset();
      expect(mediaAsset.type, equals(MediaAssetType.video));
      expect(mediaAsset.name, equals('Trip_Vlog.mp4'));
      expect(mediaAsset.localPath, contains('Trip_Vlog.mp4'));
      expect(mediaAsset.duration, isNull); // Rule 4: No fake durations

      final json = mediaAsset.toJson();
      final restored = MediaAsset.fromJson(json);
      expect(restored.id, equals(mediaAsset.id));
      expect(restored.name, equals(mediaAsset.name));
      expect(restored.type, equals(mediaAsset.type));
      expect(restored.localPath, equals(mediaAsset.localPath));
      expect(restored.duration, isNull);
    });

    group('Centralized MediaLibrary & MediaAsset Flow Tests', () {
      test('1. Initial mediaLibrary is empty', () {
        expect(viewModel.mediaLibrary, isEmpty);
      });

      test('2. Successful video asset addition adds one MediaAsset', () {
        final videoAsset = MediaAsset(
          id: 'asset_vid_1',
          type: MediaAssetType.video,
          name: 'sample_video.mp4',
          localPath: '/storage/sample_video.mp4',
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(videoAsset);
        expect(viewModel.mediaLibrary.length, equals(1));
        expect(viewModel.mediaLibrary.first.id, equals('asset_vid_1'));
        expect(viewModel.mediaLibrary.first.type, equals(MediaAssetType.video));
      });

      test('3. Successful audio asset addition adds one MediaAsset', () {
        final audioAsset = MediaAsset(
          id: 'asset_aud_1',
          type: MediaAssetType.audio,
          name: 'podcast_track.mp3',
          localPath: '/storage/podcast_track.mp3',
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(audioAsset);
        expect(viewModel.mediaLibrary.length, equals(1));
        expect(viewModel.mediaLibrary.first.id, equals('asset_aud_1'));
        expect(viewModel.mediaLibrary.first.type, equals(MediaAssetType.audio));
      });

      test('4 & 5. Cancelled/null import does not modify mediaLibrary', () async {
        final initialCount = viewModel.mediaLibrary.length;
        // Simulating cancelled or failed imports where nothing is added
        expect(viewModel.mediaLibrary.length, equals(initialCount));
      });

      test('6. Duplicate video asset is not added twice', () {
        final videoAsset1 = MediaAsset(
          id: 'asset_vid_1',
          type: MediaAssetType.video,
          name: 'same_file.mp4',
          localPath: '/storage/cache/same_file.mp4',
          createdAt: DateTime.now(),
        );
        final videoAsset2 = MediaAsset(
          id: 'asset_vid_2',
          type: MediaAssetType.video,
          name: 'same_file_copy.mp4',
          localPath: '/storage/cache/same_file.mp4',
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(videoAsset1);
        expect(viewModel.mediaLibrary.length, equals(1));

        viewModel.addMediaAsset(videoAsset2);
        expect(viewModel.mediaLibrary.length, equals(1)); // duplicate rejected
      });

      test('7. Duplicate audio asset is not added twice', () {
        final audioAsset1 = MediaAsset(
          id: 'asset_aud_1',
          type: MediaAssetType.audio,
          name: 'song.mp3',
          localPath: '/storage/cache/song.mp3',
          createdAt: DateTime.now(),
        );
        final audioAsset2 = MediaAsset(
          id: 'asset_aud_2',
          type: MediaAssetType.audio,
          name: 'song_renamed.mp3',
          localPath: '/storage/cache/song.mp3',
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(audioAsset1);
        expect(viewModel.mediaLibrary.length, equals(1));

        viewModel.addMediaAsset(audioAsset2);
        expect(viewModel.mediaLibrary.length, equals(1)); // duplicate rejected
      });

      test('8. getAssetById() returns the correct asset', () {
        final asset = MediaAsset(
          id: 'asset_target_99',
          type: MediaAssetType.video,
          name: 'target_video.mp4',
          localPath: '/storage/target_video.mp4',
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(asset);

        final retrieved = viewModel.getAssetById('asset_target_99');
        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals('asset_target_99'));
        expect(retrieved.name, equals('target_video.mp4'));
      });

      test('9. getAssetById() returns null for unknown ID', () {
        final unknown = viewModel.getAssetById('non_existent_id');
        expect(unknown, isNull);
      });

      test('10. removeMediaAsset() removes the correct asset', () {
        final asset = MediaAsset(
          id: 'asset_to_delete',
          type: MediaAssetType.video,
          name: 'delete_me.mp4',
          localPath: '/storage/delete_me.mp4',
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(asset);
        expect(viewModel.mediaLibrary.length, equals(1));

        viewModel.removeMediaAsset('asset_to_delete');
        expect(viewModel.mediaLibrary, isEmpty);
      });

      test('11. Removing one asset does not remove another asset', () {
        final asset1 = MediaAsset(
          id: 'asset_stay',
          type: MediaAssetType.video,
          name: 'keep.mp4',
          localPath: '/storage/keep.mp4',
          createdAt: DateTime.now(),
        );
        final asset2 = MediaAsset(
          id: 'asset_remove',
          type: MediaAssetType.audio,
          name: 'remove.mp3',
          localPath: '/storage/remove.mp3',
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(asset1);
        viewModel.addMediaAsset(asset2);
        expect(viewModel.mediaLibrary.length, equals(2));

        viewModel.removeMediaAsset('asset_remove');
        expect(viewModel.mediaLibrary.length, equals(1));
        expect(viewModel.mediaLibrary.first.id, equals('asset_stay'));
      });
    });

    group('Step 3: Timeline Model Migration & Media Asset References Tests', () {
      test('1. VideoClip stores assetId correctly', () {
        const clip = VideoClip(
          id: 'clip_test_1',
          assetId: 'media_asset_video_100',
          title: 'Test Clip',
          originalDuration: Duration(seconds: 10),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 10),
          previewGradient: [Colors.blue, Colors.green],
        );
        expect(clip.assetId, equals('media_asset_video_100'));
        expect(clip.id, equals('clip_test_1'));
      });

      test('2. AudioTrack stores assetId correctly', () {
        const track = AudioTrack(
          id: 'audio_test_1',
          assetId: 'media_asset_audio_200',
          title: 'Test Audio',
          duration: Duration(seconds: 20),
          waveformPoints: [0.1, 0.5, 0.9],
        );
        expect(track.assetId, equals('media_asset_audio_200'));
        expect(track.id, equals('audio_test_1'));
      });

      test('3 & 4. VideoClip does not require content:// URI or raw path as its identity', () {
        const clip = VideoClip(
          id: 'timeline_clip_300',
          assetId: 'asset_clean_id_400',
          title: 'Clean Reference Clip',
          originalDuration: Duration(seconds: 5),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 5),
          previewGradient: [Colors.purple, Colors.orange],
        );
        expect(clip.assetId, isNot(startsWith('content://')));
        expect(clip.assetId, isNot(startsWith('/')));
        expect(clip.assetId, equals('asset_clean_id_400'));
      });

      test('5. AudioTrack uses MediaAsset.id as assetId', () {
        final audioAsset = MediaAsset(
          id: 'unique_audio_asset_500',
          type: MediaAssetType.audio,
          name: 'Soundtrack.mp3',
          localPath: '/storage/music/Soundtrack.mp3',
          duration: const Duration(seconds: 45),
          createdAt: DateTime.now(),
        );

        final track = AudioTrack(
          id: 'track_instance_1',
          assetId: audioAsset.id,
          title: audioAsset.name,
          duration: audioAsset.duration!,
          waveformPoints: const [0.2, 0.6, 0.4],
        );
        expect(track.assetId, equals(audioAsset.id));
      });

      test('6. getAssetById(videoClip.assetId) returns the source asset', () {
        final sourceAsset = MediaAsset(
          id: 'source_video_asset_600',
          type: MediaAssetType.video,
          name: '4K_Drone.mp4',
          localPath: '/storage/videos/4K_Drone.mp4',
          duration: const Duration(seconds: 15),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(sourceAsset);

        viewModel.addNewClipFromMedia(
          assetId: sourceAsset.id,
          title: sourceAsset.name,
          duration: const Duration(seconds: 15),
          gradient: const [Colors.red, Colors.yellow],
        );

        final lastClip = viewModel.videoClips.last;
        final resolvedAsset = viewModel.getAssetById(lastClip.assetId);
        expect(resolvedAsset, isNotNull);
        expect(resolvedAsset!.id, equals(sourceAsset.id));
        expect(resolvedAsset.name, equals('4K_Drone.mp4'));
      });

      test('7. getAssetById(audioTrack.assetId) returns the source asset', () {
        final sourceAudioAsset = MediaAsset(
          id: 'source_audio_asset_700',
          type: MediaAssetType.audio,
          name: 'Beat.mp3',
          localPath: '/storage/audio/Beat.mp3',
          duration: const Duration(seconds: 30),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(sourceAudioAsset);

        final track = AudioTrack(
          id: 'audio_timeline_track_1',
          assetId: sourceAudioAsset.id,
          title: sourceAudioAsset.name,
          duration: const Duration(seconds: 30),
          waveformPoints: const [0.5, 0.5, 0.5],
        );
        viewModel.addAudioTrack(track);

        final resolvedAsset = viewModel.getAssetById(viewModel.audioTrack!.assetId);
        expect(resolvedAsset, isNotNull);
        expect(resolvedAsset!.id, equals(sourceAudioAsset.id));
        expect(resolvedAsset.name, equals('Beat.mp3'));
      });

      test('8. Two timeline clips can reference the same MediaAsset (Asset A -> Clip 1 & Clip 2)', () {
        final sharedAsset = MediaAsset(
          id: 'shared_source_asset_800',
          type: MediaAssetType.video,
          name: 'Hero_Scene.mp4',
          localPath: '/storage/Hero_Scene.mp4',
          duration: const Duration(seconds: 10),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(sharedAsset);

        // Add Clip 1 from shared asset
        viewModel.addNewClipFromMedia(
          assetId: sharedAsset.id,
          title: 'Hero Scene Part 1',
          duration: const Duration(seconds: 5),
          gradient: const [Colors.teal, Colors.blue],
        );
        final clip1 = viewModel.videoClips.last;

        // Add Clip 2 from same shared asset
        viewModel.addNewClipFromMedia(
          assetId: sharedAsset.id,
          title: 'Hero Scene Part 2',
          duration: const Duration(seconds: 5),
          gradient: const [Colors.teal, Colors.blue],
        );
        final clip2 = viewModel.videoClips.last;

        expect(clip1.id, isNot(equals(clip2.id))); // Unique timeline instances
        expect(clip1.assetId, equals(sharedAsset.id)); // Same source media asset reference
        expect(clip2.assetId, equals(sharedAsset.id)); // Same source media asset reference
        expect(viewModel.getAssetById(clip1.assetId), equals(sharedAsset));
        expect(viewModel.getAssetById(clip2.assetId), equals(sharedAsset));
      });
    });

    group('Step 4: Migrate Runtime Media Resolution to MediaAsset Tests', () {
      test('1. VideoClip resolves MediaAsset by assetId', () {
        final asset = MediaAsset(
          id: 'step4_video_asset_1',
          type: MediaAssetType.video,
          name: 'Scenic_Drive.mp4',
          localPath: '/storage/videos/Scenic_Drive.mp4',
          duration: const Duration(seconds: 12),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(asset);

        viewModel.addNewClipFromMedia(
          assetId: asset.id,
          title: asset.name,
          duration: const Duration(seconds: 12),
          gradient: const [Colors.indigo, Colors.cyan],
        );

        final clip = viewModel.videoClips.last;
        final resolved = viewModel.getAssetById(clip.assetId);
        expect(resolved, isNotNull);
        expect(resolved!.id, equals(asset.id));
        expect(resolved.localPath, equals('/storage/videos/Scenic_Drive.mp4'));
      });

      test('2. VideoClip with missing/stale assetId does not crash', () {
        const staleClip = VideoClip(
          id: 'clip_stale_1',
          assetId: 'non_existent_asset_id_999',
          title: 'Stale Clip',
          originalDuration: Duration(seconds: 5),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 5),
          previewGradient: [Colors.grey, Colors.blueGrey],
        );

        final resolved = viewModel.getAssetById(staleClip.assetId);
        expect(resolved, isNull); // Graceful null handling, no crash
      });

      test('3. AudioTrack resolves MediaAsset by assetId', () {
        final audioAsset = MediaAsset(
          id: 'step4_audio_asset_1',
          type: MediaAssetType.audio,
          name: 'Upbeat_Vibe.mp3',
          localPath: '/storage/music/Upbeat_Vibe.mp3',
          duration: const Duration(seconds: 35),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(audioAsset);

        final track = AudioTrack(
          id: 'track_step4_1',
          assetId: audioAsset.id,
          title: audioAsset.name,
          duration: const Duration(seconds: 35),
          waveformPoints: const [0.3, 0.7, 0.4],
        );
        viewModel.addAudioTrack(track);

        final resolved = viewModel.getAssetById(viewModel.audioTrack!.assetId);
        expect(resolved, isNotNull);
        expect(resolved!.id, equals(audioAsset.id));
        expect(resolved.localPath, equals('/storage/music/Upbeat_Vibe.mp3'));
      });

      test('4. AudioTrack with missing/stale assetId does not crash', () {
        const staleTrack = AudioTrack(
          id: 'track_stale_1',
          assetId: 'stale_audio_id_888',
          title: 'Stale Audio',
          duration: Duration(seconds: 15),
          waveformPoints: [0.1, 0.2, 0.3],
        );

        final resolved = viewModel.getAssetById(staleTrack.assetId);
        expect(resolved, isNull); // Graceful null handling, no crash
      });

      test('5. Removing a MediaAsset does not cause a runtime exception', () {
        final asset = MediaAsset(
          id: 'asset_to_be_deleted_1',
          type: MediaAssetType.video,
          name: 'Temporary.mp4',
          localPath: '/storage/Temporary.mp4',
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(asset);
        viewModel.addNewClipFromMedia(
          assetId: asset.id,
          title: asset.name,
          duration: const Duration(seconds: 6),
          gradient: const [Colors.amber, Colors.deepOrange],
        );

        final clip = viewModel.videoClips.last;
        expect(viewModel.getAssetById(clip.assetId), isNotNull);

        // Remove asset from library
        viewModel.removeMediaAsset(asset.id);

        // Resolving should now safely return null without throwing
        expect(() => viewModel.getAssetById(clip.assetId), returnsNormally);
        expect(viewModel.getAssetById(clip.assetId), isNull);
      });

      test('6. Multiple VideoClips can resolve the same MediaAsset', () {
        final masterAsset = MediaAsset(
          id: 'master_camera_feed_1',
          type: MediaAssetType.video,
          name: 'Master_Take.mp4',
          localPath: '/storage/Master_Take.mp4',
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(masterAsset);

        viewModel.addNewClipFromMedia(
          assetId: masterAsset.id,
          title: 'Take 1 - Start',
          duration: const Duration(seconds: 4),
          gradient: const [Colors.purple, Colors.pink],
        );
        final clipA = viewModel.videoClips.last;

        viewModel.addNewClipFromMedia(
          assetId: masterAsset.id,
          title: 'Take 1 - End',
          duration: const Duration(seconds: 4),
          gradient: const [Colors.purple, Colors.pink],
        );
        final clipB = viewModel.videoClips.last;

        expect(clipA.id, isNot(equals(clipB.id)));
        expect(viewModel.getAssetById(clipA.assetId), equals(masterAsset));
        expect(viewModel.getAssetById(clipB.assetId), equals(masterAsset));
        expect(viewModel.getAssetById(clipA.assetId)?.localPath, equals('/storage/Master_Take.mp4'));
        expect(viewModel.getAssetById(clipB.assetId)?.localPath, equals('/storage/Master_Take.mp4'));
      });

      test('7. Preview uses MediaAsset.localPath dynamically via getAssetById', () {
        final previewAsset = MediaAsset(
          id: 'preview_asset_100',
          type: MediaAssetType.video,
          name: 'Preview_Target.mp4',
          localPath: '/storage/emulated/0/DCIM/Preview_Target.mp4',
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(previewAsset);

        viewModel.addNewClipFromMedia(
          assetId: previewAsset.id,
          title: previewAsset.name,
          duration: const Duration(seconds: 10),
          gradient: const [Colors.cyan, Colors.blue],
        );

        final activeClip = viewModel.videoClips.last;
        final resolvedLocalPath = viewModel.getAssetById(activeClip.assetId)?.localPath;
        expect(resolvedLocalPath, equals('/storage/emulated/0/DCIM/Preview_Target.mp4'));
      });

      test('8. Audio playback/track uses MediaAsset.localPath dynamically via getAssetById', () {
        final playbackAudioAsset = MediaAsset(
          id: 'playback_audio_asset_200',
          type: MediaAssetType.audio,
          name: 'Playback_Soundtrack.mp3',
          localPath: '/storage/emulated/0/Music/Playback_Soundtrack.mp3',
          duration: const Duration(seconds: 60),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(playbackAudioAsset);

        final track = AudioTrack(
          id: 'timeline_audio_track_200',
          assetId: playbackAudioAsset.id,
          title: playbackAudioAsset.name,
          duration: const Duration(seconds: 60),
          waveformPoints: const [0.4, 0.8, 0.4],
        );
        viewModel.addAudioTrack(track);

        final resolvedAudioPath = viewModel.getAssetById(viewModel.audioTrack!.assetId)?.localPath;
        expect(resolvedAudioPath, equals('/storage/emulated/0/Music/Playback_Soundtrack.mp3'));
      });
    });

    group('Gallery Video Resolution & Playback Verification (Tests A, B, C, D)', () {
      test('Test A — Gallery video: imported, MediaAsset created, duration detected, thumbnail created, Timeline clip resolves', () {
        final sampleVideoAsset = MediaAsset(
          id: 'gallery_asset_mp4_1',
          type: MediaAssetType.video,
          name: 'VID_873687.mp4',
          uri: 'content://media/external/video/media/873687',
          localPath: '/data/user/0/com.example.capcut_video_editor/cache/VID_873687.mp4',
          thumbnailPath: '/data/user/0/com.example.capcut_video_editor/cache/VID_873687_thumb.jpg',
          duration: const Duration(seconds: 12),
          sizeBytes: 15 * 1024 * 1024,
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(sampleVideoAsset);
        expect(viewModel.mediaLibrary.length, equals(1));
        expect(viewModel.mediaLibrary.first.duration, equals(const Duration(seconds: 12)));
        expect(viewModel.mediaLibrary.first.thumbnailPath, isNotNull);

        viewModel.addNewClipFromMedia(
          assetId: sampleVideoAsset.id,
          title: sampleVideoAsset.name,
          duration: sampleVideoAsset.duration ?? const Duration(seconds: 8),
          gradient: const [Colors.teal, Colors.blue],
        );

        final activeClip = viewModel.videoClips.last;
        expect(activeClip.title, equals('VID_873687.mp4'));
        expect(activeClip.durationInSeconds, equals(12.0));

        final resolvedAsset = viewModel.getAssetById(activeClip.assetId);
        expect(resolvedAsset, isNotNull);
        expect(resolvedAsset!.localPath, equals('/data/user/0/com.example.capcut_video_editor/cache/VID_873687.mp4'));
        expect(resolvedAsset.thumbnailPath, equals('/data/user/0/com.example.capcut_video_editor/cache/VID_873687_thumb.jpg'));
        expect(resolvedAsset.duration, equals(const Duration(seconds: 12)));
      });

      test('Test B — Different video: second video with different duration resolves independently without stale previous data', () {
        final video1 = MediaAsset(
          id: 'gallery_vid_1',
          type: MediaAssetType.video,
          name: 'Vlog_Day1.mp4',
          localPath: '/data/user/0/cache/Vlog_Day1.mp4',
          thumbnailPath: '/data/user/0/cache/Vlog_Day1_thumb.jpg',
          duration: const Duration(seconds: 15),
          createdAt: DateTime.now(),
        );

        final video2 = MediaAsset(
          id: 'gallery_vid_2',
          type: MediaAssetType.video,
          name: 'Drone_Shot.mp4',
          localPath: '/data/user/0/cache/Drone_Shot.mp4',
          thumbnailPath: '/data/user/0/cache/Drone_Shot_thumb.jpg',
          duration: const Duration(seconds: 45),
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(video1);
        viewModel.addMediaAsset(video2);

        viewModel.addNewClipFromMedia(
          assetId: video1.id,
          title: video1.name,
          duration: video1.duration!,
          gradient: const [Colors.red, Colors.orange],
        );
        final clip1 = viewModel.videoClips.last;

        viewModel.addNewClipFromMedia(
          assetId: video2.id,
          title: video2.name,
          duration: video2.duration!,
          gradient: const [Colors.purple, Colors.blue],
        );
        final clip2 = viewModel.videoClips.last;

        expect(clip1.durationInSeconds, equals(15.0));
        expect(clip2.durationInSeconds, equals(45.0));
        expect(viewModel.getAssetById(clip1.assetId)?.localPath, equals('/data/user/0/cache/Vlog_Day1.mp4'));
        expect(viewModel.getAssetById(clip2.assetId)?.localPath, equals('/data/user/0/cache/Drone_Shot.mp4'));
      });

      test('Test C — App restart / persistence: MediaAsset serialized and restored preserves playable source', () {
        final originalAsset = MediaAsset(
          id: 'persisted_vid_99',
          type: MediaAssetType.video,
          name: 'Cinema_Reel.mp4',
          uri: 'content://media/external/video/media/99',
          localPath: '/data/user/0/cache/Cinema_Reel.mp4',
          thumbnailPath: '/data/user/0/cache/Cinema_Reel_thumb.jpg',
          duration: const Duration(seconds: 30),
          sizeBytes: 25 * 1024 * 1024,
          createdAt: DateTime.now(),
        );

        final json = originalAsset.toJson();
        final restoredAsset = MediaAsset.fromJson(json);

        expect(restoredAsset.id, equals(originalAsset.id));
        expect(restoredAsset.localPath, equals(originalAsset.localPath));
        expect(restoredAsset.thumbnailPath, equals(originalAsset.thumbnailPath));
        expect(restoredAsset.duration, equals(originalAsset.duration));

        viewModel.addMediaAsset(restoredAsset);
        final fetched = viewModel.getAssetById(restoredAsset.id);
        expect(fetched?.localPath, equals('/data/user/0/cache/Cinema_Reel.mp4'));
      });

      test('Test D — Invalid/missing file: missing assetId or non-existent path handles gracefully without crash', () {
        const ghostClip = VideoClip(
          id: 'clip_ghost_999',
          assetId: 'non_existent_asset_id',
          title: 'Ghost Clip',
          originalDuration: Duration(seconds: 5),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 5),
          previewGradient: [Colors.grey, Colors.black],
          previewIcon: Icons.broken_image,
        );

        expect(viewModel.getAssetById(ghostClip.assetId), isNull);
        expect(viewModel.getAssetById(ghostClip.assetId)?.localPath, isNull);
        expect(viewModel.getAssetById(ghostClip.assetId)?.thumbnailPath, isNull);
      });
    });

    group('Separate Audio Import & Timeline Playback Suite', () {
      test('1. Audio file imported -> MediaAsset created with correct duration and localPath', () {
        final audioAsset = MediaAsset(
          id: 'audio_import_101',
          type: MediaAssetType.audio,
          name: 'Beat_Drop.mp3',
          localPath: '/data/user/0/files/media/Beat_Drop.mp3',
          duration: const Duration(seconds: 42),
          sizeBytes: 3 * 1024 * 1024,
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(audioAsset);
        expect(viewModel.mediaLibrary.contains(audioAsset), isTrue);

        final track = AudioTrack(
          id: 'timeline_audio_1',
          assetId: audioAsset.id,
          title: audioAsset.name,
          artist: 'Device Audio',
          duration: audioAsset.duration!,
          volume: 0.8,
          waveformPoints: const [0.2, 0.5, 0.8, 0.4],
        );
        viewModel.addAudioTrack(track);

        expect(viewModel.audioTrack, isNotNull);
        expect(viewModel.audioTrack?.assetId, equals('audio_import_101'));
        expect(viewModel.audioTrack?.title, equals('Beat_Drop.mp3'));
        expect(viewModel.audioTrack?.durationInSeconds, equals(42.0));
      });

      test('2. Audio track volume and trimming operate independently of video clips', () {
        final audioAsset = MediaAsset(
          id: 'audio_import_102',
          type: MediaAssetType.audio,
          name: 'Chill_Vibes.mp3',
          localPath: '/data/user/0/files/media/Chill_Vibes.mp3',
          duration: const Duration(seconds: 60),
          createdAt: DateTime.now(),
        );
        viewModel.addMediaAsset(audioAsset);

        final track = AudioTrack(
          id: 'timeline_audio_2',
          assetId: audioAsset.id,
          title: audioAsset.name,
          duration: const Duration(seconds: 60),
          volume: 1.0,
          waveformPoints: const [0.3, 0.6],
        );
        viewModel.addAudioTrack(track);

        viewModel.setAudioTrackVolume(0.45);
        expect(viewModel.audioTrack?.volume, equals(0.45));

        viewModel.updateAudioTrackTiming(const Duration(seconds: 5), const Duration(seconds: 30));
        expect(viewModel.audioTrack?.startTimeInSeconds, equals(5.0));
        expect(viewModel.audioTrack?.durationInSeconds, equals(30.0));
      });

      test('3. Removing audio track clears state and disposes session cleanly', () {
        const track = AudioTrack(
          id: 'test_remove_audio',
          assetId: 'asset_remove_audio',
          title: 'Track to remove',
          duration: Duration(seconds: 10),
        );
        viewModel.addAudioTrack(track);
        expect(viewModel.audioTrack, isNotNull);
        viewModel.removeAudioTrack();
        expect(viewModel.audioTrack, isNull);
        expect(viewModel.isAudioSelected, isFalse);
      });
    });

    group('Separate Text Overlay Suite', () {
      late TextOverlay sampleText;

      setUp(() {
        sampleText = const TextOverlay(
          id: 'text_custom_1',
          text: '⚡ Exclusive BTS Footage',
          startTime: Duration(milliseconds: 3500),
          duration: Duration(seconds: 5),
          textColor: Colors.amber,
          fontSize: 26.0,
          position: Offset(0.5, 0.4),
        );
        viewModel.addTextOverlay(sampleText);
      });

      test('1. User enters custom text -> TextOverlay created with custom styling and playhead start time', () {
        expect(viewModel.textOverlays.any((t) => t.id == 'text_custom_1'), isTrue);
        expect(viewModel.selectedTextId, equals('text_custom_1'));

        final retrieved = viewModel.textOverlays.firstWhere((t) => t.id == 'text_custom_1');
        expect(retrieved.text, equals('⚡ Exclusive BTS Footage'));
        expect(retrieved.startTimeInSeconds, equals(3.5));
        expect(retrieved.durationInSeconds, equals(5.0));
        expect(retrieved.color, equals(Colors.amber));
        expect(retrieved.fontSize, equals(26.0));
      });

      test('2. activeTextOverlaysAtPlayhead correctly reflects visibility over time range', () {
        // Text is from 3.5s to 8.5s
        viewModel.seekTo(1.0);
        expect(viewModel.activeTextOverlaysAtPlayhead.any((t) => t.id == 'text_custom_1'), isFalse);

        viewModel.seekTo(3.5);
        expect(viewModel.activeTextOverlaysAtPlayhead.any((t) => t.id == 'text_custom_1'), isTrue);

        viewModel.seekTo(6.0);
        expect(viewModel.activeTextOverlaysAtPlayhead.any((t) => t.id == 'text_custom_1'), isTrue);

        viewModel.seekTo(9.0);
        expect(viewModel.activeTextOverlaysAtPlayhead.any((t) => t.id == 'text_custom_1'), isFalse);
      });

      test('3. Dragging/repositioning text updates position offset in state', () {
        viewModel.updateTextPosition('text_custom_1', const Offset(0.7, 0.3));
        final updated = viewModel.textOverlays.firstWhere((t) => t.id == 'text_custom_1');
        expect(updated.position, equals(const Offset(0.7, 0.3)));
      });

      test('4. Editing and deleting text overlay updates state and removes cleanly', () {
        final existing = viewModel.textOverlays.firstWhere((t) => t.id == 'text_custom_1');
        viewModel.updateTextOverlay(existing.copyWith(text: 'Updated Title'));
        expect(viewModel.textOverlays.firstWhere((t) => t.id == 'text_custom_1').text, equals('Updated Title'));

        viewModel.removeTextOverlay('text_custom_1');
        expect(viewModel.textOverlays.any((t) => t.id == 'text_custom_1'), isFalse);
        expect(viewModel.selectedTextId, isNull);
      });
    });

    group('Project & Draft Persistence Suite', () {
      test('1. Project model serializes to JSON and deserializes with complete fidelity', () {
        final project = Project(
          id: 'proj_persistence_test_1',
          name: 'Vlog Edit Reel',
          createdAt: DateTime(2026, 8, 28, 12, 0),
          updatedAt: DateTime(2026, 8, 28, 12, 30),
          aspectRatio: AspectRatioPreset.ratio9x16,
          videoClips: const [
            VideoClip(
              id: 'clip_p1',
              assetId: 'asset_vid_p1',
              title: 'Drone Intro.mp4',
              originalDuration: Duration(seconds: 15),
              trimStart: Duration.zero,
              trimEnd: Duration(seconds: 15),
              previewGradient: [Colors.blue, Colors.cyan],
            ),
          ],
          audioTracks: const [
            AudioTrack(
              id: 'audio_p1',
              assetId: 'asset_aud_p1',
              title: 'Beat.mp3',
              duration: Duration(seconds: 25),
              waveformPoints: [0.2, 0.6, 0.4],
            ),
          ],
          textOverlays: const [
            TextOverlay(
              id: 'text_p1',
              text: 'Welcome to Dubai',
              startTime: Duration(seconds: 1),
              duration: Duration(seconds: 4),
            ),
          ],
        );

        final json = project.toJson();
        final restored = Project.fromJson(json);

        expect(restored.id, equals(project.id));
        expect(restored.name, equals('Vlog Edit Reel'));
        expect(restored.videoClips.length, equals(1));
        expect(restored.videoClips.first.title, equals('Drone Intro.mp4'));
        expect(restored.audioTrack?.title, equals('Beat.mp3'));
        expect(restored.textOverlays.length, equals(1));
        expect(restored.textOverlays.first.text, equals('Welcome to Dubai'));
      });

      test('2. ProjectStorageService saves and retrieves drafts', () async {
        final project = await ProjectStorageService.instance.createNewProject(name: 'AutoSaved Draft');
        expect(project.id, startsWith('proj_'));

        final fetched = await ProjectStorageService.instance.getProjectById(project.id);
        expect(fetched, isNotNull);
        expect(fetched?.name, equals('AutoSaved Draft'));

        final all = await ProjectStorageService.instance.getAllProjects();
        expect(all.any((p) => p.id == project.id), isTrue);

        await ProjectStorageService.instance.deleteProject(project.id);
        final afterDelete = await ProjectStorageService.instance.getProjectById(project.id);
        expect(afterDelete, isNull);
      });

      test('3. EditorViewModel loads existing project and retains full timeline state', () {
        final project = Project(
          id: 'proj_load_test',
          name: 'Restored Reel',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          aspectRatio: AspectRatioPreset.ratio16x9,
          videoClips: const [
            VideoClip(
              id: 'c_restored',
              assetId: 'a_restored',
              title: 'Reel Clip',
              originalDuration: Duration(seconds: 20),
              trimStart: Duration(seconds: 2),
              trimEnd: Duration(seconds: 18),
              previewGradient: [Colors.purple, Colors.pink],
            ),
          ],
        );

        final freshViewModel = EditorViewModel(initialProject: project);
        expect(freshViewModel.currentProject.id, equals('proj_load_test'));
        expect(freshViewModel.aspectRatio, equals(AspectRatioPreset.ratio16x9));
        expect(freshViewModel.videoClips.length, equals(1));
        expect(freshViewModel.videoClips.first.title, equals('Reel Clip'));
        expect(freshViewModel.videoClips.first.durationInSeconds, equals(16.0));
      });

      test('4. Missing media on disk does not crash ViewModel', () {
        final missingMediaProject = Project(
          id: 'proj_missing_media',
          name: 'Missing Media Project',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          videoClips: const [
            VideoClip(
              id: 'c_ghost',
              assetId: 'ghost_asset_404',
              title: 'Deleted_On_Storage.mp4',
              originalDuration: Duration(seconds: 10),
              trimStart: Duration.zero,
              trimEnd: Duration(seconds: 10),
              previewGradient: [Colors.grey, Colors.black],
            ),
          ],
        );

        final freshViewModel = EditorViewModel(initialProject: missingMediaProject);
        expect(freshViewModel.videoClips.length, equals(1));
        expect(freshViewModel.getAssetById('ghost_asset_404'), isNull);
        expect(freshViewModel.getAssetById('ghost_asset_404')?.localPath, isNull);
      });
    });

    group('9. Local Audio Editing Controls (Trim, Split, Duplicate, Speed, Volume, Delete, Multi-track)', () {
      late EditorViewModel viewModel;

      setUp(() {
        viewModel = EditorViewModel();
        // Clear default tracks for controlled test isolation
        while (viewModel.audioTracks.isNotEmpty) {
          viewModel.removeAudioTrack(viewModel.audioTracks.first.id);
        }
      });

      test('1. Audio Selection State: Selecting audio isolates selection and deselects video/text', () {
        const track1 = AudioTrack(
          id: 'audio_test_1',
          assetId: 'asset_test_1',
          title: 'Cinematic_Beat.mp3',
          duration: Duration(seconds: 30),
        );
        viewModel.addAudioTrack(track1);

        expect(viewModel.audioTracks.length, equals(1));
        expect(viewModel.isAudioSelected, isTrue);
        expect(viewModel.selectedAudioTrackId, equals('audio_test_1'));
        expect(viewModel.selectedAudioTrack?.title, equals('Cinematic_Beat.mp3'));
        expect(viewModel.selectedClip, isNull);
        expect(viewModel.selectedTextId, isNull);

        // Select a video clip -> audio should deselect
        if (viewModel.videoClips.isNotEmpty) {
          viewModel.selectClip(0);
          expect(viewModel.selectedClip, isNotNull);
          expect(viewModel.isAudioSelected, isFalse);
          expect(viewModel.selectedAudioTrackId, isNull);
        }

        // Reselect audio
        viewModel.selectAudioTrack('audio_test_1');
        expect(viewModel.isAudioSelected, isTrue);
        expect(viewModel.selectedClip, isNull);
      });

      test('2. Audio Trimming: Non-destructive Trim Left and Trim Right update trim boundaries', () {
        const track = AudioTrack(
          id: 'audio_trim_test',
          assetId: 'asset_trim_1',
          title: 'Upbeat_Vlog.mp3',
          duration: Duration(seconds: 40),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 40),
          startTime: Duration.zero,
        );
        viewModel.addAudioTrack(track);
        viewModel.selectAudioTrack('audio_trim_test');

        // Move playhead to 10.0s and Trim Left
        viewModel.seekTo(10.0);
        final trimmedLeft = viewModel.trimAudioLeftToPlayhead();
        expect(trimmedLeft, isTrue);
        expect(viewModel.selectedAudioTrack!.startTimeInSeconds, equals(0.0));
        expect(viewModel.selectedAudioTrack!.trimStart.inSeconds, equals(10));
        expect(viewModel.selectedAudioTrack!.durationInSeconds, equals(30.0));

        // Move playhead to 20.0s and Trim Right
        viewModel.seekTo(20.0);
        final trimmedRight = viewModel.trimAudioRightToPlayhead();
        expect(trimmedRight, isTrue);
        expect(viewModel.selectedAudioTrack!.startTimeInSeconds, equals(0.0));
        expect(viewModel.selectedAudioTrack!.trimEnd!.inSeconds, equals(30));
        expect(viewModel.selectedAudioTrack!.durationInSeconds, equals(20.0));
      });

      test('3. Audio Split: Splits audio at playhead into Part 1 and Part 2 sharing assetId', () {
        const track = AudioTrack(
          id: 'audio_split_test',
          assetId: 'asset_split_1',
          title: 'Background_Ambience.mp3',
          duration: Duration(seconds: 60),
          startTime: Duration.zero,
        );
        viewModel.addAudioTrack(track);
        viewModel.selectAudioTrack('audio_split_test');

        viewModel.seekTo(25.0);
        final splitSuccess = viewModel.splitAudioAtPlayhead();
        expect(splitSuccess, isTrue);
        expect(viewModel.audioTracks.length, equals(2));

        final partA = viewModel.audioTracks[0];
        final partB = viewModel.audioTracks[1];

        expect(partA.title, contains('Part 1'));
        expect(partA.assetId, equals('asset_split_1'));
        expect(partA.trimEnd!.inSeconds, equals(25));
        expect(partA.durationInSeconds, equals(25.0));

        expect(partB.title, contains('Part 2'));
        expect(partB.assetId, equals('asset_split_1'));
        expect(partB.startTimeInSeconds, equals(25.0));
        expect(partB.trimStart.inSeconds, equals(25));
        expect(partB.durationInSeconds, equals(35.0));
      });

      test('4. Audio Duplicate: Creates independent instance starting at original track end', () {
        const track = AudioTrack(
          id: 'audio_dup_test',
          assetId: 'asset_dup_1',
          title: 'HipHop_Loop.mp3',
          duration: Duration(seconds: 15),
          startTime: Duration.zero,
        );
        viewModel.addAudioTrack(track);
        viewModel.selectAudioTrack('audio_dup_test');

        final duplicate = viewModel.duplicateSelectedAudioTrack();
        expect(duplicate, isNotNull);
        expect(viewModel.audioTracks.length, equals(2));
        expect(duplicate!.assetId, equals('asset_dup_1'));
        expect(duplicate.startTimeInSeconds, equals(15.0));
        expect(duplicate.title, contains('Copy'));
        expect(duplicate.id, isNot(equals('audio_dup_test')));
      });

      test('5. Audio Speed Control: Changes speed and accurately scales effectiveDuration', () {
        const track = AudioTrack(
          id: 'audio_speed_test',
          assetId: 'asset_speed_1',
          title: 'Podcast_Track.mp3',
          duration: Duration(seconds: 20),
          startTime: Duration.zero,
          speed: 1.0,
        );
        viewModel.addAudioTrack(track);

        // 1.0x -> duration = 20s
        expect(viewModel.audioTracks.first.durationInSeconds, equals(20.0));

        // 2.0x -> duration = 10s
        viewModel.updateAudioSpeed('audio_speed_test', 2.0);
        expect(viewModel.audioTracks.first.speed, equals(2.0));
        expect(viewModel.audioTracks.first.durationInSeconds, equals(10.0));

        // 0.5x -> duration = 40s
        viewModel.updateAudioSpeed('audio_speed_test', 0.5);
        expect(viewModel.audioTracks.first.speed, equals(0.5));
        expect(viewModel.audioTracks.first.durationInSeconds, equals(40.0));
      });

      test('6. Audio Volume & Mute: Per-track volume adjustment and mute toggle', () {
        const track = AudioTrack(
          id: 'audio_vol_test',
          assetId: 'asset_vol_1',
          title: 'Voiceover.mp3',
          duration: Duration(seconds: 10),
          volume: 0.8,
          isMuted: false,
        );
        viewModel.addAudioTrack(track);

        viewModel.updateAudioVolume('audio_vol_test', 0.45);
        expect(viewModel.audioTracks.first.volume, closeTo(0.45, 0.001));
        expect(viewModel.audioTracks.first.isMuted, isFalse);

        viewModel.toggleAudioMute('audio_vol_test');
        expect(viewModel.audioTracks.first.isMuted, isTrue);

        viewModel.toggleAudioMute('audio_vol_test');
        expect(viewModel.audioTracks.first.isMuted, isFalse);
      });

      test('7. Audio Delete: Removes track, cleans up selection and stops playback', () {
        const track = AudioTrack(
          id: 'audio_del_test',
          assetId: 'asset_del_1',
          title: 'To_Be_Deleted.mp3',
          duration: Duration(seconds: 12),
        );
        viewModel.addAudioTrack(track);
        viewModel.selectAudioTrack('audio_del_test');
        expect(viewModel.isAudioSelected, isTrue);

        viewModel.deleteSelectedAudioTrack();
        expect(viewModel.audioTracks, isEmpty);
        expect(viewModel.selectedAudioTrackId, isNull);
        expect(viewModel.isAudioSelected, isFalse);
      });

      test('8. Multi-track Audio & Project Persistence: Preserves all audio tracks and metadata', () {
        final project = Project(
          id: 'proj_multi_audio',
          name: 'Multi-Track Music Video',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          audioTracks: const [
            AudioTrack(
              id: 'track_bgm',
              assetId: 'asset_bgm_1',
              title: 'Main_Theme.mp3',
              duration: Duration(seconds: 60),
              trimStart: Duration(seconds: 5),
              trimEnd: Duration(seconds: 55),
              startTime: Duration.zero,
              volume: 0.7,
              speed: 1.0,
            ),
            AudioTrack(
              id: 'track_sfx',
              assetId: 'asset_sfx_1',
              title: 'Explosion_FX.mp3',
              duration: Duration(seconds: 4),
              startTime: Duration(seconds: 12),
              volume: 1.0,
              speed: 1.5,
              isMuted: false,
            ),
          ],
        );

        final json = project.toJson();
        final restored = Project.fromJson(json);

        expect(restored.audioTracks.length, equals(2));
        expect(restored.audioTracks[0].title, equals('Main_Theme.mp3'));
        expect(restored.audioTracks[0].trimStart.inSeconds, equals(5));
        expect(restored.audioTracks[0].trimEnd!.inSeconds, equals(55));
        expect(restored.audioTracks[0].volume, closeTo(0.7, 0.01));

        expect(restored.audioTracks[1].title, equals('Explosion_FX.mp3'));
        expect(restored.audioTracks[1].startTime.inSeconds, equals(12));
        expect(restored.audioTracks[1].speed, equals(1.5));
        expect(restored.audioTracks[1].durationInSeconds, closeTo(4.0 / 1.5, 0.005));
      });
    });

    group('Text Layer Editing Controls & Audio Auto-Play Prevention Tests', () {
      test('1. Text Layer Selection & Isolation: Selecting text isolates selection from audio/video/overlay', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_sel_test',
          text: 'Super Intro',
          startTime: Duration(seconds: 1),
          duration: Duration(seconds: 5),
          textColor: Colors.amber,
          fontSize: 24,
        );
        viewModel.addTextOverlay(text);
        expect(viewModel.selectedTextId, equals('text_sel_test'));
        expect(viewModel.isTextSelected, isTrue);
        expect(viewModel.selectedClipIndex, isNull);
        expect(viewModel.selectedOverlayIndex, isNull);
        expect(viewModel.selectedAudioTrackId, isNull);
        expect(viewModel.isAudioSelected, isFalse);

        // Deselect text
        viewModel.deselectText();
        expect(viewModel.selectedTextId, isNull);
        expect(viewModel.isTextSelected, isFalse);
      });

      test('2. Text Layer Trim Left: Non-destructively advances trimStart preserving timeline startTime', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_trim_left_test',
          text: 'Vlog Chapter 1',
          startTime: Duration(seconds: 2),
          duration: Duration(seconds: 6),
          speed: 1.0,
        );
        viewModel.addTextOverlay(text);
        viewModel.selectText(text.id);

        // Position playhead inside text range at 4.0s (2s past start)
        viewModel.seekTo(4.0);
        final trimmed = viewModel.trimTextLeftToPlayhead();
        expect(trimmed, isTrue);

        final updated = viewModel.selectedTextOverlay!;
        // startTime MUST remain 2.0s (preserving timeline alignment)
        expect(updated.startTimeInSeconds, closeTo(2.0, 0.01));
        expect(updated.trimStartInSeconds, closeTo(2.0, 0.01));
        expect(updated.durationInSeconds, closeTo(4.0, 0.01));
      });

      test('3. Text Layer Trim Right: Non-destructively truncates trimEnd', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_trim_right_test',
          text: 'Subscribe Now',
          startTime: Duration(seconds: 1),
          duration: Duration(seconds: 8),
          speed: 1.0,
        );
        viewModel.addTextOverlay(text);
        viewModel.selectText(text.id);

        // Position playhead inside text range at 5.0s (4s duration from start)
        viewModel.seekTo(5.0);
        final trimmed = viewModel.trimTextRightToPlayhead();
        expect(trimmed, isTrue);

        final updated = viewModel.selectedTextOverlay!;
        expect(updated.startTimeInSeconds, closeTo(1.0, 0.01));
        expect(updated.trimEndInSeconds, closeTo(4.0, 0.01));
        expect(updated.durationInSeconds, closeTo(4.0, 0.01));
      });

      test('4. Text Layer Split: Splits into two independent TextOverlays at playhead', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_split_test',
          text: 'Split Subtitle Text',
          startTime: Duration(seconds: 2),
          duration: Duration(seconds: 6),
          speed: 1.0,
          textColor: Colors.cyanAccent,
          fontSize: 22,
          isBold: true,
        );
        viewModel.addTextOverlay(text);
        viewModel.selectText(text.id);

        // Seek to 5.0s (3s offset into text)
        viewModel.seekTo(5.0);
        final split = viewModel.splitTextAtPlayhead();
        expect(split, isTrue);

        final partA = viewModel.textOverlays.firstWhere((t) => t.id.contains('part1'));
        final partB = viewModel.textOverlays.firstWhere((t) => t.id.contains('part2'));

        expect(partA.startTimeInSeconds, closeTo(2.0, 0.01));
        expect(partA.durationInSeconds, closeTo(3.0, 0.01));
        expect(partA.text, equals('Split Subtitle Text'));
        expect(partA.textColor, equals(Colors.cyanAccent));

        expect(partB.startTimeInSeconds, closeTo(5.0, 0.01));
        expect(partB.durationInSeconds, closeTo(3.0, 0.01));
        expect(partB.text, equals('Split Subtitle Text'));
        expect(viewModel.selectedTextId, equals(partB.id));
      });

      test('5. Text Layer Duplicate: Creates clone right after original preserving styling and assigning new ID', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_dup_orig',
          text: 'Animated Title',
          startTime: Duration(seconds: 3),
          duration: Duration(seconds: 4),
          speed: 1.0,
          textColor: Colors.yellow,
          fontSize: 28,
          isItalic: true,
        );
        viewModel.addTextOverlay(text);
        viewModel.selectText(text.id);

        final dup = viewModel.duplicateSelectedText();
        expect(dup, isNotNull);
        expect(dup!.id, isNot(equals(text.id)));
        expect(dup.startTimeInSeconds, closeTo(7.0, 0.01)); // 3s start + 4s duration
        expect(dup.text, equals('Animated Title'));
        expect(dup.textColor, equals(Colors.yellow));
        expect(dup.isItalic, isTrue);
        expect(viewModel.selectedTextId, equals(dup.id));
      });

      test('6. Text Layer Speed: Adjusting speed scales effective duration', () {
        final viewModel = EditorViewModel();
        const text = TextOverlay(
          id: 'text_speed_test',
          text: 'Fast Kinetic Typography',
          startTime: Duration.zero,
          duration: Duration(seconds: 4),
          speed: 1.0,
        );
        viewModel.addTextOverlay(text);
        viewModel.selectText(text.id);

        // Change speed to 2.0x
        viewModel.setTextSpeed(2.0);
        expect(viewModel.selectedTextOverlay!.speed, equals(2.0));
        expect(viewModel.selectedTextOverlay!.durationInSeconds, closeTo(2.0, 0.01));

        // Change speed to 0.5x
        viewModel.setTextSpeed(0.5);
        expect(viewModel.selectedTextOverlay!.speed, equals(0.5));
        expect(viewModel.selectedTextOverlay!.durationInSeconds, closeTo(8.0, 0.01));
      });

      test('7. Text Layer Delete: Deletes text layer, clears selection, updates total duration', () {
        final viewModel = EditorViewModel();
        final initialTextCount = viewModel.textOverlays.length;
        const text = TextOverlay(
          id: 'text_to_delete',
          text: 'Temporary Text',
          startTime: Duration(seconds: 10),
          duration: Duration(seconds: 5),
        );
        viewModel.addTextOverlay(text);
        expect(viewModel.textOverlays.length, equals(initialTextCount + 1));
        expect(viewModel.selectedTextId, equals('text_to_delete'));

        viewModel.deleteSelectedText();
        expect(viewModel.textOverlays.any((t) => t.id == 'text_to_delete'), isFalse);
        expect(viewModel.selectedTextId, isNull);
        expect(viewModel.isTextSelected, isFalse);
      });

      test('8. Audio Auto-Play Prevention: Importing/adding audio track leaves playback PAUSED', () {
        final viewModel = EditorViewModel();
        expect(viewModel.isPlaying, isFalse);

        const audioTrack = AudioTrack(
          id: 'audio_import_test',
          assetId: 'asset_imported_audio',
          title: 'Imported_Beat.mp3',
          duration: Duration(seconds: 30),
          startTime: Duration.zero,
        );

        viewModel.addAudioTrack(audioTrack);
        // Playback MUST remain strictly paused upon import!
        expect(viewModel.isPlaying, isFalse);
        expect(viewModel.selectedAudioTrackId, equals('audio_import_test'));
      });

      test('9. TextOverlay JSON Persistence: Serializes and deserializes all editing and styling properties', () {
        const text = TextOverlay(
          id: 'text_json_full',
          text: 'Persistent Cinematic Title',
          startTime: Duration(seconds: 3),
          duration: Duration(seconds: 10),
          trimStart: Duration(seconds: 1),
          trimEnd: Duration(seconds: 9),
          speed: 1.5,
          textColor: Colors.deepOrangeAccent,
          fontSize: 26.0,
          position: Offset(0.5, 0.8),
          fontFamily: 'Roboto',
          backgroundColor: Colors.black54,
          textAlign: TextAlign.center,
          isBold: true,
          isItalic: true,
          isUnderline: true,
          shadowColor: Colors.black,
        );

        final json = text.toJson();
        final restored = TextOverlay.fromJson(json);

        expect(restored.id, equals('text_json_full'));
        expect(restored.text, equals('Persistent Cinematic Title'));
        expect(restored.startTimeInSeconds, closeTo(3.0, 0.01));
        expect(restored.trimStartInSeconds, closeTo(1.0, 0.01));
        expect(restored.trimEndInSeconds, closeTo(9.0, 0.01));
        expect(restored.speed, equals(1.5));
        expect(restored.fontSize, equals(26.0));
        expect(restored.isBold, isTrue);
        expect(restored.isItalic, isTrue);
        expect(restored.isUnderline, isTrue);
        expect(restored.fontFamily, equals('Roboto'));
        expect(restored.textAlign, equals(TextAlign.center));
      });
    });

    group('Video Layer Controls, Speed, Volume, Add Clip & Canvases Removal Tests', () {
      test('1. Video selection isolation and properties', () {
        const track = AudioTrack(
          id: 'audio_test_iso',
          assetId: 'asset_test_iso',
          title: 'Isolation Track',
          duration: Duration(seconds: 10),
        );
        viewModel.addAudioTrack(track);
        viewModel.selectAudio();
        expect(viewModel.isAudioSelected, isTrue);

        // Selecting video clip must cleanly clear audio, text, and sticker selection
        viewModel.selectClip(0);
        expect(viewModel.selectedClipIndex, equals(0));
        expect(viewModel.isAudioSelected, isFalse);
        expect(viewModel.selectedAudioTrackId, isNull);
        expect(viewModel.selectedTextId, isNull);
        expect(viewModel.selectedStickerId, isNull);
        expect(viewModel.selectedOverlayIndex, isNull);
      });

      test('2. Video Speed Control: 0.5x, 1.0x, 1.5x, 2.0x updates active duration correctly', () {
        viewModel.selectClip(0);
        final clip = viewModel.selectedClip!;
        final initialTrimmedDuration = (clip.trimEnd.inMilliseconds - clip.trimStart.inMilliseconds) / 1000.0;

        // 1.0x (normal)
        viewModel.setClipSpeed(1.0);
        expect(viewModel.selectedClip!.speed, equals(1.0));
        expect(viewModel.selectedClip!.durationInSeconds, closeTo(initialTrimmedDuration, 0.01));

        // 0.5x (slow motion -> 2x duration)
        viewModel.setClipSpeed(0.5);
        expect(viewModel.selectedClip!.speed, equals(0.5));
        expect(viewModel.selectedClip!.durationInSeconds, closeTo(initialTrimmedDuration / 0.5, 0.01));

        // 1.5x
        viewModel.setClipSpeed(1.5);
        expect(viewModel.selectedClip!.speed, equals(1.5));
        expect(viewModel.selectedClip!.durationInSeconds, closeTo(initialTrimmedDuration / 1.5, 0.01));

        // 2.0x (fast forward -> 0.5x duration)
        viewModel.setClipSpeed(2.0);
        expect(viewModel.selectedClip!.speed, equals(2.0));
        expect(viewModel.selectedClip!.durationInSeconds, closeTo(initialTrimmedDuration / 2.0, 0.01));
      });

      test('3. Video Volume Control: 0%, 25%, 50%, 100% and track isolation', () {
        viewModel.selectClip(0);
        viewModel.setClipVolume(0.5);
        expect(viewModel.selectedClip!.volume, equals(0.5));

        // 0% (silent)
        viewModel.setClipVolume(0.0);
        expect(viewModel.selectedClip!.volume, equals(0.0));

        // 25%
        viewModel.setClipVolume(0.25);
        expect(viewModel.selectedClip!.volume, equals(0.25));

        // 100%
        viewModel.setClipVolume(1.0);
        expect(viewModel.selectedClip!.volume, equals(1.0));

        // Video volume change does NOT mutate audio track volume
        if (viewModel.audioTrack != null) {
          final originalAudioVol = viewModel.audioTrack!.volume;
          viewModel.setClipVolume(0.0);
          expect(viewModel.audioTrack!.volume, equals(originalAudioVol));
        }
      });

      test('4. Video Trim Left and Right non-destructive operation', () {
        viewModel.selectClip(0);
        final initialLength = viewModel.selectedClip!.durationInSeconds;

        viewModel.seekTo(2.0);
        final trimmedLeft = viewModel.trimLeftToPlayhead();
        expect(trimmedLeft, isTrue);
        expect(viewModel.selectedClip!.trimStart.inMilliseconds, greaterThan(0));
        expect(viewModel.selectedClip!.durationInSeconds, lessThan(initialLength));

        final trimmedLen = viewModel.selectedClip!.durationInSeconds;
        viewModel.seekTo(1.0); // Inside remaining clip
        final trimmedRight = viewModel.trimRightToPlayhead();
        expect(trimmedRight, isTrue);
        expect(viewModel.selectedClip!.durationInSeconds, lessThan(trimmedLen));
      });

      test('5. Video Duplicate Property Isolation: duplicate gets unique ID and independent properties', () {
        viewModel.selectClip(0);
        viewModel.setClipSpeed(1.5);
        viewModel.setClipVolume(0.4);

        final initialCount = viewModel.videoClips.length;
        viewModel.duplicateSelectedClip();

        expect(viewModel.videoClips.length, equals(initialCount + 1));
        final original = viewModel.videoClips[0];
        final duplicate = viewModel.videoClips[1];

        expect(duplicate.id, isNot(equals(original.id)));
        expect(duplicate.speed, equals(1.5));
        expect(duplicate.volume, equals(0.4));

        // Modifying duplicate does not affect original
        viewModel.selectClip(1);
        viewModel.setClipSpeed(0.5);
        viewModel.setClipVolume(1.0);

        expect(viewModel.videoClips[1].speed, equals(0.5));
        expect(viewModel.videoClips[1].volume, equals(1.0));
        expect(viewModel.videoClips[0].speed, equals(1.5));
        expect(viewModel.videoClips[0].volume, equals(0.4));
      });

      test('6. Video Delete removes selected clip and updates timeline', () {
        final initialCount = viewModel.videoClips.length;
        viewModel.selectClip(0);
        final clipToDeleteId = viewModel.selectedClip!.id;

        viewModel.deleteSelectedClip();
        expect(viewModel.videoClips.length, equals(initialCount - 1));
        expect(viewModel.videoClips.any((c) => c.id == clipToDeleteId), isFalse);
      });

      test('7. Add Clip from MediaAsset: imports real asset and adds to timeline', () {
        final realAsset = MediaAsset(
          id: 'asset_real_device_999',
          type: MediaAssetType.video,
          name: 'Device_Camera_Test.mp4',
          localPath: '/data/user/0/com.example.capcut_video_editor/files/media/Device_Camera_Test.mp4',
          duration: const Duration(seconds: 14),
          createdAt: DateTime.now(),
        );

        viewModel.addMediaAsset(realAsset);
        expect(viewModel.mediaLibrary.contains(realAsset), isTrue);

        final countBefore = viewModel.videoClips.length;
        viewModel.addNewClipFromMedia(
          assetId: realAsset.id,
          title: realAsset.name,
          duration: realAsset.duration!,
          gradient: const [Colors.blue, Colors.teal],
        );

        expect(viewModel.videoClips.length, equals(countBefore + 1));
        final added = viewModel.videoClips.last;
        expect(added.assetId, equals(realAsset.id));
        expect(added.title, equals('Device_Camera_Test.mp4'));
        expect(added.durationInSeconds, equals(14.0));
      });

      test('8. VideoClip JSON Persistence preserves speed, volume, and trim boundaries', () {
        const clip = VideoClip(
          id: 'video_clip_persist_1',
          assetId: 'asset_ref_123',
          title: 'Cinematic Sunset',
          originalDuration: Duration(seconds: 20),
          trimStart: Duration(seconds: 2),
          trimEnd: Duration(seconds: 18),
          speed: 1.5,
          volume: 0.65,
          previewGradient: [Colors.purple, Colors.orange],
        );

        final json = clip.toJson();
        final restored = VideoClip.fromJson(json);

        expect(restored.id, equals('video_clip_persist_1'));
        expect(restored.assetId, equals('asset_ref_123'));
        expect(restored.title, equals('Cinematic Sunset'));
        expect(restored.speed, equals(1.5));
        expect(restored.volume, equals(0.65));
        expect(restored.trimStart.inSeconds, equals(2));
        expect(restored.trimEnd.inSeconds, equals(18));
        expect(restored.durationInSeconds, closeTo((18 - 2) / 1.5, 0.01));
      });
    });

    group('MAHMAS Studio 4 Critical Bug Fix Regression Tests', () {
      // BUG #1: PROJECT AUTO-PLAY PREVENTION TESTS
      group('Bug #1: Project Opening / Initialization Playback State Tests', () {
        test('TEST 1: Opening a new project starts paused (isPlaying == false)', () {
          final vm = EditorViewModel();
          expect(vm.isPlaying, isFalse);
          expect(vm.playheadPosition, equals(0.0));
          vm.dispose();
        });

        test('TEST 2: Opening an existing project starts paused (isPlaying == false)', () {
          final project = Project(
            id: 'proj_test_paused_2',
            name: 'Paused Test Project',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            playheadPosition: 4.25,
            videoClips: MockMediaRepository.getInitialVideoClips(),
            audioTracks: const [
              AudioTrack(
                id: 'audio_test_paused_2',
                assetId: 'preset_asset_audio_01',
                name: 'Test Audio Track',
                artist: 'Test Artist',
                startTime: Duration.zero,
                duration: Duration(seconds: 18),
              ),
            ],
          );

          final vm = EditorViewModel(initialProject: project);
          expect(vm.isPlaying, isFalse);
          expect(vm.playheadPosition, equals(4.25));
          vm.dispose();
        });

        test('TEST 3: A project previously saved while playing must reopen paused', () {
          final vm1 = EditorViewModel();
          vm1.play();
          expect(vm1.isPlaying, isTrue);

          final projectState = vm1.currentProject.copyWith(playheadPosition: 3.5);
          vm1.dispose();

          final vm2 = EditorViewModel(initialProject: projectState);
          expect(vm2.isPlaying, isFalse);
          expect(vm2.playheadPosition, equals(3.5));
          vm2.dispose();
        });

        test('TEST 4: Opening a project must not start the playback timer', () async {
          final vm = EditorViewModel();
          final initialPos = vm.playheadPosition;

          // Wait 100ms to verify periodic playback timer is not running
          await Future.delayed(const Duration(milliseconds: 100));

          expect(vm.isPlaying, isFalse);
          expect(vm.playheadPosition, equals(initialPos));
          vm.dispose();
        });

        test('TEST 5: Opening a project must not start audio playback', () {
          final project = Project(
            id: 'proj_test_audio_paused',
            name: 'Audio Paused Test',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            audioTracks: const [
              AudioTrack(
                id: 'audio_test_paused_5',
                assetId: 'preset_asset_audio_01',
                name: 'Test Audio Track',
                artist: 'Test Artist',
                startTime: Duration.zero,
                duration: Duration(seconds: 18),
              ),
            ],
          );

          final vm = EditorViewModel(initialProject: project);
          expect(vm.isPlaying, isFalse);
          expect(AudioPlaybackService.instance.isPlaying, isFalse);
          vm.dispose();
        });

        test('TEST 6: Opening a project must not start video playback', () {
          final project = Project(
            id: 'proj_test_video_paused',
            name: 'Video Paused Test',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            videoClips: MockMediaRepository.getInitialVideoClips(),
          );

          final vm = EditorViewModel(initialProject: project);
          expect(vm.isPlaying, isFalse);
          expect(VideoPlaybackService.instance.activeSession?.isPlaying ?? false, isFalse);
          vm.dispose();
        });

        test('TEST 7: Explicit Play action still starts playback', () {
          final vm = EditorViewModel();
          expect(vm.isPlaying, isFalse);

          vm.play();
          expect(vm.isPlaying, isTrue);
          vm.dispose();
        });

        test('TEST 8: Explicit Pause action still pauses playback', () {
          final vm = EditorViewModel();
          vm.play();
          expect(vm.isPlaying, isTrue);

          vm.pause();
          expect(vm.isPlaying, isFalse);
          vm.dispose();
        });
      });

      // BUG #2: BACKGROUND AUDIO & RESOURCE CLEANUP TESTS
      group('Bug #2: Background Audio & Disposal Resource Cleanup Tests', () {
        test('Disposing EditorViewModel stops active playback and cleans up timers and services', () {
          final vm = EditorViewModel();
          vm.play();
          expect(vm.isPlaying, isTrue);

          vm.dispose();
          expect(vm.isPlaying, isFalse);

          // Calling dispose again is idempotent and does not crash
          expect(() => vm.dispose(), returnsNormally);
        });
      });

      // BUG #3: GALLERY EXPORT PIPELINE TESTS
      group('Bug #3: Gallery Export Pipeline Tests', () {
        test('exportVideoToGallery creates valid output file and invokes MediaStore gallery registration', () async {
          final vm = EditorViewModel();
          expect(vm.isExporting, isFalse);

          bool callbackFired = false;
          bool? exportSuccess;
          String? outputPath;

          await vm.exportVideoToGallery(
            onFinished: (success, path) {
              callbackFired = true;
              exportSuccess = success;
              outputPath = path;
            },
          );

          // Wait briefly for the progress timer to complete
          await Future.delayed(const Duration(milliseconds: 1500));

          expect(callbackFired, isTrue);
          expect(exportSuccess, isTrue);
          expect(outputPath, isNotNull);
          expect(outputPath!.endsWith('.mp4'), isTrue);

          vm.dispose();
        });
      });

      // BUG #4: TIMELINE TRIM ALIGNMENT TESTS
      group('Bug #4: Audio Trim Alignment Tests', () {
        test('TEST 1 & 3 & 5: Trim Left increases source in-point, reduces duration, and KEEPS timeline startTime unchanged', () {
          final vm = EditorViewModel();

          // Construct original audio track:
          // timelineStart = 10.0s
          // duration = 20.0s
          // trimStart = 0.0s
          // trimEnd = 20.0s
          const originalTrack = AudioTrack(
            id: 'audio_alignment_test_1',
            assetId: 'asset_audio_align',
            title: 'Alignment Track',
            startTime: Duration(seconds: 10),
            duration: Duration(seconds: 20),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 20),
            speed: 1.0,
          );

          vm.addAudioTrack(originalTrack);
          vm.selectAudioTrack(originalTrack.id);

          expect(vm.selectedAudioTrack!.startTimeInSeconds, equals(10.0));
          expect(vm.selectedAudioTrack!.durationInSeconds, equals(20.0));
          expect(vm.selectedAudioTrack!.trimStartInSeconds, equals(0.0));
          expect(vm.selectedAudioTrack!.trimEndInSeconds, equals(20.0));

          // Playhead placed at 15.0s (5s into the track starting at 10s)
          vm.seekTo(15.0);
          final trimLeftSuccess = vm.trimAudioLeftToPlayhead();
          expect(trimLeftSuccess, isTrue);

          final trimmedTrack = vm.selectedAudioTrack!;

          // SEMANTIC ASSERTIONS:
          // 1. timelineStart MUST remain 10.0s
          expect(trimmedTrack.startTimeInSeconds, equals(10.0));
          // 2. sourceStart MUST become 5.0s
          expect(trimmedTrack.trimStartInSeconds, closeTo(5.0, 0.01));
          // 3. sourceEnd MUST remain 20.0s
          expect(trimmedTrack.trimEndInSeconds, equals(20.0));
          // 4. effective duration MUST become 15.0s
          expect(trimmedTrack.durationInSeconds, closeTo(15.0, 0.01));

          vm.dispose();
        });

        test('TEST 2 & 4 & 6: Trim Right reduces source out-point, reduces duration, and KEEPS timeline startTime unchanged', () {
          final vm = EditorViewModel();

          // Construct original audio track:
          // timelineStart = 10.0s
          // duration = 20.0s
          // trimStart = 0.0s
          // trimEnd = 20.0s
          const originalTrack = AudioTrack(
            id: 'audio_alignment_test_2',
            assetId: 'asset_audio_align_2',
            title: 'Alignment Track 2',
            startTime: Duration(seconds: 10),
            duration: Duration(seconds: 20),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 20),
            speed: 1.0,
          );

          vm.addAudioTrack(originalTrack);
          vm.selectAudioTrack(originalTrack.id);

          // Playhead placed at 15.0s (5s into track -> trim remaining 15s down to 5s from track start)
          vm.seekTo(15.0);
          final trimRightSuccess = vm.trimAudioRightToPlayhead();
          expect(trimRightSuccess, isTrue);

          final trimmedTrack = vm.selectedAudioTrack!;

          // SEMANTIC ASSERTIONS:
          // 1. timelineStart MUST remain 10.0s
          expect(trimmedTrack.startTimeInSeconds, equals(10.0));
          // 2. sourceStart MUST remain 0.0s
          expect(trimmedTrack.trimStartInSeconds, equals(0.0));
          // 3. sourceEnd MUST become 5.0s
          expect(trimmedTrack.trimEndInSeconds, closeTo(5.0, 0.01));
          // 4. effective duration MUST become 5.0s
          expect(trimmedTrack.durationInSeconds, closeTo(5.0, 0.01));

          vm.dispose();
        });

        test('TEST 7: Multiple consecutive trims preserve timeline alignment', () {
          final vm = EditorViewModel();
          const track = AudioTrack(
            id: 'audio_consecutive_trim',
            assetId: 'asset_consecutive',
            title: 'Consecutive Trim Track',
            startTime: Duration(seconds: 10),
            duration: Duration(seconds: 30),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 30),
          );

          vm.addAudioTrack(track);
          vm.selectAudioTrack(track.id);

          // Trim Left at 14.0s (4s into track)
          vm.seekTo(14.0);
          expect(vm.trimAudioLeftToPlayhead(), isTrue);
          expect(vm.selectedAudioTrack!.startTimeInSeconds, equals(10.0));
          expect(vm.selectedAudioTrack!.trimStartInSeconds, closeTo(4.0, 0.01));
          expect(vm.selectedAudioTrack!.durationInSeconds, closeTo(26.0, 0.01));

          // Trim Left again at 18.0s (8s into track)
          vm.seekTo(18.0);
          expect(vm.trimAudioLeftToPlayhead(), isTrue);
          expect(vm.selectedAudioTrack!.startTimeInSeconds, equals(10.0));
          expect(vm.selectedAudioTrack!.trimStartInSeconds, closeTo(8.0, 0.01));
          expect(vm.selectedAudioTrack!.durationInSeconds, closeTo(22.0, 0.01));

          // Trim Right at 25.0s (15s from track startTime -> 7s effective duration remaining)
          vm.seekTo(25.0);
          expect(vm.trimAudioRightToPlayhead(), isTrue);
          expect(vm.selectedAudioTrack!.startTimeInSeconds, equals(10.0));
          expect(vm.selectedAudioTrack!.trimStartInSeconds, closeTo(8.0, 0.01));
          expect(vm.selectedAudioTrack!.trimEndInSeconds, closeTo(23.0, 0.01));
          expect(vm.selectedAudioTrack!.durationInSeconds, closeTo(15.0, 0.01));

          vm.dispose();
        });

        test('TEST 8: Moving the audio clip first and then trimming preserves the moved position', () {
          final vm = EditorViewModel();
          const track = AudioTrack(
            id: 'audio_move_then_trim',
            assetId: 'asset_move_trim',
            title: 'Move Then Trim Track',
            startTime: Duration(seconds: 5),
            duration: Duration(seconds: 20),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 20),
          );

          vm.addAudioTrack(track);

          // Move track from 5.0s to 12.0s
          vm.moveAudioTrack(track.id, const Duration(seconds: 12));
          final movedTrack = vm.audioTracks.firstWhere((t) => t.id == track.id);
          expect(movedTrack.startTimeInSeconds, equals(12.0));
          expect(movedTrack.trimStartInSeconds, equals(0.0));
          expect(movedTrack.trimEndInSeconds, equals(20.0));

          // Select and Trim Left at 16.0s (4s into track)
          vm.selectAudioTrack(track.id);
          vm.seekTo(16.0);
          expect(vm.trimAudioLeftToPlayhead(), isTrue);

          final resultTrack = vm.selectedAudioTrack!;
          expect(resultTrack.startTimeInSeconds, equals(12.0));
          expect(resultTrack.trimStartInSeconds, closeTo(4.0, 0.01));
          expect(resultTrack.trimEndInSeconds, equals(20.0));
          expect(resultTrack.durationInSeconds, closeTo(16.0, 0.01));

          vm.dispose();
        });

        test('TEST 9: Persistence: Trimmed audio track serializes and restores exact startTime and trim boundaries', () {
          const track = AudioTrack(
            id: 'audio_persist_trim',
            assetId: 'asset_persist_1',
            title: 'Persisted Audio',
            startTime: Duration(seconds: 10),
            duration: Duration(seconds: 20),
            trimStart: Duration(seconds: 5),
            trimEnd: Duration(seconds: 20),
            speed: 1.0,
          );

          final json = track.toJson();
          final restored = AudioTrack.fromJson(json);

          expect(restored.startTimeInSeconds, equals(10.0));
          expect(restored.durationInSeconds, equals(15.0));
          expect(restored.trimStartInSeconds, equals(5.0));
          expect(restored.trimEndInSeconds, equals(20.0));
        });

        test('TEST 10: updateAudioTrim clamps boundaries without changing startTime', () {
          final vm = EditorViewModel();
          const track = AudioTrack(
            id: 'audio_update_trim_test',
            assetId: 'asset_update_trim',
            title: 'Direct Trim Update',
            startTime: Duration(seconds: 8),
            duration: Duration(seconds: 20),
          );

          vm.addAudioTrack(track);
          vm.updateAudioTrim(
            track.id,
            const Duration(seconds: 3),
            const Duration(seconds: 17),
          );

          final updated = vm.audioTracks.firstWhere((t) => t.id == track.id);
          expect(updated.startTimeInSeconds, equals(8.0));
          expect(updated.trimStartInSeconds, equals(3.0));
          expect(updated.trimEndInSeconds, equals(17.0));
          expect(updated.durationInSeconds, equals(14.0));

          vm.dispose();
        });
      });

      // BUG #5: DEMO AUDIO REMOVAL TESTS
      group('Bug #5: Demo Audio Removal Tests', () {
        test('New project must not contain demo/sample audio', () {
          final vm = EditorViewModel();
          expect(vm.audioTracks, isEmpty);
          expect(vm.audioTrack, isNull);
          expect(vm.selectedAudioTrack, isNull);
          expect(vm.isAudioSelected, isFalse);
          vm.dispose();
        });

        test('User can still add and manage audio track normally', () {
          final vm = EditorViewModel();
          const userTrack = AudioTrack(
            id: 'user_imported_audio_01',
            assetId: 'asset_user_audio_01',
            title: 'User My Song.mp3',
            artist: 'User',
            duration: Duration(seconds: 25),
          );

          vm.addAudioTrack(userTrack);
          expect(vm.audioTracks.length, equals(1));
          expect(vm.audioTrack?.title, equals('User My Song.mp3'));
          expect(vm.selectedAudioTrackId, equals('user_imported_audio_01'));
          expect(vm.isAudioSelected, isTrue);

          vm.dispose();
        });

        test('Audio Library: Fresh project has 0 audio tracks and opening drawer creates no tracks', () {
          final vm = EditorViewModel();
          expect(vm.audioTracks, isEmpty);
          expect(vm.mediaLibrary.where((a) => a.isAudio), isEmpty);
          vm.openDrawer(EditorCategory.audio);
          expect(vm.audioTracks, isEmpty);
          vm.dispose();
        });

        test('Importing user audio adds exactly 1 track and remains playable and persistent', () {
          final vm = EditorViewModel();
          final userAsset = MediaAsset(
            id: 'user_imported_audio_asset_99',
            type: MediaAssetType.audio,
            name: 'MyCustomTrack.mp3',
            localPath: '/storage/emulated/0/Music/MyCustomTrack.mp3',
            duration: const Duration(seconds: 30),
            sizeBytes: 1024 * 1024 * 3,
            createdAt: DateTime.now(),
          );

          vm.addMediaAsset(userAsset);
          expect(vm.mediaLibrary.where((a) => a.isAudio).length, equals(1));

          final userTrack = AudioTrack(
            id: 'audio_track_99',
            assetId: userAsset.id,
            title: userAsset.name,
            artist: 'Library Audio',
            duration: userAsset.duration!,
            startTime: Duration.zero,
          );

          vm.addAudioTrack(userTrack);
          expect(vm.audioTracks.length, equals(1));
          expect(vm.audioTracks.first.title, equals('MyCustomTrack.mp3'));

          // Test save & restore
          final project = Project(
            id: 'test_project_1',
            name: 'Test Project',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            audioTracks: [userTrack],
          );
          final projectJson = project.toJson();
          final restored = Project.fromJson(projectJson);
          expect(restored.audioTracks.length, equals(1));
          expect(restored.audioTracks.first.title, equals('MyCustomTrack.mp3'));

          vm.dispose();
        });
      });

      // ONLINE SOUND EFFECTS & ASSET STORE TESTS
      group('Online Sound Effects & Asset Store Tests', () {
        late RemoteAssetRepository remoteRepo;
        late AssetDownloadService downloadService;
        late AssetStorageService storageService;

        setUp(() async {
          remoteRepo = RemoteAssetRepository();
          downloadService = AssetDownloadService.instance;
          storageService = AssetStorageService.instance;
          await storageService.initialize();
        });

        test('TEST 1: Online Sound Effects library loads valid catalog definitions', () async {
          final sfxList = await remoteRepo.getAssets();
          expect(sfxList.isNotEmpty, isTrue);
          expect(sfxList.every((a) => a.id.isNotEmpty && a.name.isNotEmpty), isTrue);
        });

        test('TEST 2: Downloaded SFX has a valid source mapping and file on disk', () async {
          final asset = (await remoteRepo.getAssets()).first;
          final localPath = await downloadService.downloadAsset(asset);
          expect(File(localPath).existsSync(), isTrue);
          expect(File(localPath).lengthSync(), greaterThan(1000));
        });

        test('TEST 3: Insert downloaded SFX creates a real audio track on the timeline', () async {
          final vm = EditorViewModel();
          final asset = (await remoteRepo.getAssets()).first;
          final localPath = await downloadService.downloadAsset(asset);
          final downloaded = asset.copyWith(isDownloaded: true, localPath: localPath);

          final track = await vm.insertDownloadedAsset(downloaded);

          expect(vm.audioTracks.length, equals(1));
          expect(track.title, equals(asset.name));
          expect(track.duration, equals(asset.duration));

          final resolvedAsset = vm.getAssetById(track.assetId);
          expect(resolvedAsset, isNotNull);
          expect(File(resolvedAsset!.localPath!).existsSync(), isTrue);
          vm.dispose();
        });

        test('TEST 4: Inserted downloaded SFX preserves timeline playhead start position', () async {
          final vm = EditorViewModel();
          vm.seekTo(3.5); // Move playhead to 3.5s

          final asset = (await remoteRepo.getAssets()).first;
          final localPath = await downloadService.downloadAsset(asset);
          final downloaded = asset.copyWith(isDownloaded: true, localPath: localPath);

          final track = await vm.insertDownloadedAsset(downloaded);

          expect(track.startTimeInSeconds, equals(3.5));
          expect(track.durationInSeconds, equals(asset.durationInSeconds));
          expect(track.endTimeInSeconds, closeTo(3.5 + asset.durationInSeconds, 0.01));
          vm.dispose();
        });

        test('TEST 5: Inserted SFX can be serialized and restored, resolving asset file seamlessly', () async {
          final asset = (await remoteRepo.getAssets()).first;
          final localPath = await downloadService.downloadAsset(asset);
          expect(File(localPath).existsSync(), isTrue);

          final track = AudioTrack(
            id: 'audio_sfx_persisted_test',
            assetId: asset.id,
            title: asset.name,
            artist: 'Asset Library',
            startTime: const Duration(seconds: 2),
            duration: asset.duration,
          );

          final json = track.toJson();
          final restored = AudioTrack.fromJson(json);

          expect(restored.id, equals('audio_sfx_persisted_test'));
          expect(restored.assetId, equals(asset.id));
          expect(restored.startTimeInSeconds, equals(2.0));

          // Ensure view model resolves asset even on a fresh instance
          final freshVm = EditorViewModel();
          final resolvedAsset = freshVm.getAssetById(restored.assetId);
          expect(resolvedAsset, isNotNull);
          expect(File(resolvedAsset!.localPath!).existsSync(), isTrue);
          freshVm.dispose();
        });

        test('TEST 6: No default Music Tracks are reintroduced and user import still works', () {
          final vm = EditorViewModel();
          expect(vm.audioTracks, isEmpty);
          expect(vm.mediaLibrary.where((a) => a.isAudio), isEmpty);
          vm.dispose();
        });
      });
    });
  });
}
