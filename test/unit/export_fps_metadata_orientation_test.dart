import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7.1 - Export FPS Metadata & Resolution Tests', () {
    test('ExportFps enum exposes correct integer fpsNumber for all supported frame rates', () {
      expect(ExportFps.fps20.fpsNumber, 20);
      expect(ExportFps.fps24.fpsNumber, 24);
      expect(ExportFps.fps30.fpsNumber, 30);
      expect(ExportFps.fps50.fpsNumber, 50);
      expect(ExportFps.fps60.fpsNumber, 60);
    });

    test('DeviceMediaService verifies and delivers 720p@20fps, 1080p@30fps, 2K@50fps, and 4K@60fps pipelines', () async {
      const clip = VideoClip(
        id: 'clip_target_pipeline',
        assetId: 'asset_target_pipeline',
        title: 'Target Combination Clip',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        speed: 1.0,
        previewGradient: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      );

      final project = Project(
        id: 'proj_target_pipeline',
        name: 'Target Pipeline Test',
        videoClips: [clip],
        aspectRatio: AspectRatioPreset.ratio16x9,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 1. 720p at 20 FPS (1280x720, 20 fps, 3.5 Mbps)
      const settings720p20 = ExportSettings(
        resolution: ExportResolution.res720p,
        fps: ExportFps.fps20,
      );
      final res720p20 = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: settings720p20,
        assets: [],
      );
      expect(res720p20['success'], isTrue);
      expect(res720p20['width'], 1280);
      expect(res720p20['height'], 720);
      expect(res720p20['fps'], 20);
      expect(res720p20['bitrate'], 3500000);

      // 2. 1080p at 30 FPS (1920x1080, 30 fps, 9.0 Mbps)
      const settings1080p30 = ExportSettings(
        resolution: ExportResolution.res1080p,
        fps: ExportFps.fps30,
      );
      final res1080p30 = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: settings1080p30,
        assets: [],
      );
      expect(res1080p30['success'], isTrue);
      expect(res1080p30['width'], 1920);
      expect(res1080p30['height'], 1080);
      expect(res1080p30['fps'], 30);
      expect(res1080p30['bitrate'], 9000000);

      // 3. 2K (1440p) at 50 FPS (2560x1440, 50 fps, 22.0 Mbps)
      const settings2k50 = ExportSettings(
        resolution: ExportResolution.res2k,
        fps: ExportFps.fps50,
      );
      final res2k50 = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: settings2k50,
        assets: [],
      );
      expect(res2k50['success'], isTrue);
      expect(res2k50['width'], 2560);
      expect(res2k50['height'], 1440);
      expect(res2k50['fps'], 50);
      expect(res2k50['bitrate'], 22000000);

      // 4. 4K at 60 FPS (3840x2160, 60 fps, 42.0 Mbps)
      const settings4k60 = ExportSettings(
        resolution: ExportResolution.res4k,
        fps: ExportFps.fps60,
      );
      final res4k60 = await DeviceMediaService.renderAndExportVideo(
        project: project,
        settings: settings4k60,
        assets: [],
      );
      expect(res4k60['success'], isTrue);
      expect(res4k60['width'], 3840);
      expect(res4k60['height'], 2160);
      expect(res4k60['fps'], 60);
      expect(res4k60['bitrate'], 42000000);
    });
  });
}
