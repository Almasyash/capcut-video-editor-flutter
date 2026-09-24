import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Keyframe Interpolation & Curve Tests', () {
    test('KeyframeCurve evaluations at boundaries and midpoint', () {
      // Linear
      expect(KeyframeCurve.linear.evaluate(0.0), equals(0.0));
      expect(KeyframeCurve.linear.evaluate(0.5), equals(0.5));
      expect(KeyframeCurve.linear.evaluate(1.0), equals(1.0));

      // Ease In Out: S-curve behavior
      expect(KeyframeCurve.easeInOut.evaluate(0.0), closeTo(0.0, 1e-4));
      expect(KeyframeCurve.easeInOut.evaluate(0.5), closeTo(0.5, 1e-4));
      expect(KeyframeCurve.easeInOut.evaluate(1.0), closeTo(1.0, 1e-4));
      // S-curve slows at beginning and ends:
      expect(KeyframeCurve.easeInOut.evaluate(0.25), lessThan(0.25));
      expect(KeyframeCurve.easeInOut.evaluate(0.75), greaterThan(0.75));

      // Ease In
      expect(KeyframeCurve.easeIn.evaluate(0.5), lessThan(0.5));

      // Ease Out
      expect(KeyframeCurve.easeOut.evaluate(0.5), greaterThan(0.5));
    });

    test('Keyframe.interpolate with empty keyframes returns null', () {
      final result = Keyframe.interpolate(
        keyframes: [],
        timeInSeconds: 2.0,
      );
      expect(result, isNull);
    });

    test('Keyframe.interpolate clamps to first/last keyframe when outside range', () {
      final kfs = [
        Keyframe(
          id: 'kf1',
          timeInSeconds: 1.0,
          scale: 1.0,
          rotationDegrees: 0.0,
          positionX: 0.0,
          positionY: 0.0,
          opacity: 1.0,
        ),
        Keyframe(
          id: 'kf2',
          timeInSeconds: 3.0,
          scale: 2.0,
          rotationDegrees: 90.0,
          positionX: 100.0,
          positionY: 50.0,
          opacity: 0.5,
        ),
      ];

      // Before first
      final before = Keyframe.interpolate(keyframes: kfs, timeInSeconds: 0.5)!;
      expect(before.scale, equals(1.0));
      expect(before.positionX, equals(0.0));

      // After last
      final after = Keyframe.interpolate(keyframes: kfs, timeInSeconds: 5.0)!;
      expect(after.scale, equals(2.0));
      expect(after.rotationDegrees, equals(90.0));
      expect(after.positionX, equals(100.0));
      expect(after.opacity, equals(0.5));
    });

    test('Keyframe.interpolate performs smooth cubic ease-in-out interpolation', () {
      final kfs = [
        Keyframe(
          id: 'kf1',
          timeInSeconds: 0.0,
          scale: 1.0,
          rotationDegrees: 0.0,
          positionX: 0.0,
          positionY: 0.0,
          opacity: 1.0,
          curve: KeyframeCurve.easeInOut,
        ),
        Keyframe(
          id: 'kf2',
          timeInSeconds: 2.0,
          scale: 2.0,
          rotationDegrees: 180.0,
          positionX: 100.0,
          positionY: -50.0,
          opacity: 0.0,
        ),
      ];

      // Exact midpoint: t = 1.0 (50% progress)
      final mid = Keyframe.interpolate(keyframes: kfs, timeInSeconds: 1.0)!;
      expect(mid.scale, closeTo(1.5, 0.01));
      expect(mid.rotationDegrees, closeTo(90.0, 0.01));
      expect(mid.positionX, closeTo(50.0, 0.01));
      expect(mid.positionY, closeTo(-25.0, 0.01));
      expect(mid.opacity, closeTo(0.5, 0.01));

      // Quarter point: t = 0.5 (25% progress in time, but eased progress < 25%)
      final quarter = Keyframe.interpolate(keyframes: kfs, timeInSeconds: 0.5)!;
      expect(quarter.scale, lessThan(1.25)); // due to easeInOut slow start
    });
  });

  group('EditorViewModel Keyframe Workflow Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
      viewModel.initForTesting();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('addKeyframeAtPlayhead adds keyframe with current spatial transform', () {
      expect(viewModel.videoClips, isNotEmpty);
      viewModel.selectClip(0);
      final clip = viewModel.videoClips[0];
      expect(clip.keyframes, isEmpty);

      // Seek to 1.5 seconds within clip 0
      viewModel.seekTo(1.5);
      viewModel.addKeyframeAtPlayhead();

      final updatedClip = viewModel.videoClips[0];
      expect(updatedClip.keyframes.length, equals(1));
      final kf = updatedClip.keyframes[0];
      expect(kf.timeInSeconds, closeTo(1.5, 0.05));
      expect(viewModel.hasKeyframeAtPlayhead, isTrue);
    });

    test('removeKeyframeAtPlayhead removes keyframe when playhead is on diamond', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      expect(viewModel.hasKeyframeAtPlayhead, isTrue);

      viewModel.removeKeyframeAtPlayhead();
      expect(viewModel.videoClips[0].keyframes, isEmpty);
      expect(viewModel.hasKeyframeAtPlayhead, isFalse);
    });

    test('Previous/Next keyframe navigation moves playhead accurately', () {
      viewModel.selectClip(0);

      // Add 3 keyframes at 1.0s, 2.5s, 4.0s
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(2.5);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(4.0);
      viewModel.addKeyframeAtPlayhead();

      expect(viewModel.videoClips[0].keyframes.length, equals(3));

      // At 2.5s: has both previous and next
      viewModel.seekTo(2.5);
      expect(viewModel.hasPreviousKeyframe, isTrue);
      expect(viewModel.hasNextKeyframe, isTrue);

      // Jump to previous -> should land on 1.0s
      viewModel.jumpToPreviousKeyframe();
      expect(viewModel.currentTimeInSeconds, closeTo(1.0, 0.05));
      expect(viewModel.hasPreviousKeyframe, isFalse);
      expect(viewModel.hasNextKeyframe, isTrue);

      // Jump to next twice -> should land on 4.0s
      viewModel.jumpToNextKeyframe();
      expect(viewModel.currentTimeInSeconds, closeTo(2.5, 0.05));
      viewModel.jumpToNextKeyframe();
      expect(viewModel.currentTimeInSeconds, closeTo(4.0, 0.05));
      expect(viewModel.hasNextKeyframe, isFalse);
    });

    test('updateClipTransform auto-records keyframe if clip already has keyframes', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();

      // Now seek to 3.0s and edit spatial transform (pan/zoom on canvas)
      viewModel.seekTo(3.0);
      viewModel.updateClipTransform(
        viewModel.videoClips[0].id,
        xPos: 50.0,
        yPos: -20.0,
        scale: 1.5,
        rotationAngle: 0.5,
      );

      final clip = viewModel.videoClips[0];
      // Should now have 2 keyframes because auto-keyframing recorded the transformation!
      expect(clip.keyframes.length, equals(2));
      final kf2 = clip.keyframes.firstWhere((k) => (k.timeInSeconds - 3.0).abs() < 0.1);
      expect(kf2.positionX, equals(50.0));
      expect(kf2.positionY, equals(-20.0));
      expect(kf2.scale, equals(1.5));
    });

    test('getInterpolatedOverlayKeyframe correctly animates OverlayClip PIP layers', () {
      final overlay = OverlayClip(
        id: 'overlay_1',
        title: 'PIP Test',
        startTime: const Duration(seconds: 0),
        duration: const Duration(seconds: 5),
        keyframes: [
          Keyframe(
            id: 'okf1',
            timeInSeconds: 0.0,
            scale: 0.5,
            rotationDegrees: 0.0,
            positionX: 0.0,
            positionY: 0.0,
            opacity: 1.0,
          ),
          Keyframe(
            id: 'okf2',
            timeInSeconds: 4.0,
            scale: 1.0,
            rotationDegrees: 90.0,
            positionX: 100.0,
            positionY: 100.0,
            opacity: 0.8,
          ),
        ],
      );

      final interpolated = viewModel.getInterpolatedOverlayKeyframe(overlay, 2.0);
      expect(interpolated, isNotNull);
      expect(interpolated!.scale, closeTo(0.75, 0.05));
      expect(interpolated.rotationDegrees, closeTo(45.0, 1.0));
      expect(interpolated.positionX, closeTo(50.0, 2.0));
    });
  });
}
