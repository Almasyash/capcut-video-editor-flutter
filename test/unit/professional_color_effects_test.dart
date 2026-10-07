import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/rgb_curves_model.dart';
import 'package:capcut_video_editor/domain/models/lut_config.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Professional Color Adjustments & Tone Controls Tests', () {
    test('neutral ColorAdjustments has isDefault true and getColorFilter null', () {
      const adjustments = ColorAdjustments();

      expect(adjustments.isDefault, isTrue);
      expect(adjustments.brightness, 0.0);
      expect(adjustments.contrast, 1.0);
      expect(adjustments.saturation, 1.0);
      expect(adjustments.exposure, 0.0);
      expect(adjustments.temperature, 0.0);
      expect(adjustments.tint, 0.0);
      expect(adjustments.highlights, 0.0);
      expect(adjustments.shadows, 0.0);
      expect(adjustments.blacks, 0.0);
      expect(adjustments.whites, 0.0);
      expect(adjustments.vignette, 0.0);
      expect(adjustments.vignetteRadius, 0.8);
      expect(adjustments.vignetteSoftness, 0.5);
      expect(adjustments.sharpness, 0.0);
      expect(adjustments.curves.isIdentity, isTrue);
      expect(adjustments.lut, isNull);

      // CRITICAL: Must be null to prevent grey overlay / degradation
      expect(adjustments.getColorFilter(), isNull);
    });

    test('non-default parameters set isDefault false and produce non-null ColorFilter', () {
      final tests = [
        const ColorAdjustments(brightness: 0.1),
        const ColorAdjustments(contrast: 1.2),
        const ColorAdjustments(saturation: 1.2),
        const ColorAdjustments(exposure: 0.1),
        const ColorAdjustments(temperature: 0.1),
        const ColorAdjustments(tint: 0.1),
        const ColorAdjustments(highlights: 0.1),
        const ColorAdjustments(shadows: 0.1),
        const ColorAdjustments(blacks: 0.1),
        const ColorAdjustments(whites: 0.1),
      ];

      for (final adj in tests) {
        expect(adj.isDefault, isFalse);
        expect(adj.getColorFilter(), isNotNull);
      }
    });

    test('ColorAdjustments copyWith and JSON roundtrip preserves all 12 controls and curves', () {
      final curves = RgbCurvesModel.identity.addPoint(
        CurveChannel.red,
        const CurvePoint(0.5, 0.7),
      );
      const lut = LutConfig(
        id: 'test_lut',
        name: 'Test LUT',
        title: 'TestLUT',
        size: 2,
        is3D: false,
      );

      final original = ColorAdjustments(
        brightness: 0.15,
        contrast: 0.25,
        saturation: -0.1,
        exposure: 0.3,
        temperature: -0.2,
        tint: 0.05,
        highlights: 0.4,
        shadows: -0.2,
        blacks: 0.1,
        whites: -0.15,
        vignette: 0.6,
        vignetteRadius: 0.75,
        vignetteSoftness: 0.4,
        sharpness: 0.8,
        curves: curves,
        lut: lut,
      );

      final json = original.toJson();
      final reconstituted = ColorAdjustments.fromJson(json);

      expect(reconstituted.brightness, equals(original.brightness));
      expect(reconstituted.contrast, equals(original.contrast));
      expect(reconstituted.saturation, equals(original.saturation));
      expect(reconstituted.exposure, equals(original.exposure));
      expect(reconstituted.temperature, equals(original.temperature));
      expect(reconstituted.tint, equals(original.tint));
      expect(reconstituted.highlights, equals(original.highlights));
      expect(reconstituted.shadows, equals(original.shadows));
      expect(reconstituted.blacks, equals(original.blacks));
      expect(reconstituted.whites, equals(original.whites));
      expect(reconstituted.vignette, equals(original.vignette));
      expect(reconstituted.vignetteRadius, equals(original.vignetteRadius));
      expect(reconstituted.vignetteSoftness, equals(original.vignetteSoftness));
      expect(reconstituted.sharpness, equals(original.sharpness));
      expect(reconstituted.curves.isIdentity, isFalse);
      expect(reconstituted.curves.redPoints.length, equals(3));
      expect(reconstituted.lut?.title, equals('TestLUT'));
    });
  });

  group('RGB Curves Model Tests', () {
    test('identity curves evaluate identity line f(x) = x', () {
      const curves = RgbCurvesModel.identity;
      expect(curves.isIdentity, isTrue);

      for (final ch in CurveChannel.values) {
        expect(curves.evaluate(0.0, ch), closeTo(0.0, 1e-4));
        expect(curves.evaluate(0.25, ch), closeTo(0.25, 1e-4));
        expect(curves.evaluate(0.5, ch), closeTo(0.5, 1e-4));
        expect(curves.evaluate(0.75, ch), closeTo(0.75, 1e-4));
        expect(curves.evaluate(1.0, ch), closeTo(1.0, 1e-4));
      }
    });

    test('adding and removing curve points updates evaluation correctly', () {
      var curves = RgbCurvesModel.identity;
      curves = curves.addPoint(CurveChannel.master, const CurvePoint(0.5, 0.8));

      expect(curves.isIdentity, isFalse);
      expect(curves.masterPoints.length, 3);
      expect(curves.evaluate(0.5, CurveChannel.master), closeTo(0.8, 1e-4));
      expect(curves.evaluate(0.25, CurveChannel.master), closeTo(0.4, 1e-4));

      // Removing the point restores identity
      curves = curves.removePoint(CurveChannel.master, 1);
      expect(curves.masterPoints.length, 2);
      expect(curves.isIdentity, isTrue);
      expect(curves.evaluate(0.5, CurveChannel.master), closeTo(0.5, 1e-4));
    });

    test('resetChannel restores individual channel to identity', () {
      var curves = RgbCurvesModel.identity;
      curves = curves.addPoint(CurveChannel.green, const CurvePoint(0.3, 0.7));
      expect(curves.isIdentity, isFalse);

      curves = curves.resetChannel(CurveChannel.green);
      expect(curves.isIdentity, isTrue);
    });

    test('curves JSON serialization and deserialization', () {
      final curves = RgbCurvesModel.identity.addPoint(
        CurveChannel.blue,
        const CurvePoint(0.4, 0.6),
      );
      final json = curves.toJson();
      final restored = RgbCurvesModel.fromJson(json);

      expect(restored.bluePoints.length, 3);
      expect(restored.bluePoints[1].x, 0.4);
      expect(restored.bluePoints[1].y, 0.6);
    });
  });

  group('LUT Config & .cube Parser Tests', () {
    test('parses 3D .cube file string correctly', () {
      const cubeData = '''
# 3D LUT Test File
TITLE "Test3D"
LUT_3D_SIZE 2
0.0 0.0 0.0
1.0 0.0 0.0
0.0 1.0 0.0
1.0 1.0 0.0
0.0 0.0 1.0
1.0 0.0 1.0
0.0 1.0 1.0
1.0 1.0 1.0
''';

      final lut = CubeLutParser.parse(cubeData);
      expect(lut, isNotNull);
      expect(lut!.title, equals('Test3D'));
      expect(lut.is3D, isTrue);
      expect(lut.size, equals(2));
      expect(lut.table.length, equals(24)); // 2^3 * 3 = 24 entries
    });

    test('parses 1D .cube file string correctly', () {
      const cube1DData = '''
TITLE "Test1D"
LUT_1D_SIZE 2
0.0 0.0 0.0
1.0 1.0 1.0
''';

      final lut = CubeLutParser.parse(cube1DData);
      expect(lut, isNotNull);
      expect(lut!.title, equals('Test1D'));
      expect(lut.is1D, isTrue);
      expect(lut.size, equals(2));
      expect(lut.table.length, equals(6));
    });

    test('handles invalid cube data gracefully by returning null', () {
      expect(CubeLutParser.parse(''), isNull);
      expect(CubeLutParser.parse('NO VALID HEADERS HERE'), isNull);
      expect(CubeLutParser.parse('LUT_3D_SIZE not_a_number'), isNull);
    });

    test('LutConfig JSON serialization and deserialization', () {
      const lut = LutConfig(
        id: 'cinematic',
        name: 'Cinematic',
        title: 'Cinematic',
        size: 33,
        intensity: 0.8,
        is3D: true,
      );
      final json = lut.toJson();
      final restored = LutConfig.fromJson(json);

      expect(restored.id, equals('cinematic'));
      expect(restored.name, equals('Cinematic'));
      expect(restored.title, equals('Cinematic'));
      expect(restored.is3D, isTrue);
      expect(restored.size, equals(33));
      expect(restored.intensity, equals(0.8));
    });
  });

  group('12 Professional Filter Presets Tests', () {
    test('all 12 presets are available in EditorFilter.presets', () {
      final presetIds = EditorFilter.presets.map((f) => f.id).toList();

      const expectedIds = [
        'none',
        'vivid',
        'warm',
        'cool',
        'vintage',
        'cinema',
        'fade',
        'mono',
        'black_white',
        'sepia',
        'dramatic',
        'portrait',
      ];

      for (final id in expectedIds) {
        expect(presetIds.contains(id), isTrue, reason: 'Preset $id should be present');
      }
    });

    test('None preset returns null filter at any intensity', () {
      final noneFilter = EditorFilter.presets.firstWhere((f) => f.id == 'none');
      expect(noneFilter.getColorFilter(1.0), isNull);
      expect(noneFilter.getColorFilter(0.5), isNull);
      expect(noneFilter.getColorFilter(0.0), isNull);
    });

    test('Any filter at 0.0 intensity returns null (blended to identity)', () {
      for (final filter in EditorFilter.presets) {
        expect(filter.getColorFilter(0.0), isNull);
      }
    });

    test('Active filters produce non-null ColorFilter at >0 intensity', () {
      for (final filter in EditorFilter.presets) {
        if (filter.id == 'none') continue;
        expect(filter.getColorFilter(1.0), isNotNull, reason: '${filter.id} at 1.0 should not be null');
        expect(filter.getColorFilter(0.5), isNotNull, reason: '${filter.id} at 0.5 should not be null');
      }
    });
  });

  group('PipColorFilterHelper Regression Safeguard', () {
    test('neutral PipAdjustments returns null ColorFilter', () {
      final filter = PipColorFilterHelper.createFilter(
        adjustments: const PipAdjustments(),
        filterId: 'none',
        filterIntensity: 1.0,
      );
      expect(filter, isNull);
    });

    test('PipColorFilterHelper correctly applies all 12 presets when intensity > 0', () {
      final presetIds = [
        'vivid',
        'warm',
        'cool',
        'vintage',
        'cinema',
        'fade',
        'mono',
        'black_white',
        'sepia',
        'dramatic',
        'portrait',
      ];

      for (final id in presetIds) {
        final filter = PipColorFilterHelper.createFilter(
          filterId: id,
          filterIntensity: 0.8,
        );
        expect(filter, isNotNull, reason: 'PIP preset $id should produce a ColorFilter');
      }
    });

    test('PipColorFilterHelper with intensity 0 returns null filter', () {
      final filter = PipColorFilterHelper.createFilter(
        filterId: 'vivid',
        filterIntensity: 0.0,
      );
      expect(filter, isNull);
    });
  });
}
