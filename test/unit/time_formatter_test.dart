import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';

void main() {
  group('TimeFormatter Tests', () {
    test('formatTimecode formats minutes, seconds, and hundredths properly', () {
      expect(
        TimeFormatter.formatTimecode(const Duration(milliseconds: 4120)),
        equals('00:04.12'),
      );

      expect(
        TimeFormatter.formatTimecode(const Duration(minutes: 1, seconds: 23, milliseconds: 450)),
        equals('01:23.45'),
      );

      expect(
        TimeFormatter.formatTimecode(const Duration(milliseconds: 0)),
        equals('00:00.00'),
      );
    });

    test('formatSeconds converts floating seconds accurately', () {
      expect(TimeFormatter.formatSeconds(7.85), equals('00:07.85'));
      expect(TimeFormatter.formatSeconds(65.0, showMilliseconds: false), equals('01:05'));
    });

    test('formatRulerTick formats second boundaries correctly', () {
      expect(TimeFormatter.formatRulerTick(0), equals('00:00'));
      expect(TimeFormatter.formatRulerTick(15), equals('00:15'));
      expect(TimeFormatter.formatRulerTick(125), equals('02:05'));
    });
  });
}
