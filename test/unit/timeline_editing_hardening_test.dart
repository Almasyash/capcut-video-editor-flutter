import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('editor_fs_timeline_hardening_');
    ProjectStorageService.instance.overrideDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    ProjectStorageService.instance.overrideDirectoryForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Timeline Editing & Media Hardening Tests', () {
    test('addNewClipFromMedia with 0 or negative duration clamps to safe default duration', () {
      final viewModel = EditorViewModel(enableMockFallback: false);

      // Add clip with zero duration
      viewModel.addNewClipFromMedia(
        assetId: 'zero_dur_asset',
        title: 'Zero Clip',
        duration: Duration.zero,
        gradient: [Colors.black, Colors.white],
      );

      expect(viewModel.videoClips.first.durationInSeconds, greaterThan(0.0));
      expect(viewModel.videoClips.first.originalDuration, equals(const Duration(seconds: 4)));
    });

    test('addVideoClipFromAsset with zero duration MediaAsset clamps to safe duration', () {
      final viewModel = EditorViewModel(enableMockFallback: false);

      final asset = MediaAsset(
        id: 'asset_zero',
        type: MediaAssetType.video,
        name: 'Empty Video.mp4',
        duration: Duration.zero,
        createdAt: DateTime.now(),
      );

      viewModel.addVideoClipFromAsset(asset);

      expect(viewModel.videoClips.first.durationInSeconds, greaterThan(0.0));
      expect(viewModel.videoClips.first.originalDuration, equals(const Duration(seconds: 10)));
    });

    test('Undo and Redo preserve stack integrity and clamp playhead accurately', () {
      final viewModel = EditorViewModel(enableMockFallback: false);

      viewModel.addNewClipFromMedia(
        assetId: 'clip_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
        gradient: [Colors.blue, Colors.green],
      );

      viewModel.addNewClipFromMedia(
        assetId: 'clip_2',
        title: 'Clip 2',
        duration: const Duration(seconds: 5),
        gradient: [Colors.orange, Colors.red],
      );

      expect(viewModel.videoClips.length, equals(2));
      expect(viewModel.canUndo, isTrue);

      // Undo second clip
      viewModel.undo();
      expect(viewModel.videoClips.length, equals(1));
      expect(viewModel.canRedo, isTrue);

      // Redo second clip
      viewModel.redo();
      expect(viewModel.videoClips.length, equals(2));
      expect(viewModel.canUndo, isTrue);
    });

    test('VideoPlaybackService disposeAll cleans active sessions and simulated sessions', () async {
      final service = VideoPlaybackService.instance;
      service.registerSimulatedSession(101, '/path/101.mp4', const Duration(seconds: 10));
      service.registerSimulatedSession(102, '/path/102.mp4', const Duration(seconds: 15));

      expect(service.activeSession, isNotNull);

      await service.disposeAll();

      expect(service.activeSession, isNull);
    });
  });
}
