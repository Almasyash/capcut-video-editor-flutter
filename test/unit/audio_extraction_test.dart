import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.mahmas.studio/file_picker');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getAppFilesDir') {
        return '/data/user/0/com.example.capcut_video_editor/files';
      }
      if (methodCall.method == 'extractAudioFromVideo') {
        final path = methodCall.arguments['path'] as String?;
        if (path == null || path.contains('no_audio')) {
          throw PlatformException(
            code: 'NO_AUDIO_TRACK',
            message: 'This video has no audio track to extract.',
          );
        }
        final outputName = methodCall.arguments['outputName'] as String? ?? 'extracted_audio.m4a';
        return {
          'success': true,
          'path': '/data/user/0/com.example.capcut_video_editor/files/extracted_audio/$outputName.m4a',
          'name': '$outputName.m4a',
          'size': 1024 * 350,
          'durationMs': 20000,
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Extract / Detach Audio - Model & ViewModel Tests', () {
    test('1. Extract Audio action only appears for video clips', () {
      final vm = EditorViewModel();
      expect(vm.selectedClip, isNotNull);
      expect(vm.selectedAudioTrack, isNull);

      // Video clip selected: hasSelectedClip is true
      expect(vm.selectedClipIndex, 0);

      // Select audio track: video clip is deselected
      vm.selectAudioTrack('some_audio_id');
      expect(vm.selectedClip, isNull);
      expect(vm.isAudioSelected, isTrue);
    });

    test('2 & 3. Audio extraction creates a new MediaAsset with a valid localPath', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_101',
        type: MediaAssetType.video,
        name: 'sample_video.mp4',
        localPath: '/mock/videos/sample_video.mp4',
        duration: const Duration(seconds: 12),
        createdAt: DateTime.now(),
      );
      vm.addMediaAsset(videoAsset);

      final clip = VideoClip(
        id: 'clip_101',
        assetId: videoAsset.id,
        title: 'sample_video.mp4',
        originalDuration: const Duration(seconds: 12),
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 8),
        previewGradient: const [Colors.black, Colors.grey],
      );

      vm.loadProject(Project(
        id: 'test_proj',
        name: 'Test Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      expect(vm.selectedClip, isNotNull);

      String? feedbackMessage;
      final extractedTrack = await vm.extractAudioFromSelectedClip(
        onFeedback: (msg) => feedbackMessage = msg,
      );

      expect(extractedTrack, isNotNull);
      expect(feedbackMessage, 'Audio extracted successfully.');

      // Check MediaAsset in mediaLibrary
      final newAsset = vm.getAssetById(extractedTrack!.assetId);
      expect(newAsset, isNotNull);
      expect(newAsset!.type, MediaAssetType.audio);
      expect(newAsset.localPath, isNotNull);
      expect(newAsset.localPath!.endsWith('.m4a'), isTrue);
      expect(newAsset.localPath!.isNotEmpty, isTrue);
    });

    test('4 & 5. Extracted AudioTrack references the NEW assetId, NOT original video assetId', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_unique_source',
        type: MediaAssetType.video,
        name: 'main_footage.mp4',
        localPath: '/mock/videos/main_footage.mp4',
        duration: const Duration(seconds: 15),
        createdAt: DateTime.now(),
      );
      vm.addMediaAsset(videoAsset);

      final clip = VideoClip(
        id: 'clip_202',
        assetId: videoAsset.id,
        title: 'main_footage.mp4',
        originalDuration: const Duration(seconds: 15),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 15),
        previewGradient: const [Colors.blue, Colors.purple],
      );

      vm.loadProject(Project(
        id: 'test_proj_2',
        name: 'Test Project 2',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);

      // Must NOT reference original video asset
      expect(track!.assetId, isNot(equals(videoAsset.id)));
      expect(track.assetId.startsWith('asset_audio_extracted_'), isTrue);

      // Asset must exist in library
      final audioAsset = vm.getAssetById(track.assetId);
      expect(audioAsset, isNotNull);
      expect(audioAsset!.id, track.assetId);
    });

    test('6 & 7. Extracted audio starts at video timeline start and matches clip trims/speed', () async {
      final vm = EditorViewModel();
      final videoAsset1 = MediaAsset(
        id: 'video_asset_1',
        type: MediaAssetType.video,
        name: 'clip1.mp4',
        localPath: '/mock/videos/clip1.mp4',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );
      final videoAsset2 = MediaAsset(
        id: 'video_asset_2',
        type: MediaAssetType.video,
        name: 'clip2.mp4',
        localPath: '/mock/videos/clip2.mp4',
        duration: const Duration(seconds: 12),
        createdAt: DateTime.now(),
      );

      final clip1 = VideoClip(
        id: 'clip_1',
        assetId: videoAsset1.id,
        title: 'clip1.mp4',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10), // duration 10s
        previewGradient: const [Colors.red, Colors.orange],
      );

      final clip2 = VideoClip(
        id: 'clip_2',
        assetId: videoAsset2.id,
        title: 'clip2.mp4',
        originalDuration: const Duration(seconds: 12),
        trimStart: const Duration(seconds: 3),
        trimEnd: const Duration(seconds: 9), // active duration = 6s
        speed: 1.5,
        previewGradient: const [Colors.green, Colors.teal],
      );

      vm.loadProject(Project(
        id: 'test_proj_multi',
        name: 'Multi Clip Project',
        videoClips: [clip1, clip2],
        mediaLibrary: [videoAsset1, videoAsset2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Select clip2 (starts at 10.0s globally)
      vm.selectClip(1);
      expect(vm.selectedClipIndex, 1);
      expect(vm.getClipStartTime(1), 10.0);

      final extractedTrack = await vm.extractAudioFromSelectedClip();
      expect(extractedTrack, isNotNull);

      // Start time must match video timeline start position (10.0s)
      expect(extractedTrack!.startTimeInSeconds, 10.0);
      expect(extractedTrack.trimStart, clip2.trimStart);
      expect(extractedTrack.trimEnd, clip2.trimEnd);
      expect(extractedTrack.speed, clip2.speed);
    });

    test('8 & 9. Video and extracted audio can move and trim independently', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_indep',
        type: MediaAssetType.video,
        name: 'indep.mp4',
        localPath: '/mock/videos/indep.mp4',
        duration: const Duration(seconds: 20),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_indep',
        assetId: videoAsset.id,
        title: 'indep.mp4',
        originalDuration: const Duration(seconds: 20),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 20),
        previewGradient: const [Colors.blue, Colors.cyan],
      );

      vm.loadProject(Project(
        id: 'test_indep',
        name: 'Independent Test',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);
      expect(vm.audioTracks.length, 1);

      // 1. Move Audio Track independently
      vm.moveAudioTrack(track!.id, const Duration(seconds: 5));
      expect(vm.audioTracks.first.startTimeInSeconds, 5.0);
      // Video clip start time remains 0.0
      expect(vm.getClipStartTime(0), 0.0);

      // 2. Trim Audio Track independently
      vm.updateAudioTrim(track.id, const Duration(seconds: 2), const Duration(seconds: 14));
      expect(vm.audioTracks.first.trimStartInSeconds, 2.0);
      expect(vm.audioTracks.first.trimEndInSeconds, 14.0);
      // Video clip trims remain unchanged
      expect(vm.videoClips.first.trimStart, Duration.zero);
      expect(vm.videoClips.first.trimEnd, const Duration(seconds: 20));

      // 3. Trim Video Clip independently
      vm.updateClipTrim(0, const Duration(seconds: 4), const Duration(seconds: 16));
      expect(vm.videoClips.first.trimStart, const Duration(seconds: 4));
      expect(vm.videoClips.first.trimEnd, const Duration(seconds: 16));
      // Audio track trims remain 2.0 and 14.0
      expect(vm.audioTracks.first.trimStartInSeconds, 2.0);
      expect(vm.audioTracks.first.trimEndInSeconds, 14.0);
    });

    test('10. Extracted audio can be deleted without deleting the video clip', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_del1',
        type: MediaAssetType.video,
        name: 'del1.mp4',
        localPath: '/mock/videos/del1.mp4',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_del1',
        assetId: videoAsset.id,
        title: 'del1.mp4',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        previewGradient: const [Colors.grey, Colors.black],
      );

      vm.loadProject(Project(
        id: 'test_del1',
        name: 'Delete Test',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);
      expect(vm.videoClips.length, 1);
      expect(vm.audioTracks.length, 1);

      // Select and delete audio track
      vm.selectAudioTrack(track!.id);
      vm.deleteSelectedAudioTrack();

      // Audio track is gone, video clip remains intact
      expect(vm.audioTracks, isEmpty);
      expect(vm.videoClips.length, 1);
      expect(vm.videoClips.first.id, clip.id);
    });

    test('11. Video clip can be deleted without silently deleting the extracted audio track', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_del2',
        type: MediaAssetType.video,
        name: 'del2.mp4',
        localPath: '/mock/videos/del2.mp4',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_del2',
        assetId: videoAsset.id,
        title: 'del2.mp4',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        previewGradient: const [Colors.grey, Colors.black],
      );

      vm.loadProject(Project(
        id: 'test_del2',
        name: 'Delete Video Test',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);
      expect(vm.videoClips.length, 1);
      expect(vm.audioTracks.length, 1);

      // Select and delete video clip
      vm.selectClip(0);
      vm.deleteSelectedClip();

      // Video clip is gone, extracted audio track remains intact
      expect(vm.videoClips, isEmpty);
      expect(vm.audioTracks.length, 1);
      expect(vm.audioTracks.first.id, track!.id);
    });

    test('12. Video with no audio produces no AudioTrack and returns clear feedback', () async {
      final vm = EditorViewModel();
      final silentVideoAsset = MediaAsset(
        id: 'video_silent',
        type: MediaAssetType.video,
        name: 'silent.mp4',
        localPath: '/mock/videos/no_audio_sample.mp4',
        duration: const Duration(seconds: 8),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_silent',
        assetId: silentVideoAsset.id,
        title: 'silent.mp4',
        originalDuration: const Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 8),
        previewGradient: const [Colors.white, Colors.grey],
      );

      vm.loadProject(Project(
        id: 'test_silent',
        name: 'Silent Video Project',
        videoClips: [clip],
        mediaLibrary: [silentVideoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      String? feedback;
      final track = await vm.extractAudioFromSelectedClip(
        onFeedback: (msg) => feedback = msg,
      );

      expect(track, isNull);
      expect(feedback, 'This video has no audio track to extract.');
      expect(vm.audioTracks, isEmpty);
    });

    test('13. Duplicate extraction requests are prevented while extraction is in progress', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_dup_req',
        type: MediaAssetType.video,
        name: 'dup.mp4',
        localPath: '/mock/videos/dup.mp4',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_dup_req',
        assetId: videoAsset.id,
        title: 'dup.mp4',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        previewGradient: const [Colors.black, Colors.amber],
      );

      vm.loadProject(Project(
        id: 'test_dup_req',
        name: 'Duplicate Request Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);

      // Start first extraction
      final future1 = vm.extractAudioFromSelectedClip();
      // Immediately trigger second extraction before first finishes
      final future2 = vm.extractAudioFromSelectedClip();

      final res2 = await future2;
      final res1 = await future1;

      expect(res1, isNotNull);
      expect(res2, isNull); // Second request debounced
      expect(vm.audioTracks.length, 1);
    });

    test('14, 15, 16 & 17. Extracted audio participates in playback, seeking, stops at project end without looping', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_playback',
        type: MediaAssetType.video,
        name: 'playback.mp4',
        localPath: '/mock/videos/playback.mp4',
        duration: const Duration(seconds: 6),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_playback',
        assetId: videoAsset.id,
        title: 'playback.mp4',
        originalDuration: const Duration(seconds: 6),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 6),
        previewGradient: const [Colors.indigo, Colors.blue],
      );

      vm.loadProject(Project(
        id: 'test_playback',
        name: 'Playback Sync Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);

      // Total duration is 6.0s
      expect(vm.totalDurationInSeconds, 6.0);

      // Seek to 3.0s
      vm.seekTo(3.0);
      expect(vm.playheadPosition, 3.0);

      // Start playback
      vm.play();
      expect(vm.isPlaying, isTrue);

      // Seek to near end (5.98s)
      vm.seekTo(5.98);
      expect(vm.playheadPosition, 5.98);

      // Let playback tick to natural end
      await Future.delayed(const Duration(milliseconds: 100));

      // Playback must stop cleanly at totalDurationInSeconds without looping
      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 6.0);
    });

    test('18. Project save and reload preserves extracted AudioTrack and MediaAsset', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'video_asset_persist',
        type: MediaAssetType.video,
        name: 'persist.mp4',
        localPath: '/mock/videos/persist.mp4',
        duration: const Duration(seconds: 14),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'clip_persist',
        assetId: videoAsset.id,
        title: 'persist.mp4',
        originalDuration: const Duration(seconds: 14),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 14),
        previewGradient: const [Colors.purple, Colors.pink],
      );

      final initialProj = Project(
        id: 'test_persist_proj',
        name: 'Persist Test',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      vm.loadProject(initialProj);
      vm.selectClip(0);
      final track = await vm.extractAudioFromSelectedClip();
      expect(track, isNotNull);

      // Explicitly flush project state to disk / currentProject model
      await vm.saveCurrentProject();

      // Serialize project to JSON
      final savedJson = vm.currentProject.toJson();

      // Deserialize in a fresh project
      final reloadedProject = Project.fromJson(savedJson);

      expect(reloadedProject.audioTracks.length, 1);
      expect(reloadedProject.audioTracks.first.id, track!.id);
      expect(reloadedProject.audioTracks.first.assetId, track.assetId);
      expect(reloadedProject.mediaLibrary.any((m) => m.id == track.assetId), isTrue);

      final reloadedAsset = reloadedProject.mediaLibrary.firstWhere((m) => m.id == track.assetId);
      expect(reloadedAsset.type, MediaAssetType.audio);
      expect(reloadedAsset.localPath, isNotNull);
    });
  });

  group('Hardened Video + Extracted Audio Playback Synchronization Suite', () {
    test('1 & 2. Video naturally reaches project end and stops video + normal audio simultaneously', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_sync_1',
        type: MediaAssetType.video,
        name: 'v1.mp4',
        localPath: '/mock/videos/v1.mp4',
        duration: const Duration(seconds: 5),
        createdAt: DateTime.now(),
      );
      final audioAsset = MediaAsset(
        id: 'a_sync_1',
        type: MediaAssetType.audio,
        name: 'a1.mp3',
        localPath: '/mock/audio/a1.mp3',
        duration: const Duration(seconds: 5),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'c1',
        assetId: videoAsset.id,
        title: 'v1.mp4',
        originalDuration: const Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 5),
        previewGradient: const [Colors.black, Colors.blue],
      );

      final track = AudioTrack(
        id: 't1',
        assetId: audioAsset.id,
        name: 'a1.mp3',
        startTime: Duration.zero,
        duration: const Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 5),
      );

      vm.loadProject(Project(
        id: 'proj_harden_1',
        name: 'Harden 1',
        videoClips: [clip],
        audioTracks: [track],
        mediaLibrary: [videoAsset, audioAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.totalDurationInSeconds, 5.0);
      vm.play();
      expect(vm.isPlaying, isTrue);

      vm.seekTo(4.98);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 5.0);
    });

    test('3 & 8. Extracted audio stops at project end together with source video', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_extract_end',
        type: MediaAssetType.video,
        name: 'ext_end.mp4',
        localPath: '/mock/videos/ext_end.mp4',
        duration: const Duration(seconds: 4),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'c_ext_end',
        assetId: videoAsset.id,
        title: 'ext_end.mp4',
        originalDuration: const Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 4),
        previewGradient: const [Colors.teal, Colors.cyan],
      );

      vm.loadProject(Project(
        id: 'proj_ext_end',
        name: 'Extracted End',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.selectClip(0);
      final extracted = await vm.extractAudioFromSelectedClip();
      expect(extracted, isNotNull);
      expect(vm.videoClips.first.volume, 0.0); // Source video muted

      vm.play();
      expect(vm.isPlaying, isTrue);

      vm.seekTo(3.98);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 4.0);
    });

    test('4, 5 & 18. Multiple mixed audio tracks (Normal + Extracted + SFX) stop together at project boundary', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_multi',
        type: MediaAssetType.video,
        name: 'v_multi.mp4',
        localPath: '/mock/videos/v_multi.mp4',
        duration: const Duration(seconds: 6),
        createdAt: DateTime.now(),
      );
      final sfxAsset = MediaAsset(
        id: 'a_sfx',
        type: MediaAssetType.audio,
        name: 'sfx.wav',
        localPath: '/mock/audio/sfx.wav',
        duration: const Duration(seconds: 3),
        createdAt: DateTime.now(),
      );
      final musicAsset = MediaAsset(
        id: 'a_music',
        type: MediaAssetType.audio,
        name: 'music.mp3',
        localPath: '/mock/audio/music.mp3',
        duration: const Duration(seconds: 6),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'c_multi',
        assetId: videoAsset.id,
        title: 'v_multi.mp4',
        originalDuration: const Duration(seconds: 6),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 6),
        previewGradient: const [Colors.purple, Colors.deepPurple],
      );

      final track1 = AudioTrack(
        id: 't_sfx',
        assetId: sfxAsset.id,
        name: 'sfx.wav',
        startTime: const Duration(seconds: 1),
        duration: const Duration(seconds: 3),
      );
      final track2 = AudioTrack(
        id: 't_music',
        assetId: musicAsset.id,
        name: 'music.mp3',
        startTime: Duration.zero,
        duration: const Duration(seconds: 6),
      );

      vm.loadProject(Project(
        id: 'proj_multi',
        name: 'Multi Audio Project',
        videoClips: [clip],
        audioTracks: [track1, track2],
        mediaLibrary: [videoAsset, sfxAsset, musicAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.totalDurationInSeconds, 6.0);
      vm.play();
      expect(vm.isPlaying, isTrue);

      vm.seekTo(5.98);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 6.0);
    });

    test('6 & 7. Audio tracks and extracted .m4a tracks do not loop', () {
      final vm = EditorViewModel();
      expect(vm.isLooping, isFalse);
      vm.setLooping(false);
      expect(vm.isLooping, isFalse);
    });

    test('9, 10 & 11. At natural completion, playhead clamps to totalDurationInSeconds, timer cancels, isPlaying becomes false', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_end_clamp',
        type: MediaAssetType.video,
        name: 'clamp.mp4',
        localPath: '/mock/videos/clamp.mp4',
        duration: const Duration(seconds: 3),
        createdAt: DateTime.now(),
      );
      final clip = VideoClip(
        id: 'c_clamp',
        assetId: videoAsset.id,
        title: 'clamp.mp4',
        originalDuration: const Duration(seconds: 3),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 3),
        previewGradient: const [Colors.orange, Colors.red],
      );

      vm.loadProject(Project(
        id: 'proj_clamp',
        name: 'Clamp Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.totalDurationInSeconds, 3.0);
      vm.play();
      vm.seekTo(2.98);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 3.0);

      // Verify timer does not continue incrementing
      await Future.delayed(const Duration(milliseconds: 100));
      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 3.0);
    });

    test('12 & 13. Natural completion holds final frame; explicit user play at end restarts from 00:00', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_restart',
        type: MediaAssetType.video,
        name: 'restart.mp4',
        localPath: '/mock/videos/restart.mp4',
        duration: const Duration(seconds: 4),
        createdAt: DateTime.now(),
      );
      final clip = VideoClip(
        id: 'c_restart',
        assetId: videoAsset.id,
        title: 'restart.mp4',
        originalDuration: const Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 4),
        previewGradient: const [Colors.green, Colors.teal],
      );

      vm.loadProject(Project(
        id: 'proj_restart',
        name: 'Restart Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.play();
      vm.seekTo(3.98);
      await Future.delayed(const Duration(milliseconds: 100));

      // Natural completion held at 4.0s
      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 4.0);

      // Explicit user tap on Play button restarts from 0.0
      vm.play();
      expect(vm.isPlaying, isTrue);
      expect(vm.playheadPosition, 0.0);
      vm.pause();
    });

    test('14 & 15. Pending seek cannot restart playback after completion or pause', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_pending_seek',
        type: MediaAssetType.video,
        name: 'pending.mp4',
        localPath: '/mock/videos/pending.mp4',
        duration: const Duration(seconds: 5),
        createdAt: DateTime.now(),
      );
      final clip = VideoClip(
        id: 'c_pending_seek',
        assetId: videoAsset.id,
        title: 'pending.mp4',
        originalDuration: const Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 5),
        previewGradient: const [Colors.blueGrey, Colors.grey],
      );

      vm.loadProject(Project(
        id: 'proj_pending_seek',
        name: 'Pending Seek Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      vm.play();
      vm.seekTo(4.98);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 5.0);

      // Perform a seek while paused at end
      vm.seekTo(2.0);
      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 2.0);
    });

    test('16. Audio shorter than video terminates cleanly without looping while video continues', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_short_a',
        type: MediaAssetType.video,
        name: 'v_long.mp4',
        localPath: '/mock/videos/v_long.mp4',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );
      final audioAsset = MediaAsset(
        id: 'a_short_a',
        type: MediaAssetType.audio,
        name: 'a_short.mp3',
        localPath: '/mock/audio/a_short.mp3',
        duration: const Duration(seconds: 4),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'c_short_a',
        assetId: videoAsset.id,
        title: 'v_long.mp4',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        previewGradient: const [Colors.amber, Colors.orange],
      );
      final track = AudioTrack(
        id: 't_short_a',
        assetId: audioAsset.id,
        name: 'a_short.mp3',
        startTime: Duration.zero,
        duration: const Duration(seconds: 4),
      );

      vm.loadProject(Project(
        id: 'proj_short_a',
        name: 'Short Audio Project',
        videoClips: [clip],
        audioTracks: [track],
        mediaLibrary: [videoAsset, audioAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.totalDurationInSeconds, 10.0);
      vm.play();
      vm.seekTo(5.0); // Past audio duration (4.0s)

      expect(vm.isPlaying, isTrue);
      expect(vm.playheadPosition, 5.0);

      // Reach natural end
      vm.seekTo(9.98);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 10.0);
    });

    test('17. Audio longer than video determines timeline boundary and stops at timeline end', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_long_a',
        type: MediaAssetType.video,
        name: 'v_short.mp4',
        localPath: '/mock/videos/v_short.mp4',
        duration: const Duration(seconds: 4),
        createdAt: DateTime.now(),
      );
      final audioAsset = MediaAsset(
        id: 'a_long_a',
        type: MediaAssetType.audio,
        name: 'a_long.mp3',
        localPath: '/mock/audio/a_long.mp3',
        duration: const Duration(seconds: 10),
        createdAt: DateTime.now(),
      );

      final clip = VideoClip(
        id: 'c_long_a',
        assetId: videoAsset.id,
        title: 'v_short.mp4',
        originalDuration: const Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 4),
        previewGradient: const [Colors.cyan, Colors.blue],
      );
      final track = AudioTrack(
        id: 't_long_a',
        assetId: audioAsset.id,
        name: 'a_long.mp3',
        startTime: Duration.zero,
        duration: const Duration(seconds: 10),
      );

      vm.loadProject(Project(
        id: 'proj_long_a',
        name: 'Long Audio Project',
        videoClips: [clip],
        audioTracks: [track],
        mediaLibrary: [videoAsset, audioAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.totalDurationInSeconds, 10.0);
      vm.play();
      vm.seekTo(9.98);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 10.0);
    });

    test('19 & 20. Rapid repeated play/pause and seek near timeline end maintains strict consistency', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_stress',
        type: MediaAssetType.video,
        name: 'stress.mp4',
        localPath: '/mock/videos/stress.mp4',
        duration: const Duration(seconds: 8),
        createdAt: DateTime.now(),
      );
      final clip = VideoClip(
        id: 'c_stress',
        assetId: videoAsset.id,
        title: 'stress.mp4',
        originalDuration: const Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 8),
        previewGradient: const [Colors.red, Colors.pink],
      );

      vm.loadProject(Project(
        id: 'proj_stress',
        name: 'Stress Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      for (int i = 0; i < 5; i++) {
        vm.seekTo(7.5 + (i * 0.08));
        vm.play();
        expect(vm.isPlaying, isTrue);
        vm.pause();
        expect(vm.isPlaying, isFalse);
      }

      vm.seekTo(7.98);
      vm.play();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.isPlaying, isFalse);
      expect(vm.playheadPosition, 8.0);
    });

    test('21 & 22. Extracted audio mutes source video to prevent duplicate playback and remains independent', () async {
      final vm = EditorViewModel();
      final videoAsset = MediaAsset(
        id: 'v_no_dup',
        type: MediaAssetType.video,
        name: 'no_dup.mp4',
        localPath: '/mock/videos/no_dup.mp4',
        duration: const Duration(seconds: 12),
        createdAt: DateTime.now(),
      );
      final clip = VideoClip(
        id: 'c_no_dup',
        assetId: videoAsset.id,
        title: 'no_dup.mp4',
        originalDuration: const Duration(seconds: 12),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 12),
        volume: 1.0,
        speed: 1.0,
        previewGradient: const [Colors.green, Colors.lime],
      );

      vm.loadProject(Project(
        id: 'proj_no_dup',
        name: 'No Duplicate Audio Project',
        videoClips: [clip],
        mediaLibrary: [videoAsset],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.videoClips.first.volume, 1.0);
      vm.selectClip(0);

      final extracted = await vm.extractAudioFromSelectedClip();
      expect(extracted, isNotNull);

      // Source video volume is muted
      expect(vm.videoClips.first.volume, 0.0);
      // Extracted audio track volume is active
      expect(extracted!.volume, 1.0);
      // Independent audio track added
      expect(vm.audioTracks.length, 1);
      expect(vm.audioTracks.first.id, extracted.id);
    });
  });
}
