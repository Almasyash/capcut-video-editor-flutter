import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';

void main() {
  group('SpeedCurvePoint', () {
    test('creates point with valid timeRatio and speedMultiplier', () {
      const pt = SpeedCurvePoint(timeRatio: 0.35, speedMultiplier: 2.5);
      expect(pt.timeRatio, 0.35);
      expect(pt.speedMultiplier, 2.5);
    });

    test('serializes to and from JSON accurately', () {
      const original = SpeedCurvePoint(timeRatio: 0.5, speedMultiplier: 3.2);
      final json = original.toJson();
      final reconstructed = SpeedCurvePoint.fromJson(json);

      expect(reconstructed, equals(original));
      expect(reconstructed.timeRatio, 0.5);
      expect(reconstructed.speedMultiplier, 3.2);
    });

    test('copyWith works correctly', () {
      const original = SpeedCurvePoint(timeRatio: 0.2, speedMultiplier: 1.0);
      final updated = original.copyWith(speedMultiplier: 4.0);

      expect(updated.timeRatio, 0.2);
      expect(updated.speedMultiplier, 4.0);
    });
  });

  group('SpeedCurve Presets', () {
    test('all presets have valid points spanning 0.0 to 1.0', () {
      final presets = [
        SpeedCurve.montage(),
        SpeedCurve.hero(),
        SpeedCurve.bullet(),
        SpeedCurve.jumpCut(),
        SpeedCurve.flashIn(),
        SpeedCurve.flashOut(),
        SpeedCurve.bubbly(),
        SpeedCurve.custom(),
      ];

      for (final curve in presets) {
        expect(curve.points.isNotEmpty, isTrue);
        expect(curve.points.first.timeRatio, 0.0);
        expect(curve.points.last.timeRatio, 1.0);
        expect(curve.keepPitch, isTrue);
        expect(curve.smoothSlowMo, isTrue);
        expect(curve.averageSpeed, greaterThan(0.0));
      }
    });

    test('bubbly preset has alternating slow and pop speed points', () {
      final bubbly = SpeedCurve.bubbly();
      expect(bubbly.type, SpeedCurvePresetType.bubbly);
      expect(bubbly.points.length, 5);
      expect(bubbly.evaluateSpeedAt(0.2), closeTo(0.4, 0.01));
      expect(bubbly.evaluateSpeedAt(0.5), closeTo(3.2, 0.01));
      expect(bubbly.evaluateSpeedAt(0.8), closeTo(0.4, 0.01));
    });
  });

  group('SpeedCurve Math & Integral Mapping', () {
    test('evaluateSpeedAt interpolates linearly between control points', () {
      const curve = SpeedCurve(
        type: SpeedCurvePresetType.custom,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 5.0),
        ],
      );

      expect(curve.evaluateSpeedAt(0.0), 1.0);
      expect(curve.evaluateSpeedAt(0.5), 3.0);
      expect(curve.evaluateSpeedAt(1.0), 5.0);
      // Clamping outside 0..1
      expect(curve.evaluateSpeedAt(-0.5), 1.0);
      expect(curve.evaluateSpeedAt(1.5), 5.0);
    });

    test('averageSpeed computes exact trapezoidal area', () {
      // Constant 2.0x speed
      const constantSpeed = SpeedCurve(
        type: SpeedCurvePresetType.custom,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 2.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 2.0),
        ],
      );
      expect(constantSpeed.averageSpeed, closeTo(2.0, 0.001));

      // Linear ramp from 1.0x to 3.0x -> average is 2.0x
      const ramp = SpeedCurve(
        type: SpeedCurvePresetType.custom,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 1.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 3.0),
        ],
      );
      expect(ramp.averageSpeed, closeTo(2.0, 0.001));
    });

    test('getSourceProgressAt satisfies boundary conditions 0.0 and 1.0', () {
      final presets = [
        SpeedCurve.montage(),
        SpeedCurve.hero(),
        SpeedCurve.bullet(),
        SpeedCurve.jumpCut(),
        SpeedCurve.flashIn(),
        SpeedCurve.flashOut(),
        SpeedCurve.bubbly(),
      ];

      for (final curve in presets) {
        expect(curve.getSourceProgressAt(0.0), 0.0);
        expect(curve.getSourceProgressAt(1.0), 1.0);
        expect(curve.getSourceProgressAt(-0.1), 0.0);
        expect(curve.getSourceProgressAt(1.1), 1.0);
      }
    });

    test('getSourceProgressAt is strictly monotonic', () {
      final curve = SpeedCurve.hero();
      double prevProgress = -0.0001;

      for (int i = 0; i <= 100; i++) {
        final t = i / 100.0;
        final progress = curve.getSourceProgressAt(t);
        expect(progress, greaterThanOrEqualTo(prevProgress));
        expect(progress, greaterThanOrEqualTo(0.0));
        expect(progress, lessThanOrEqualTo(1.0));
        prevProgress = progress;
      }
    });

    test('constant speed curve yields exactly linear progress', () {
      const constantCurve = SpeedCurve(
        type: SpeedCurvePresetType.custom,
        points: [
          SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: 3.0),
          SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: 3.0),
        ],
      );

      expect(constantCurve.getSourceProgressAt(0.25), closeTo(0.25, 0.001));
      expect(constantCurve.getSourceProgressAt(0.50), closeTo(0.50, 0.001));
      expect(constantCurve.getSourceProgressAt(0.75), closeTo(0.75, 0.001));
    });
  });

  group('SpeedCurve Serialization & copyWith', () {
    test('toJson and fromJson preserves all fields including keepPitch and smoothSlowMo', () {
      final curve = SpeedCurve.montage(keepPitch: false, smoothSlowMo: false);
      final json = curve.toJson();

      expect(json['type'], 'montage');
      expect(json['keepPitch'], isFalse);
      expect(json['smoothSlowMo'], isFalse);

      final decoded = SpeedCurve.fromJson(json);
      expect(decoded.type, SpeedCurvePresetType.montage);
      expect(decoded.keepPitch, isFalse);
      expect(decoded.smoothSlowMo, isFalse);
      expect(decoded.points.length, curve.points.length);
      expect(decoded, equals(curve));
    });

    test('copyWith modifies selected properties correctly', () {
      final original = SpeedCurve.bullet();
      final modified = original.copyWith(keepPitch: false);

      expect(modified.keepPitch, isFalse);
      expect(modified.smoothSlowMo, isTrue);
      expect(modified.type, SpeedCurvePresetType.bullet);
    });
  });

  group('VideoClip integration with SpeedCurve', () {
    test('activeDuration uses speedCurve.averageSpeed', () {
      final curve = SpeedCurve.bullet(); // average speed around 2.44
      final clip = VideoClip(
        id: 'test_clip_1',
        assetId: 'asset_1',
        title: 'Speed Test Clip',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        speedCurve: curve,
        previewGradient: const [],
      );

      final expectedMs = (10000 / curve.averageSpeed).round();
      expect(clip.activeDuration.inMilliseconds, equals(expectedMs));
    });
  });
}
