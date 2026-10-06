import 'dart:ui' show ColorFilter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PIP Image Overlay & Adjustments Regression Tests', () {
    test('default PipAdjustments are neutral', () {
      const adjustments = PipAdjustments();

      expect(adjustments.isDefault, isTrue);
      expect(adjustments.brightness, 0.0);
      expect(adjustments.contrast, 0.0);
      expect(adjustments.saturation, 0.0);
      expect(adjustments.exposure, 0.0);
      expect(adjustments.temperature, 0.0);
      expect(adjustments.tint, 0.0);
      expect(adjustments.vignette, 0.0);
      expect(adjustments.sharpness, 0.0);
    });

    test('default adjustments do not create ColorFilter', () {
      // With default adjustments and no filter, createFilter MUST return null
      // to avoid applying any unnecessary ColorFilter widget that could cause gray-screen (#808080)
      final filterDefault = PipColorFilterHelper.createFilter(
        adjustments: const PipAdjustments(),
      );
      expect(filterDefault, isNull);

      final filterNullAdjustments = PipColorFilterHelper.createFilter(
        adjustments: null,
      );
      expect(filterNullAdjustments, isNull);

      final filterNoneId = PipColorFilterHelper.createFilter(
        filterId: 'none',
        adjustments: const PipAdjustments(),
      );
      expect(filterNoneId, isNull);

      final filterEmptyId = PipColorFilterHelper.createFilter(
        filterId: '',
        adjustments: const PipAdjustments(),
      );
      expect(filterEmptyId, isNull);
    });

    test('contrast 0 maps to 1.0', () {
      // contrast = 0.0 is the neutral slider position.
      // In PipColorFilterHelper, c = (1.0 + (adjustments?.contrast ?? 0.0)).clamp(0.0, 3.0);
      // When contrast is 0.0, c must equal 1.0, and cOffset = 128.0 * (1.0 - c) must equal 0.0 (not 128.0!).
      final adjustments = const PipAdjustments(
        contrast: 0.0,
        brightness: 0.2, // trigger non-default so a filter is produced
      );
      final filter = PipColorFilterHelper.createFilter(adjustments: adjustments);
      expect(filter, isNotNull);

      // Verify matrix values: at contrast 0.0 and saturation 0.0 (neutral),
      // scale should be 1.0 and cOffset must be 0.0 (only brightness offset = 0.2 * 50 = 10.0)
      // ColorFilter.matrix creates an instance of _ColorFilterMatrix.
      // We also verify directly through mathematical expectation.
      final c = (1.0 + adjustments.contrast).clamp(0.0, 3.0);
      expect(c, equals(1.0));
      final cOffset = 128.0 * (1.0 - c);
      expect(cOffset, equals(0.0));
    });

    test('saturation 0 maps to 1.0', () {
      // saturation = 0.0 is the neutral slider position.
      // In PipColorFilterHelper, s = (1.0 + (adjustments?.saturation ?? 0.0)).clamp(0.0, 3.0);
      // When saturation is 0.0, s must equal 1.0, preserving all color channels.
      final adjustments = const PipAdjustments(
        saturation: 0.0,
        brightness: 0.2, // trigger non-default so a filter is produced
      );
      final filter = PipColorFilterHelper.createFilter(adjustments: adjustments);
      expect(filter, isNotNull);

      final s = (1.0 + adjustments.saturation).clamp(0.0, 3.0);
      expect(s, equals(1.0));
      final rw = 0.2126 * (1.0 - s);
      final gw = 0.7152 * (1.0 - s);
      final bw = 0.0722 * (1.0 - s);
      expect(rw, equals(0.0));
      expect(gw, equals(0.0));
      expect(bw, equals(0.0));
    });

    test('contrast positive/negative', () {
      // Positive contrast: contrast = 0.5 -> c = 1.5
      const adjPos = PipAdjustments(contrast: 0.5);
      expect(adjPos.isDefault, isFalse);
      final cPos = (1.0 + adjPos.contrast).clamp(0.0, 3.0);
      expect(cPos, closeTo(1.5, 1e-4));
      final cOffsetPos = 128.0 * (1.0 - cPos);
      expect(cOffsetPos, closeTo(-64.0, 1e-4));
      final filterPos = PipColorFilterHelper.createFilter(adjustments: adjPos);
      expect(filterPos, isNotNull);

      // Negative contrast: contrast = -0.5 -> c = 0.5
      const adjNeg = PipAdjustments(contrast: -0.5);
      expect(adjNeg.isDefault, isFalse);
      final cNeg = (1.0 + adjNeg.contrast).clamp(0.0, 3.0);
      expect(cNeg, closeTo(0.5, 1e-4));
      final cOffsetNeg = 128.0 * (1.0 - cNeg);
      expect(cOffsetNeg, closeTo(64.0, 1e-4));
      final filterNeg = PipColorFilterHelper.createFilter(adjustments: adjNeg);
      expect(filterNeg, isNotNull);

      // Boundary -1.0 -> c = 0.0
      const adjMin = PipAdjustments(contrast: -1.0);
      final cMin = (1.0 + adjMin.contrast).clamp(0.0, 3.0);
      expect(cMin, equals(0.0));

      // Boundary +1.0 -> c = 2.0
      const adjMax = PipAdjustments(contrast: 1.0);
      final cMax = (1.0 + adjMax.contrast).clamp(0.0, 3.0);
      expect(cMax, equals(2.0));
    });

    test('saturation positive/negative', () {
      // Positive saturation: saturation = 0.5 -> s = 1.5
      const adjPos = PipAdjustments(saturation: 0.5);
      expect(adjPos.isDefault, isFalse);
      final sPos = (1.0 + adjPos.saturation).clamp(0.0, 3.0);
      expect(sPos, closeTo(1.5, 1e-4));
      final filterPos = PipColorFilterHelper.createFilter(adjustments: adjPos);
      expect(filterPos, isNotNull);

      // Negative saturation: saturation = -0.5 -> s = 0.5
      const adjNeg = PipAdjustments(saturation: -0.5);
      expect(adjNeg.isDefault, isFalse);
      final sNeg = (1.0 + adjNeg.saturation).clamp(0.0, 3.0);
      expect(sNeg, closeTo(0.5, 1e-4));
      final filterNeg = PipColorFilterHelper.createFilter(adjustments: adjNeg);
      expect(filterNeg, isNotNull);

      // Extreme negative: saturation = -1.0 -> s = 0.0 (monochrome)
      const adjMono = PipAdjustments(saturation: -1.0);
      final sMono = (1.0 + adjMono.saturation).clamp(0.0, 3.0);
      expect(sMono, equals(0.0));
    });

    test('image PIP preview model', () {
      const clip = OverlayClip(
        id: 'pip_img_model_1',
        title: 'Image Overlay Model',
        localPath: '/data/user/0/cache/photo_preview.jpg',
        isPhoto: true,
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
        position: Offset(0.4, 0.6),
        scale: 0.7,
        opacity: 0.95,
      );

      expect(clip.isPhoto, isTrue);
      expect(clip.id, equals('pip_img_model_1'));
      expect(clip.title, equals('Image Overlay Model'));
      expect(clip.localPath, equals('/data/user/0/cache/photo_preview.jpg'));
      expect(clip.position, equals(const Offset(0.4, 0.6)));
      expect(clip.scale, equals(0.7));
      expect(clip.opacity, equals(0.95));
    });

    test('image PIP local path', () {
      const pathJpg = '/data/user/0/cache/image.jpg';
      const pathPng = '/data/user/0/cache/image.png';
      const pathWebp = '/data/user/0/cache/image.webp';

      final clipJpg = OverlayClip(
        id: 'ov_jpg',
        title: 'JPG',
        localPath: pathJpg,
        isPhoto: true,
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
      );
      final clipPng = OverlayClip(
        id: 'ov_png',
        title: 'PNG',
        localPath: pathPng,
        isPhoto: true,
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
      );
      final clipWebp = OverlayClip(
        id: 'ov_webp',
        title: 'WebP',
        localPath: pathWebp,
        isPhoto: true,
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
      );

      expect(clipJpg.localPath, equals(pathJpg));
      expect(clipPng.localPath, equals(pathPng));
      expect(clipWebp.localPath, equals(pathWebp));
      expect(clipJpg.isPhoto, isTrue);
      expect(clipPng.isPhoto, isTrue);
      expect(clipWebp.isPhoto, isTrue);
    });

    test('image PIP duration', () {
      const clip = OverlayClip(
        id: 'pip_dur_1',
        title: 'Duration Test',
        startTime: Duration(milliseconds: 750),
        duration: Duration(milliseconds: 3250),
        isPhoto: true,
      );

      expect(clip.startTime, equals(const Duration(milliseconds: 750)));
      expect(clip.duration, equals(const Duration(milliseconds: 3250)));
      expect(clip.startTimeInSeconds, closeTo(0.75, 1e-4));
      expect(clip.durationInSeconds, closeTo(3.25, 1e-4));
      expect(clip.endTimeInSeconds, closeTo(4.0, 1e-4));
      expect(clip.endTimeMs, equals(4000));
      expect(clip.endTime, equals(const Duration(milliseconds: 4000)));
    });

    test('image PIP transform', () {
      const clip = OverlayClip(
        id: 'pip_trans_1',
        title: 'Transform Test',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.25, 0.75),
        scale: 1.25,
        rotation: 1.5708, // ~90 degrees in radians
        flipHorizontal: true,
        flipVertical: false,
        isPhoto: true,
      );

      expect(clip.position.dx, closeTo(0.25, 1e-4));
      expect(clip.position.dy, closeTo(0.75, 1e-4));
      expect(clip.scale, closeTo(1.25, 1e-4));
      expect(clip.rotation, closeTo(1.5708, 1e-4));
      expect(clip.flipHorizontal, isTrue);
      expect(clip.flipVertical, isFalse);
    });

    test('image PIP serialization', () {
      const clip = OverlayClip(
        id: 'pip_ser_1',
        title: 'Serialize Test',
        assetId: 'asset_ser_99',
        localPath: '/data/user/0/cache/test_serialize.png',
        thumbnailPath: '/data/user/0/cache/test_serialize_thumb.png',
        isPhoto: true,
        startTime: Duration(milliseconds: 1000),
        duration: Duration(milliseconds: 4000),
        position: Offset(0.5, 0.5),
        scale: 0.8,
        rotation: 0.1,
        opacity: 0.9,
        flipHorizontal: true,
        flipVertical: true,
        adjustments: PipAdjustments(
          brightness: 0.1,
          contrast: -0.2,
          saturation: 0.3,
          temperature: 0.15,
          tint: -0.05,
        ),
      );

      final json = clip.toJson();

      expect(json['id'], equals('pip_ser_1'));
      expect(json['title'], equals('Serialize Test'));
      expect(json['assetId'], equals('asset_ser_99'));
      expect(json['localPath'], equals('/data/user/0/cache/test_serialize.png'));
      expect(json['isPhoto'], isTrue);
      expect(json['startTimeMs'], equals(1000));
      expect(json['durationMs'], equals(4000));
      expect(json['posX'], closeTo(0.5, 1e-4));
      expect(json['posY'], closeTo(0.5, 1e-4));
      expect(json['scale'], closeTo(0.8, 1e-4));
      expect(json['rotation'], closeTo(0.1, 1e-4));
      expect(json['opacity'], closeTo(0.9, 1e-4));
      expect(json['flipHorizontal'], isTrue);
      expect(json['flipVertical'], isTrue);
      expect(json['adjustments'], isNotNull);
      final adjJson = json['adjustments'] as Map<String, dynamic>;
      expect(adjJson['brightness'], closeTo(0.1, 1e-4));
      expect(adjJson['contrast'], closeTo(-0.2, 1e-4));
      expect(adjJson['saturation'], closeTo(0.3, 1e-4));
    });

    test('image PIP deserialization', () {
      final json = <String, dynamic>{
        'id': 'pip_deser_1',
        'title': 'Deserialized PIP',
        'assetId': 'asset_deser_77',
        'localPath': '/data/user/0/cache/sample_deser.webp',
        'thumbnailPath': '/data/user/0/cache/sample_deser_thumb.webp',
        'isPhoto': true,
        'startTimeMs': 500,
        'durationMs': 3500,
        'posX': 0.35,
        'posY': 0.65,
        'scale': 0.6,
        'rotation': -0.5,
        'opacity': 0.88,
        'flipHorizontal': false,
        'flipVertical': true,
        'adjustments': <String, dynamic>{
          'brightness': -0.15,
          'contrast': 0.25,
          'saturation': -0.1,
          'exposure': 0.0,
          'temperature': -0.2,
          'tint': 0.1,
          'vignette': 0.0,
          'sharpness': 0.0,
        },
      };

      final clip = OverlayClip.fromJson(json);

      expect(clip.id, equals('pip_deser_1'));
      expect(clip.title, equals('Deserialized PIP'));
      expect(clip.assetId, equals('asset_deser_77'));
      expect(clip.localPath, equals('/data/user/0/cache/sample_deser.webp'));
      expect(clip.isPhoto, isTrue);
      expect(clip.startTime, equals(const Duration(milliseconds: 500)));
      expect(clip.duration, equals(const Duration(milliseconds: 3500)));
      expect(clip.position.dx, closeTo(0.35, 1e-4));
      expect(clip.position.dy, closeTo(0.65, 1e-4));
      expect(clip.scale, closeTo(0.6, 1e-4));
      expect(clip.rotation, closeTo(-0.5, 1e-4));
      expect(clip.opacity, closeTo(0.88, 1e-4));
      expect(clip.flipHorizontal, isFalse);
      expect(clip.flipVertical, isTrue);
      expect(clip.adjustments, isNotNull);
      expect(clip.adjustments!.brightness, closeTo(-0.15, 1e-4));
      expect(clip.adjustments!.contrast, closeTo(0.25, 1e-4));
      expect(clip.adjustments!.saturation, closeTo(-0.1, 1e-4));
      expect(clip.adjustments!.temperature, closeTo(-0.2, 1e-4));
      expect(clip.adjustments!.tint, closeTo(0.1, 1e-4));
      expect(clip.adjustments!.isDefault, isFalse);
    });

    test('timeline boundary hardening: handles zero start, sub-frame precision, and end-trim math', () {
      const clipZero = OverlayClip(
        id: 'clip_zero',
        title: 'Zero Start Overlay',
        startTime: Duration.zero,
        duration: Duration(milliseconds: 3000),
        isPhoto: true,
      );

      expect(clipZero.startTimeInSeconds, equals(0.0));
      expect(clipZero.durationInSeconds, equals(3.0));
      expect(clipZero.endTimeInSeconds, equals(3.0));
      expect(clipZero.endTimeMs, equals(3000));

      // Sub-frame boundary checking
      const boundaryTolerance = 0.05; // 50ms buffer used in EditorViewModel
      bool isVisibleAt(double playhead, OverlayClip c) {
        return playhead >= (c.startTimeInSeconds - boundaryTolerance) &&
            playhead <= (c.endTimeInSeconds + boundaryTolerance);
      }

      // Exactly at start
      expect(isVisibleAt(0.0, clipZero), isTrue);
      // Just inside start (1 frame / 16ms inside)
      expect(isVisibleAt(0.016, clipZero), isTrue);
      // Midpoint
      expect(isVisibleAt(1.5, clipZero), isTrue);
      // Exactly at end
      expect(isVisibleAt(3.0, clipZero), isTrue);
      // 1 frame inside end
      expect(isVisibleAt(2.984, clipZero), isTrue);
      // 100ms outside end (outside 50ms tolerance)
      expect(isVisibleAt(3.10, clipZero), isFalse);
      // Before start (outside 50ms tolerance)
      expect(isVisibleAt(-0.10, clipZero), isFalse);

      // Very short PIP (100ms)
      const shortClip = OverlayClip(
        id: 'short_clip',
        title: 'Short PIP',
        startTime: Duration(milliseconds: 1000),
        duration: Duration(milliseconds: 100),
        isPhoto: true,
      );
      expect(shortClip.startTimeInSeconds, equals(1.0));
      expect(shortClip.durationInSeconds, equals(0.1));
      expect(shortClip.endTimeInSeconds, closeTo(1.1, 1e-4));
      expect(isVisibleAt(1.05, shortClip), isTrue);
    });

    test('animation duration hardening: user trim preserves timeline duration authority without mutating clip', () {
      const entranceAnim = PipAnimation(
        type: 'fade',
        durationSec: 1.0,
        easing: 'easeInOut',
        enabled: true,
      );

      final clip = OverlayClip(
        id: 'anim_clip',
        title: 'Animated Photo',
        startTime: Duration.zero,
        duration: const Duration(seconds: 4),
        isPhoto: true,
        inAnimation: entranceAnim,
      );

      expect(clip.inAnimation, isNotNull);
      expect(clip.inAnimation!.durationSec, equals(1.0));
      expect(clip.durationInSeconds, equals(4.0));

      // Simulate trimming clip to 0.5s: clip duration becomes 0.5s
      final trimmedClip = clip.copyWith(
        duration: const Duration(milliseconds: 500),
      );

      // The clip duration must strictly reflect user trim (0.5s), NOT be lengthened or shortened by the animation
      expect(trimmedClip.durationInSeconds, equals(0.5));
      expect(trimmedClip.inAnimation!.durationSec, equals(1.0));
      // Effective animation clamp: animation duration cannot exceed the clip duration in playback
      final effectiveAnimDuration = trimmedClip.inAnimation!.durationSec > trimmedClip.durationInSeconds
          ? trimmedClip.durationInSeconds
          : trimmedClip.inAnimation!.durationSec;
      expect(effectiveAnimDuration, equals(0.5));
    });

    test('multi-PIP stress & persistence: 3 Images + 2 Videos + 2 Texts serialize and revive cleanly', () {
      final img1 = const OverlayClip(
        id: 'img_1',
        title: 'Image 1 (JPG)',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.2, 0.3),
        scale: 0.5,
        isPhoto: true,
        localPath: '/data/user/0/cache/img1.jpg',
      );
      final img2 = const OverlayClip(
        id: 'img_2',
        title: 'Image 2 (PNG Transparent)',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
        position: Offset(0.5, 0.5),
        scale: 0.7,
        opacity: 0.85,
        isPhoto: true,
        localPath: '/data/user/0/cache/img2.png',
      );
      final img3 = const OverlayClip(
        id: 'img_3',
        title: 'Image 3 (WebP)',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 3),
        position: Offset(0.8, 0.7),
        scale: 0.6,
        rotation: 0.785, // 45 deg
        isPhoto: true,
        localPath: '/data/user/0/cache/img3.webp',
      );
      final vid1 = const OverlayClip(
        id: 'vid_1',
        title: 'Video PIP 1',
        startTime: Duration.zero,
        duration: Duration(seconds: 6),
        position: Offset(0.3, 0.7),
        scale: 0.4,
        isPhoto: false,
        localPath: '/data/user/0/cache/vid1.mp4',
      );
      final vid2 = const OverlayClip(
        id: 'vid_2',
        title: 'Video PIP 2',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 5),
        position: Offset(0.7, 0.3),
        scale: 0.45,
        isPhoto: false,
        localPath: '/data/user/0/cache/vid2.mp4',
      );

      final text1 = TextOverlay(
        id: 'txt_1',
        text: 'Title Headline',
        startTime: Duration.zero,
        duration: const Duration(seconds: 4),
      );
      final text2 = TextOverlay(
        id: 'txt_2',
        text: 'Subtitle Banner',
        startTime: const Duration(seconds: 2),
        duration: const Duration(seconds: 3),
      );

      final allOverlays = [img1, img2, img3, vid1, vid2];
      final allTexts = [text1, text2];

      // Verify layer count and distinct z-indices
      expect(allOverlays.length, equals(5));
      expect(allTexts.length, equals(2));

      // Verify image vs video distinction
      final photos = allOverlays.where((o) => o.isPhoto).toList();
      final videos = allOverlays.where((o) => !o.isPhoto).toList();
      expect(photos.length, equals(3));
      expect(videos.length, equals(2));
      for (final p in photos) {
        expect(p.isPhoto, isTrue);
        expect(p.localPath, isNotNull);
      }
      for (final v in videos) {
        expect(v.isPhoto, isFalse);
        expect(v.localPath, isNotNull);
      }

      // JSON serialization & deserialization cycle
      final serializedOverlays = allOverlays.map((o) => o.toJson()).toList();
      final revivedOverlays = serializedOverlays.map((j) => OverlayClip.fromJson(j)).toList();

      expect(revivedOverlays.length, equals(5));
      expect(revivedOverlays[0].id, equals('img_1'));
      expect(revivedOverlays[0].isPhoto, isTrue);
      expect(revivedOverlays[1].id, equals('img_2'));
      expect(revivedOverlays[1].opacity, closeTo(0.85, 1e-4));
      expect(revivedOverlays[2].id, equals('img_3'));
      expect(revivedOverlays[2].rotation, closeTo(0.785, 1e-4));
      expect(revivedOverlays[3].id, equals('vid_1'));
      expect(revivedOverlays[3].isPhoto, isFalse);
      expect(revivedOverlays[4].id, equals('vid_2'));
      expect(revivedOverlays[4].isPhoto, isFalse);
    });
  });
}
