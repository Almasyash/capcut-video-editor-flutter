import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Speed Model & Curve Presets Tests', () {
    test('SpeedInterpolation enum exposes all easing models', () {
      expect(SpeedInterpolation.values, contains(SpeedInterpolation.linear));
      expect(SpeedInterpolation.values, contains(SpeedInterpolation.easeIn));
      expect(SpeedInterpolation.values, contains(SpeedInterpolation.easeOut));
      expect(SpeedInterpolation.values, contains(SpeedInterpolation.easeInOut));
      expect(SpeedInterpolation.values, contains(SpeedInterpolation.hold));
    });

    test('SpeedCurvePoint validation, copyWith and serialization', () {
      const pt = SpeedCurvePoint(
        timeRatio: 0.25,
        speedMultiplier: 2.0,
        interpolation: SpeedInterpolation.easeInOut,
      );

      expect(pt.timeRatio, 0.25);
      expect(pt.speedMultiplier, 2.0);
      expect(pt.interpolation, SpeedInterpolation.easeInOut);

      final json = pt.toJson();
      expect(json['timeRatio'], 0.25);
      expect(json['speedMultiplier'], 2.0);
      expect(json['interpolation'], 'easeInOut');

      final reconstructed = SpeedCurvePoint.fromJson(json);
      expect(reconstructed.timeRatio, 0.25);
      expect(reconstructed.speedMultiplier, 2.0);
      expect(reconstructed.interpolation, SpeedInterpolation.easeInOut);
      expect(reconstructed, equals(pt));

      final modified = pt.copyWith(speedMultiplier: 4.0);
      expect(modified.speedMultiplier, 4.0);
      expect(modified.timeRatio, 0.25);
    });

    test('SpeedPoint alias conforms to SpeedCurvePoint', () {
      const sp = SpeedPoint(timeRatio: 0.5, speedMultiplier: 1.5);
      expect(sp, isA<SpeedCurvePoint>());
      expect(sp.timeRatio, 0.5);
      expect(sp.speedMultiplier, 1.5);
    });

    test('SpeedSegment models interval correctly', () {
      const seg = SpeedSegment(
        startRatio: 0.2,
        endRatio: 0.6,
        startSpeed: 1.0,
        endSpeed: 3.0,
        interpolation: SpeedInterpolation.linear,
      );
      expect(seg.durationRatio, closeTo(0.4, 0.0001));
      expect(seg.evaluateAt(0.2), closeTo(1.0, 0.01));
      expect(seg.evaluateAt(0.4), closeTo(2.0, 0.01));
      expect(seg.evaluateAt(0.6), closeTo(3.0, 0.01));
    });

    test('FreezeFrame model serialization and validation', () {
      const freeze = FreezeFrame(
        timelineOffset: Duration(seconds: 2),
        duration: Duration(seconds: 3),
        sourceTime: Duration(seconds: 1),
      );

      final json = freeze.toJson();
      expect(json['timelineOffsetMs'], 2000);
      expect(json['durationMs'], 3000);
      expect(json['sourceTimeMs'], 1000);

      final fromJson = FreezeFrame.fromJson(json);
      expect(fromJson.timelineOffset, const Duration(seconds: 2));
      expect(fromJson.duration, const Duration(seconds: 3));
      expect(fromJson.sourceTime, const Duration(seconds: 1));
      expect(fromJson, equals(freeze));
    });

    test('All 8 required SpeedCurve presets generate deterministic points', () {
      final montage = SpeedCurve.montage();
      final hero = SpeedCurve.hero();
      final bullet = SpeedCurve.bullet();
      final jumpCut = SpeedCurve.jumpCut();
      final flashIn = SpeedCurve.flashIn();
      final flashOut = SpeedCurve.flashOut();
      final smooth = SpeedCurve.smooth();
      final custom = SpeedCurve.custom();

      expect(montage.type, SpeedCurvePresetType.montage);
      expect(hero.type, SpeedCurvePresetType.hero);
      expect(bullet.type, SpeedCurvePresetType.bullet);
      expect(jumpCut.type, SpeedCurvePresetType.jumpCut);
      expect(flashIn.type, SpeedCurvePresetType.flashIn);
      expect(flashOut.type, SpeedCurvePresetType.flashOut);
      expect(smooth.type, SpeedCurvePresetType.smooth);
      expect(custom.type, SpeedCurvePresetType.custom);

      // Verify all presets have start at 0.0 and end at 1.0
      for (final curve in [montage, hero, bullet, jumpCut, flashIn, flashOut, smooth, custom]) {
        expect(curve.points.first.timeRatio, 0.0);
        expect(curve.points.last.timeRatio, 1.0);
        expect(curve.points.length, greaterThanOrEqualTo(2));
        expect(curve.averageSpeed, greaterThan(0.0));
      }
    });

    test('SpeedCurve serialization and deserialization preserves points and presets', () {
      final curve = SpeedCurve.hero();
      final json = curve.toJson();
      final restored = SpeedCurve.fromJson(json);

      expect(restored.type, SpeedCurvePresetType.hero);
      expect(restored.points.length, curve.points.length);
      expect(restored.keepPitch, curve.keepPitch);
      expect(restored.smoothSlowMo, curve.smoothSlowMo);
      expect(restored, equals(curve));
    });

    test('SpeedCurve evaluateSpeedAt interpolates deterministically across points', () {
      final curve = SpeedCurve.constant(2.0);
      expect(curve.evaluateSpeedAt(0.0), closeTo(2.0, 0.001));
      expect(curve.evaluateSpeedAt(0.5), closeTo(2.0, 0.001));
      expect(curve.evaluateSpeedAt(1.0), closeTo(2.0, 0.001));

      const ramp = SpeedCurve(
        type: SpeedCurvePresetType.custom,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 0.5, speedMultiplier: 3.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 1.0),
        ],
      );
      expect(ramp.evaluateSpeedAt(0.0), closeTo(1.0, 0.01));
      expect(ramp.evaluateSpeedAt(0.25), closeTo(2.0, 0.05));
      expect(ramp.evaluateSpeedAt(0.5), closeTo(3.0, 0.01));
      expect(ramp.evaluateSpeedAt(0.75), closeTo(2.0, 0.05));
      expect(ramp.evaluateSpeedAt(1.0), closeTo(1.0, 0.01));
    });

    test('SpeedCurve getSourceProgressAt produces monotonic [0.0, 1.0] progression', () {
      final curves = [
        SpeedCurve.montage(),
        SpeedCurve.hero(),
        SpeedCurve.bullet(),
        SpeedCurve.smooth(),
      ];

      for (final curve in curves) {
        expect(curve.getSourceProgressAt(0.0), closeTo(0.0, 0.001));
        expect(curve.getSourceProgressAt(1.0), closeTo(1.0, 0.001));

        double lastProgress = -0.001;
        for (int i = 0; i <= 20; i++) {
          final t = i / 20.0;
          final prog = curve.getSourceProgressAt(t);
          expect(prog, greaterThanOrEqualTo(lastProgress),
              reason: 'Progress must be non-decreasing for ${curve.type} at t=$t');
          lastProgress = prog;
        }
      }
    });

    test('SpeedCurve.splitAt splits curve into two continuous rebased sub-curves', () {
      final original = SpeedCurve.hero();
      final (partA, partB) = original.splitAt(0.4);

      expect(partA.points.first.timeRatio, 0.0);
      expect(partA.points.last.timeRatio, 1.0);
      expect(partB.points.first.timeRatio, 0.0);
      expect(partB.points.last.timeRatio, 1.0);

      // Speed at the split boundary must match in both halves
      final speedAtSplit = original.evaluateSpeedAt(0.4);
      expect(partA.points.last.speedMultiplier, closeTo(speedAtSplit, 0.01));
      expect(partB.points.first.speedMultiplier, closeTo(speedAtSplit, 0.01));
    });

    test('SpeedCurve.duplicate deep-copies points and state', () {
      final orig = SpeedCurve.montage();
      final copy = orig.duplicate();

      expect(copy, equals(orig));
      expect(identical(copy, orig), isFalse);
      expect(identical(copy.points, orig.points), isFalse);
    });
  });

  group('2. Deterministic Time Remapping & Mapping Engine Tests', () {
    test('Constant speed mapping 1x, 2x, 0.5x, 4x, 0.25x, 8x', () {
      const trimStart = Duration.zero;
      const trimEnd = Duration(seconds: 10);
      const original = Duration(seconds: 10);

      // 1x: timeline offset 5s -> source 5s
      final t1 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 5),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 1.0,
      );
      expect(t1.inMilliseconds, 5000);

      // 2x: timeline offset 2.5s -> source 5s
      final t2 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(milliseconds: 2500),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 2.0,
      );
      expect(t2.inMilliseconds, 5000);

      // 0.5x: timeline offset 10s -> source 5s
      final tHalf = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 10),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 0.5,
      );
      expect(tHalf.inMilliseconds, 5000);

      // 4x: timeline offset 1s -> source 4s
      final t4 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 1),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 4.0,
      );
      expect(t4.inMilliseconds, 4000);

      // 0.25x: timeline offset 8s -> source 2s
      final tQuarter = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 8),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 0.25,
      );
      expect(tQuarter.inMilliseconds, 2000);

      // 8x: timeline offset 1s -> source 8s
      final t8 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 1),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        constantSpeed: 8.0,
      );
      expect(t8.inMilliseconds, 8000);
    });

    test('Source duration and active duration calculations under speed changes', () {
      // 10s source at 2x = 5s active timeline
      final dur2x = TimeRemapper.calculateActiveDuration(
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        constantSpeed: 2.0,
      );
      expect(dur2x.inMilliseconds, 5000);

      // 10s source at 0.5x = 20s active timeline
      final durHalf = TimeRemapper.calculateActiveDuration(
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        constantSpeed: 0.5,
      );
      expect(durHalf.inMilliseconds, 20000);
    });

    test('Freeze frame time remapping holds exact frame and rebases post-freeze', () {
      const trimStart = Duration.zero;
      const trimEnd = Duration(seconds: 10);
      const original = Duration(seconds: 10);
      const freeze = FreezeFrame(
        timelineOffset: Duration(seconds: 3), // freeze begins at 3s on timeline
        duration: Duration(seconds: 2),       // freezes for 2s (active window: 3s to 5s)
        sourceTime: Duration(seconds: 3),     // frame locked at 3s source
      );

      // Before freeze: normal progression
      final before = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 2),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        freezeFrame: freeze,
      );
      expect(before.inMilliseconds, 2000);

      // Inside freeze window: exactly locked to sourceTime
      final inside1 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 3),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        freezeFrame: freeze,
      );
      expect(inside1.inMilliseconds, 3000);

      final inside2 = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(milliseconds: 4500),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        freezeFrame: freeze,
      );
      expect(inside2.inMilliseconds, 3000);

      final insideEnd = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 5),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        freezeFrame: freeze,
      );
      expect(insideEnd.inMilliseconds, 3000);

      // After freeze: timeline offset is rebased by -freezeDuration
      // At 6s on timeline (1s after freeze ends), effective timeline is 4s -> source is 4s
      final after = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 6),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        freezeFrame: freeze,
      );
      expect(after.inMilliseconds, 4000);
    });

    test('Reverse playback inverts source mapping from trimEnd to trimStart', () {
      const trimStart = Duration(seconds: 2);
      const trimEnd = Duration(seconds: 8); // 6s duration
      const original = Duration(seconds: 10);

      // At t=0s, reverse should be at trimEnd (8s)
      final t0 = TimeRemapper.timelineToSourceTime(
        timelineOffset: Duration.zero,
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        isReversed: true,
      );
      expect(t0.inMilliseconds, 8000);

      // At t=3s (halfway), reverse should be at 5s
      final tMid = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 3),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        isReversed: true,
      );
      expect(tMid.inMilliseconds, 5000);

      // At t=6s (end), reverse should be at trimStart (2s)
      final tEnd = TimeRemapper.timelineToSourceTime(
        timelineOffset: const Duration(seconds: 6),
        trimStart: trimStart,
        trimEnd: trimEnd,
        originalDuration: original,
        isReversed: true,
      );
      expect(tEnd.inMilliseconds, 2000);
    });

    test('VideoClip activeDuration integrates speedCurve and freezeFrame', () {
      const clipNormal = VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Normal',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        speed: 1.0,
        previewGradient: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      );
      expect(clipNormal.activeDuration.inMilliseconds, 10000);

      final clip2x = clipNormal.copyWith(speed: 2.0);
      expect(clip2x.activeDuration.inMilliseconds, 5000);

      final clipFreeze = clipNormal.copyWith(
        freezeFrame: const FreezeFrame(
          timelineOffset: Duration(seconds: 2),
          duration: Duration(seconds: 3),
          sourceTime: Duration(seconds: 2),
        ),
      );
      // 10s base + 3s freeze = 13s active duration
      expect(clipFreeze.activeDuration.inMilliseconds, 13000);
    });

    test('OverlayClip activeDuration integrates speed, speedCurve and freezeFrame', () {
      const overlay = OverlayClip(
        id: 'ov1',
        title: 'Video PIP',
        startTime: Duration.zero,
        duration: Duration(seconds: 10),
        speed: 2.0,
        freezeFrame: FreezeFrame(
          timelineOffset: Duration(seconds: 1),
          duration: Duration(seconds: 2),
          sourceTime: Duration(seconds: 1),
        ),
      );
      // Base: 10s / 2.0 = 5s + 2s freeze = 7s
      expect(overlay.activeDuration.inMilliseconds, 7000);
    });
  });

  group('3. ViewModel Speed Ramping, Trimming, Splitting & Undo/Redo Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      const clip = VideoClip(
        id: 'test_clip_1',
        assetId: 'asset_1',
        title: 'Test Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        speed: 1.0,
        previewGradient: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      );
      final project = Project(
        id: 'speed_test_proj',
        name: 'Speed Test Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        aspectRatio: AspectRatioPreset.ratio16x9,
        videoClips: const [clip],
      );
      viewModel = EditorViewModel(initialProject: project);
      viewModel.selectClip(0);
    });

    test('setClipSpeed updates speed and records undo snapshot', () {
      expect(viewModel.selectedClip!.speed, 1.0);
      expect(viewModel.canUndo, isFalse);

      viewModel.setClipSpeed(2.0);
      expect(viewModel.selectedClip!.speed, 2.0);
      expect(viewModel.selectedClip!.durationInSeconds, closeTo(5.0, 0.01));
      expect(viewModel.canUndo, isTrue);

      viewModel.undo();
      expect(viewModel.selectedClip!.speed, 1.0);
      expect(viewModel.selectedClip!.durationInSeconds, closeTo(10.0, 0.01));

      viewModel.redo();
      expect(viewModel.selectedClip!.speed, 2.0);
    });

    test('setClipSpeedCurve applies preset curve and updates active duration', () {
      final heroCurve = SpeedCurve.hero();
      viewModel.setClipSpeedCurve(heroCurve);

      expect(viewModel.selectedClip!.speedCurve, isNotNull);
      expect(viewModel.selectedClip!.speedCurve!.type, SpeedCurvePresetType.hero);
      expect(viewModel.canUndo, isTrue);

      // Undo restores null speedCurve
      viewModel.undo();
      expect(viewModel.selectedClip!.speedCurve, isNull);
    });

    test('addFreezeFrameAtPlayhead creates deterministic FreezeFrame', () {
      viewModel.seekTo(3.0); // 3 seconds on timeline
      viewModel.addFreezeFrameAtPlayhead(duration: const Duration(seconds: 2));

      final clip = viewModel.selectedClip!;
      expect(clip.freezeFrame, isNotNull);
      expect(clip.freezeFrame!.timelineOffset.inMilliseconds, 3000);
      expect(clip.freezeFrame!.duration.inMilliseconds, 2000);
      expect(clip.freezeFrame!.sourceTime.inMilliseconds, 3000);

      // Total active duration is 10s + 2s = 12s
      expect(clip.durationInSeconds, closeTo(12.0, 0.01));

      // Remove freeze frame
      viewModel.removeFreezeFrame();
      expect(viewModel.selectedClip!.freezeFrame, isNull);
      expect(viewModel.selectedClip!.durationInSeconds, closeTo(10.0, 0.01));
    });

    test('splitClipAtPlayhead splits speed-ramped clip into Part A and Part B with rebased curves', () {
      viewModel.setClipSpeedCurve(SpeedCurve.montage());
      final origDuration = viewModel.selectedClip!.durationInSeconds;

      viewModel.seekTo(origDuration / 2.0);
      final splitResult = viewModel.splitClipAtPlayhead();
      expect(splitResult, isTrue);

      expect(viewModel.videoClips.length, 2);
      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      expect(partA.speedCurve, isNotNull);
      expect(partB.speedCurve, isNotNull);
      expect(partA.speedCurve!.points.first.timeRatio, 0.0);
      expect(partA.speedCurve!.points.last.timeRatio, 1.0);
      expect(partB.speedCurve!.points.first.timeRatio, 0.0);
      expect(partB.speedCurve!.points.last.timeRatio, 1.0);

      // Undo merges back to single clip
      viewModel.undo();
      expect(viewModel.videoClips.length, 1);
      expect(viewModel.videoClips[0].speedCurve!.type, SpeedCurvePresetType.montage);
    });

    test('duplicateSelectedClip deep-copies speedCurve and freezeFrame', () {
      viewModel.setClipSpeedCurve(SpeedCurve.bullet());
      viewModel.addFreezeFrameAtPlayhead(duration: const Duration(seconds: 2));

      viewModel.duplicateSelectedClip();
      expect(viewModel.videoClips.length, 2);

      final original = viewModel.videoClips[0];
      final duplicate = viewModel.videoClips[1];

      expect(duplicate.id, isNot(equals(original.id)));
      expect(duplicate.speedCurve, equals(original.speedCurve));
      expect(identical(duplicate.speedCurve, original.speedCurve), isFalse);
      expect(duplicate.freezeFrame, equals(original.freezeFrame));
      expect(identical(duplicate.freezeFrame, original.freezeFrame), isFalse);

      // Mutating duplicate does not mutate original
      viewModel.selectClip(1);
      viewModel.setClipSpeed(1.5);
      expect(viewModel.videoClips[0].speedCurve, isNotNull);
      expect(viewModel.videoClips[1].speedCurve, isNull);
    });

    test('toggleClipReverse flips isReversed state deterministically', () {
      expect(viewModel.selectedClip!.isReversed, isFalse);
      viewModel.toggleClipReverse();
      expect(viewModel.selectedClip!.isReversed, isTrue);
      viewModel.toggleClipReverse();
      expect(viewModel.selectedClip!.isReversed, isFalse);
    });

    test('PIP overlay speed ramping, freeze frame and reverse', () {
      const pip = OverlayClip(
        id: 'overlay_video_1',
        title: 'Video Overlay',
        startTime: Duration.zero,
        duration: Duration(seconds: 6),
        speed: 1.0,
      );
      viewModel.addOverlayClip(pip);
      viewModel.selectOverlayClip(0);

      viewModel.setOverlaySpeed('overlay_video_1', 2.0);
      expect(viewModel.overlayClips[0].speed, 2.0);

      viewModel.setOverlaySpeedCurve('overlay_video_1', SpeedCurve.smooth());
      expect(viewModel.overlayClips[0].speedCurve!.type, SpeedCurvePresetType.smooth);

      viewModel.toggleOverlayReverse('overlay_video_1');
      expect(viewModel.overlayClips[0].isReversed, isTrue);

      viewModel.addOverlayFreezeFrame(
        'overlay_video_1',
        timelineOffset: const Duration(seconds: 1),
        duration: const Duration(seconds: 2),
      );
      expect(viewModel.overlayClips[0].freezeFrame, isNotNull);
      expect(viewModel.overlayClips[0].freezeFrame!.duration.inSeconds, 2);

      viewModel.removeOverlayFreezeFrame('overlay_video_1');
      expect(viewModel.overlayClips[0].freezeFrame, isNull);
    });
  });

  group('4. Project Persistence & Backward Compatibility Tests', () {
    test('Legacy video clip JSON without speedCurve or freezeFrame deserializes safely', () {
      final legacyJson = {
        'id': 'legacy_1',
        'assetId': 'asset_1',
        'title': 'Legacy Clip',
        'originalDuration': 10000,
        'trimStart': 0,
        'trimEnd': 10000,
        'speed': 1.0,
      };

      final clip = VideoClip.fromJson(legacyJson);
      expect(clip.speedCurve, isNull);
      expect(clip.freezeFrame, isNull);
      expect(clip.isFrozen, isFalse);
      expect(clip.isReversed, isFalse);
      expect(clip.speed, 1.0);
      expect(clip.activeDuration.inMilliseconds, 10000);
    });

    test('Full project JSON round-trip with speed ramping, freeze frame and reverse', () {
      final clip = VideoClip(
        id: 'clip_full_1',
        assetId: 'asset_full_1',
        title: 'Full Speed Clip',
        originalDuration: const Duration(seconds: 12),
        trimStart: const Duration(seconds: 1),
        trimEnd: const Duration(seconds: 11),
        speed: 1.5,
        speedCurve: SpeedCurve.hero(),
        freezeFrame: const FreezeFrame(
          timelineOffset: Duration(seconds: 2),
          duration: Duration(seconds: 3),
          sourceTime: Duration(seconds: 3),
        ),
        isReversed: true,
        previewGradient: const [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      );

      final project = Project(
        id: 'proj_speed_test',
        name: 'Speed Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        videoClips: [clip],
      );

      final projectJson = project.toJson();
      final restored = Project.fromJson(projectJson);

      expect(restored.videoClips.length, 1);
      final restoredClip = restored.videoClips[0];
      expect(restoredClip.id, 'clip_full_1');
      expect(restoredClip.speed, 1.5);
      expect(restoredClip.isReversed, isTrue);
      expect(restoredClip.speedCurve, isNotNull);
      expect(restoredClip.speedCurve!.type, SpeedCurvePresetType.hero);
      expect(restoredClip.freezeFrame, isNotNull);
      expect(restoredClip.freezeFrame!.timelineOffset, const Duration(seconds: 2));
      expect(restoredClip.freezeFrame!.duration, const Duration(seconds: 3));
    });
  });
}
