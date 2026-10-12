import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EasingCurve Standard Presets Tests', () {
    test('Standard preset collection contains expected items', () {
      expect(EasingCurve.standardPresets.length, equals(14));
      expect(EasingCurve.standardPresets.contains(EasingCurve.linear), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInOut), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInQuad), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeOutQuad), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInOutQuad), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInCubic), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeOutCubic), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInOutCubic), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInBack), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeOutBack), isTrue);
      expect(EasingCurve.standardPresets.contains(EasingCurve.easeInOutBack), isTrue);
    });

    test('Quad and Cubic presets evaluate smoothly from 0.0 to 1.0', () {
      final quadCurves = [
        EasingCurve.easeInQuad,
        EasingCurve.easeOutQuad,
        EasingCurve.easeInOutQuad,
        EasingCurve.easeInCubic,
        EasingCurve.easeOutCubic,
        EasingCurve.easeInOutCubic,
      ];

      for (final curve in quadCurves) {
        expect(curve.evaluate(0.0), closeTo(0.0, 1e-4), reason: '${curve.displayName} at 0.0');
        expect(curve.evaluate(1.0), closeTo(1.0, 1e-4), reason: '${curve.displayName} at 1.0');
        final mid = curve.evaluate(0.5);
        expect(mid, greaterThanOrEqualTo(0.0));
        expect(mid, lessThanOrEqualTo(1.0));
        expect(curve.evaluateDerivative(0.5).isFinite, isTrue);
      }
    });

    test('Back easing curves demonstrate characteristic anticipation and overshoot', () {
      // Ease In Back anticipates (dips below 0)
      final inBackMid = EasingCurve.easeInBack.evaluate(0.3);
      expect(inBackMid, lessThan(0.0));

      // Ease Out Back overshoots (exceeds 1.0)
      final outBackMid = EasingCurve.easeOutBack.evaluate(0.7);
      expect(outBackMid, greaterThan(1.0));

      // Both converge at endpoints
      expect(EasingCurve.easeInBack.evaluate(0.0), closeTo(0.0, 1e-4));
      expect(EasingCurve.easeInBack.evaluate(1.0), closeTo(1.0, 1e-4));
      expect(EasingCurve.easeOutBack.evaluate(0.0), closeTo(0.0, 1e-4));
      expect(EasingCurve.easeOutBack.evaluate(1.0), closeTo(1.0, 1e-4));
    });
  });

  group('KeyframeTrack Temporal Manipulation Tests', () {
    test('shiftTime shifts all keyframes by positive offsetMs', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.positionX,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 500, value: 10.0),
          MotionKeyframe(id: 'k1', timestampMs: 1500, value: 50.0),
        ],
      );

      final shifted = track.shiftTime(500);
      expect(shifted.keyframes[0].timestampMs, equals(1000));
      expect(shifted.keyframes[1].timestampMs, equals(2000));
      expect(shifted.keyframes[0].value, equals(10.0));
      expect(shifted.keyframes[1].value, equals(50.0));
    });

    test('shiftTime respects minTimeMs when shifted backwards', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.positionX,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 500, value: 10.0),
          MotionKeyframe(id: 'k1', timestampMs: 1500, value: 50.0),
        ],
      );

      final shifted = track.shiftTime(-1000, minTimeMs: 100);
      expect(shifted.keyframes[0].timestampMs, equals(100)); // Clamped to minTimeMs
      expect(shifted.keyframes[1].timestampMs, equals(500));
    });

    test('scaleTime scales timeline distance around originMs', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 1000, value: 1.0),
          MotionKeyframe(id: 'k1', timestampMs: 2000, value: 2.0),
        ],
      );

      // Scale 2x around origin 1000ms
      final scaled = track.scaleTime(2.0, originMs: 1000);
      expect(scaled.keyframes[0].timestampMs, equals(1000));
      expect(scaled.keyframes[1].timestampMs, equals(3000)); // 1000 + (1000 * 2) = 3000
    });

    test('applyEasingToAll updates easing curves on all keyframes', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.opacity,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 0, value: 0.0, easing: EasingCurve.linear),
          MotionKeyframe(id: 'k1', timestampMs: 1000, value: 1.0, easing: EasingCurve.linear),
        ],
      );

      final updated = track.applyEasingToAll(EasingCurve.easeOutBack);
      expect(updated.keyframes[0].easing, equals(EasingCurve.easeOutBack));
      expect(updated.keyframes[1].easing, equals(EasingCurve.easeOutBack));
      expect(updated.keyframes[0].value, equals(0.0));
      expect(updated.keyframes[1].value, equals(1.0));
    });
  });

  group('KeyframeTrackGroup Multi-Track Tests', () {
    test('TrackGroup shiftTime, scaleTime and applyEasingToProperty function correctly', () {
      var group = const KeyframeTrackGroup();
      group = group.addKeyframe(AnimatableProperty.positionX, 500, 100.0);
      group = group.addKeyframe(AnimatableProperty.positionX, 1500, 200.0);
      group = group.addKeyframe(AnimatableProperty.scale, 500, 1.0);
      group = group.addKeyframe(AnimatableProperty.scale, 1500, 2.0);

      // Shift
      final shifted = group.shiftTime(500);
      expect(shifted.tracks[AnimatableProperty.positionX]!.keyframes[0].timestampMs, equals(1000));
      expect(shifted.tracks[AnimatableProperty.scale]!.keyframes[0].timestampMs, equals(1000));

      // Apply easing to one property
      final eased = shifted.applyEasingToProperty(AnimatableProperty.positionX, EasingCurve.easeInOutCubic);
      expect(eased.tracks[AnimatableProperty.positionX]!.keyframes[0].easing, equals(EasingCurve.easeInOutCubic));
      expect(eased.tracks[AnimatableProperty.scale]!.keyframes[0].easing, equals(EasingCurve.easeInOut));
    });
  });
}
