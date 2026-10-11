import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EasingCurve Derivative & Tangent Tests', () {
    test('Linear curve derivative is constantly 1.0 across unit interval', () {
      expect(EasingCurve.linear.evaluateDerivative(0.0), closeTo(1.0, 1e-4));
      expect(EasingCurve.linear.evaluateDerivative(0.25), closeTo(1.0, 1e-4));
      expect(EasingCurve.linear.evaluateDerivative(0.5), closeTo(1.0, 1e-4));
      expect(EasingCurve.linear.evaluateDerivative(0.75), closeTo(1.0, 1e-4));
      expect(EasingCurve.linear.evaluateDerivative(1.0), closeTo(1.0, 1e-4));
    });

    test('Hold curve derivative is 0.0 everywhere', () {
      expect(EasingCurve.hold.evaluateDerivative(0.0), equals(0.0));
      expect(EasingCurve.hold.evaluateDerivative(0.5), equals(0.0));
      expect(EasingCurve.hold.evaluateDerivative(1.0), equals(0.0));
    });

    test('Ease In derivative starts at 0.0 and ramps up to 3.0 at completion', () {
      expect(EasingCurve.easeIn.evaluateDerivative(0.0), equals(0.0));
      expect(EasingCurve.easeIn.evaluateDerivative(0.5), closeTo(0.75, 1e-4));
      expect(EasingCurve.easeIn.evaluateDerivative(1.0), equals(3.0));
    });

    test('Ease Out derivative starts at 3.0 and decelerates to 0.0 at completion', () {
      expect(EasingCurve.easeOut.evaluateDerivative(0.0), equals(3.0));
      expect(EasingCurve.easeOut.evaluateDerivative(0.5), closeTo(0.75, 1e-4));
      expect(EasingCurve.easeOut.evaluateDerivative(1.0), equals(0.0));
    });

    test('Ease In-Out derivative has zero velocity at endpoints and peaks at 3.0 at midpoint', () {
      expect(EasingCurve.easeInOut.evaluateDerivative(0.0), equals(0.0));
      expect(EasingCurve.easeInOut.evaluateDerivative(0.5), closeTo(3.0, 1e-4));
      expect(EasingCurve.easeInOut.evaluateDerivative(1.0), equals(0.0));
    });

    test('Cubic Bezier derivative evaluates smoothly and safely without NaN', () {
      final bezier = EasingCurve.cubic(0.25, 0.1, 0.25, 1.0);
      expect(bezier.evaluateDerivative(0.0).isFinite, isTrue);
      expect(bezier.evaluateDerivative(0.5).isFinite, isTrue);
      expect(bezier.evaluateDerivative(1.0).isFinite, isTrue);
      expect(bezier.evaluateDerivative(0.5), greaterThan(0.0));
    });

    test('TangentMode preserves state and serializes correctly', () {
      final curve = EasingCurve.cubic(
        0.3,
        0.2,
        0.7,
        0.8,
        tangentMode: TangentMode.broken,
      );

      expect(curve.tangentMode, equals(TangentMode.broken));

      final json = curve.toJson();
      expect(json['tangentMode'], equals('broken'));

      final restored = EasingCurve.fromJson(json);
      expect(restored.tangentMode, equals(TangentMode.broken));
      expect(restored, equals(curve));
    });
  });

  group('KeyframeTrack Velocity & Direct Manipulation Tests', () {
    test('evaluateDerivative computes exact physical velocity in units/second', () {
      // Track moving from 0.0 at 0s to 100.0 at 2s with linear easing
      const track = KeyframeTrack(
        property: AnimatableProperty.positionX,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 0, value: 0.0, easing: EasingCurve.linear),
          MotionKeyframe(id: 'k1', timestampMs: 2000, value: 100.0, easing: EasingCurve.linear),
        ],
      );

      // Outside range -> 0 velocity
      expect(track.evaluateDerivative(-0.5), equals(0.0));
      expect(track.evaluateDerivative(0.0), equals(0.0));
      expect(track.evaluateDerivative(2.5), equals(0.0));

      // Constant velocity 50.0 px/s inside [0, 2s]
      expect(track.evaluateDerivative(0.5), closeTo(50.0, 1e-3));
      expect(track.evaluateDerivative(1.0), closeTo(50.0, 1e-3));
      expect(track.evaluateDerivative(1.5), closeTo(50.0, 1e-3));
    });

    test('updateKeyframeValueAt modifies keyframe value without altering timestamp or order', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        keyframes: [
          MotionKeyframe(id: 'k0', timestampMs: 0, value: 1.0),
          MotionKeyframe(id: 'k1', timestampMs: 1000, value: 2.0),
          MotionKeyframe(id: 'k2', timestampMs: 2000, value: 1.5),
        ],
      );

      final updated = track.updateKeyframeValueAt(1000, 3.5);
      expect(updated.keyframes.length, equals(3));
      expect(updated.keyframes[1].timestampMs, equals(1000));
      expect(updated.keyframes[1].value, equals(3.5));
      expect(updated.keyframes[0].value, equals(1.0));
      expect(updated.keyframes[2].value, equals(1.5));
    });

    test('KeyframeTrackGroup evaluates multi-track velocity', () {
      var group = const KeyframeTrackGroup();
      group = group.addKeyframe(AnimatableProperty.positionX, 0, 0.0, easing: EasingCurve.linear);
      group = group.addKeyframe(AnimatableProperty.positionX, 1000, 200.0, easing: EasingCurve.linear);

      expect(group.evaluateDerivative(AnimatableProperty.positionX, 0.5), closeTo(200.0, 1e-3));
      expect(group.evaluateDerivative(AnimatableProperty.scale, 0.5), equals(0.0));
    });
  });
}
