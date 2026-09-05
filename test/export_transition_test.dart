import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STEP 29B — Transition Export Engine Tests', () {
    late VideoClip clip1;
    late VideoClip clip2;
    late MediaAsset asset1;
    late MediaAsset asset2;
    late AudioTrack audioTrack1;

    setUp(() {
      clip1 = const VideoClip(
        id: 'clip_alpha',
        assetId: 'asset_alpha',
        title: 'Clip Alpha',
        originalDuration: Duration(seconds: 6),
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(seconds: 5), // active: 4s
        speed: 1.0,
        volume: 0.9,
        rotationDegrees: 90,
        flipHorizontal: true,
        previewGradient: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      );

      clip2 = const VideoClip(
        id: 'clip_beta',
        assetId: 'asset_beta',
        title: 'Clip Beta',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 8),
        speed: 2.0, // active: 4s
        volume: 0.8,
        previewGradient: [Color(0xFFFC466B), Color(0xFF3F5EFB)],
      );

      asset1 = MediaAsset(
        id: 'asset_alpha',
        type: MediaAssetType.video,
        name: 'video_alpha.mp4',
        createdAt: DateTime.now(),
      );

      asset2 = MediaAsset(
        id: 'asset_beta',
        type: MediaAssetType.video,
        name: 'video_beta.mp4',
        createdAt: DateTime.now(),
      );

      audioTrack1 = const AudioTrack(
        id: 'bgm_1',
        assetId: 'asset_bgm',
        name: 'Soundtrack',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 30),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 12),
        volume: 0.7,
      );
    });

    test('DeviceMediaService.renderAndExportVideo produces valid MP4 container with transitions', () async {
      final transition = Transition(
        type: TransitionType.slideLeft,
        duration: 1.5,
        leftClipId: 'clip_alpha',
        rightClipId: 'clip_beta',
      );

      final project = Project(
        id: 'export_proj_1',
        name: 'Export Test 1',
        videoClips: [clip1, clip2],
        transitions: [transition],
        audioTracks: [audioTrack1],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      const settings = ExportSettings(
        resolution: ExportResolution.res1080p,
        fps: ExportFps.fps30,
      );

      final progressValues = <double>[];
      final result = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: settings,
        assets: [asset1, asset2],
        onProgress: (p) => progressValues.add(p),
      );

      expect(result['success'], isTrue);
      expect(result['path'], isNotNull);
      final outPath = result['path'] as String;

      final file = File(outPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));

      // Check valid ISO MP4 header bytes (ftyp isom)
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(32));
      // ftyp signature
      expect(bytes[4], 0x66); // 'f'
      expect(bytes[5], 0x74); // 't'
      expect(bytes[6], 0x79); // 'y'
      expect(bytes[7], 0x70); // 'p'

      expect(progressValues, isNotEmpty);
      expect(progressValues.last, 1.0);
    });

    test('All 12 TransitionTypes are supported in export without error', () async {
      for (final type in TransitionType.values) {
        final transition = Transition(
          type: type,
          duration: 1.0,
          leftClipId: 'clip_alpha',
          rightClipId: 'clip_beta',
        );

        final project = Project(
          id: 'test_type_${type.name}',
          name: 'Test ${type.name}',
          videoClips: [clip1, clip2],
          transitions: [transition],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final result = await DeviceMediaService.renderAndExportVideo(
          project: project,
          settings: const ExportSettings(),
          assets: [asset1, asset2],
          outputFileName: 'test_${type.name}.mp4',
        );

        expect(result['success'], isTrue, reason: 'Failed for transition type ${type.name}');
        expect(result['path'], isNotNull);
        final file = File(result['path'] as String);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      }
    });

    test('Resolution & Aspect Ratio adjustments work correctly', () async {
      // 9:16 vertical project
      final verticalProject = Project(
        id: 'vertical_proj',
        name: 'Vertical TikTok',
        aspectRatio: AspectRatioPreset.ratio9x16,
        videoClips: [clip1, clip2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final result720p = await DeviceMediaService.renderAndExportVideo(
        project: verticalProject,
        settings: const ExportSettings(resolution: ExportResolution.res720p),
        assets: [asset1, asset2],
      );
      expect(result720p['success'], isTrue);

      final result4k = await DeviceMediaService.renderAndExportVideo(
        project: verticalProject,
        settings: const ExportSettings(resolution: ExportResolution.res4k),
        assets: [asset1, asset2],
      );
      expect(result4k['success'], isTrue);
    });

    test('EditorViewModel.exportVideoToGallery coordinates state and updates progress', () async {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 1.0,
        leftClipId: 'clip_alpha',
        rightClipId: 'clip_beta',
      );

      final project = Project(
        id: 'vm_export_proj',
        name: 'VM Export Test',
        videoClips: [clip1, clip2],
        transitions: [transition],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final viewModel = EditorViewModel(initialProject: project);
      expect(viewModel.isExporting, isFalse);
      expect(viewModel.exportProgress, 0.0);

      bool callbackFinished = false;
      bool callbackSuccess = false;
      String? savedPath;

      final exportFuture = viewModel.exportVideoToGallery(
        onFinished: (success, path) {
          callbackFinished = true;
          callbackSuccess = success;
          savedPath = path;
        },
      );

      expect(viewModel.isExporting, isTrue);

      final success = await exportFuture;
      expect(success, isTrue);
      expect(callbackFinished, isTrue);
      expect(callbackSuccess, isTrue);
      expect(savedPath, isNotNull);
      expect(viewModel.isExporting, isFalse);
      expect(viewModel.exportProgress, 1.0);

      final file = File(savedPath!);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    });

    test('Transition window calculation matches exact boundary and speed math', () {
      // clip1: 4s active (1s trimStart to 5s trimEnd, 1x speed)
      // clip2: 4s active (0s trimStart to 8s trimEnd, 2x speed)
      // Boundary is at 4.0s
      final transition = Transition(
        type: TransitionType.dissolve,
        duration: 2.0,
        leftClipId: 'clip_alpha',
        rightClipId: 'clip_beta',
      );

      final project = Project(
        id: 'boundary_proj',
        name: 'Boundary Test',
        videoClips: [clip1, clip2],
        transitions: [transition],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final viewModel = EditorViewModel(initialProject: project);

      // Boundary is at 4.0s. Transition duration = 2.0s.
      // Transition start = 4.0 - 1.0 = 3.0s
      // Transition end = 4.0 + 1.0 = 5.0s

      // 1. Outside transition before (2.5s)
      viewModel.seekTo(2.5);
      expect(viewModel.activeTransitionAtPlayhead, isNull);

      // 2. Exactly at transition start (3.0s)
      viewModel.seekTo(3.0);
      final atStart = viewModel.activeTransitionAtPlayhead;
      expect(atStart, isNotNull);
      expect(atStart!.progress, closeTo(0.0, 0.01));

      // 3. Exactly at boundary midpoint (4.0s)
      viewModel.seekTo(4.0);
      final atMid = viewModel.activeTransitionAtPlayhead;
      expect(atMid, isNotNull);
      expect(atMid!.progress, closeTo(0.5, 0.01));

      // 4. Exactly at transition end (5.0s)
      viewModel.seekTo(5.0);
      final atEnd = viewModel.activeTransitionAtPlayhead;
      expect(atEnd, isNotNull);
      expect(atEnd!.progress, closeTo(1.0, 0.01));

      // 5. Outside transition after (5.5s)
      viewModel.seekTo(5.5);
      expect(viewModel.activeTransitionAtPlayhead, isNull);
    });
  });
}
