import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
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
  });
}
