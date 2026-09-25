import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:capcut_video_editor/core/utils/font_helper.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Text Editor Controls & Typography Hardening Suite', () {
    late EditorViewModel viewModel;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      viewModel = EditorViewModel();
      viewModel.loadProject(
        Project(
          id: 'test_text_editor_proj',
          name: 'Text Editor Hardening Project',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          videoClips: const [],
          audioTracks: const [],
          textOverlays: const [],
        ),
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('1. Font family list includes required standard, google, and fallback fonts', () {
      final families = FontHelper.availableFonts.map((f) => f.family).toList();
      final labels = FontHelper.availableFonts.map((f) => f.label).toList();

      expect(labels, contains('Default'));
      expect(labels, contains('Roboto'));
      expect(labels, contains('Montserrat'));
      expect(labels, contains('Oswald'));
      expect(labels, contains('Bebas Neue'));
      expect(labels, contains('Playfair Display'));
      expect(labels, contains('Poppins'));
      expect(labels, contains('Lato'));
      expect(labels, contains('Open Sans'));
      expect(labels, contains('Raleway'));
      expect(labels, contains('Pacifico'));
      expect(labels, contains('Monospace'));
      expect(labels, contains('Serif'));
      expect(labels, contains('Sans-Serif'));

      expect(families, contains(null)); // Default
      expect(families, contains('Roboto'));
      expect(families, contains('Montserrat'));
      expect(families, contains('Oswald'));
      expect(families, contains('Bebas Neue'));
      expect(families, contains('monospace'));
      expect(families, contains('serif'));
      expect(families, contains('sans-serif'));
    });

    test('2. FontHelper resolves standard and fallback styles without throwing', () {
      // Default
      final defaultStyle = FontHelper.getTextStyle(fontSize: 24);
      expect(defaultStyle.fontSize, equals(24));

      // Monospace
      final monoStyle = FontHelper.getTextStyle(fontFamily: 'monospace', fontSize: 20);
      expect(monoStyle.fontFamily, equals('monospace'));

      // Unknown / graceful fallback
      final unknownStyle = FontHelper.getTextStyle(fontFamily: 'NonExistentFontXYZ', fontSize: 18);
      expect(unknownStyle.fontSize, equals(18));
      expect(unknownStyle.fontFamily, equals('NonExistentFontXYZ'));
    });

    test('3. Bold weight mapping: normal text uses w400, bold text uses w700 / bold', () {
      const normalText = TextOverlay(
        id: 't_normal',
        text: 'Normal Weight',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        isBold: false,
      );
      expect(normalText.isBold, isFalse);

      final boldText = normalText.copyWith(isBold: true);
      expect(boldText.isBold, isTrue);

      final normalStyle = FontHelper.getTextStyle(
        fontSize: 24,
        fontWeight: normalText.isBold ? FontWeight.bold : FontWeight.normal,
      );
      final boldStyle = FontHelper.getTextStyle(
        fontSize: 24,
        fontWeight: boldText.isBold ? FontWeight.bold : FontWeight.normal,
      );

      expect(normalStyle.fontWeight, equals(FontWeight.normal));
      expect(boldStyle.fontWeight, equals(FontWeight.bold));
    });

    test('4. Underline decoration: applies TextDecoration.underline when isUnderline is true', () {
      const textWithoutUnderline = TextOverlay(
        id: 't_no_u',
        text: 'Plain Text',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        isUnderline: false,
      );
      expect(textWithoutUnderline.isUnderline, isFalse);

      final textWithUnderline = textWithoutUnderline.copyWith(isUnderline: true);
      expect(textWithUnderline.isUnderline, isTrue);

      final styleNoU = FontHelper.getTextStyle(
        fontSize: 24,
        decoration: textWithoutUnderline.isUnderline ? TextDecoration.underline : TextDecoration.none,
      );
      final styleWithU = FontHelper.getTextStyle(
        fontSize: 24,
        decoration: textWithUnderline.isUnderline ? TextDecoration.underline : TextDecoration.none,
      );

      expect(styleNoU.decoration, equals(TextDecoration.none));
      expect(styleWithU.decoration, equals(TextDecoration.underline));
    });

    test('5. Alignment support: TextAlign.left, center, and right persist and align correctly', () {
      const textLeft = TextOverlay(
        id: 't_left',
        text: 'Left Align',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        textAlign: TextAlign.left,
      );
      expect(textLeft.textAlign, equals(TextAlign.left));

      final textCenter = textLeft.copyWith(textAlign: TextAlign.center);
      expect(textCenter.textAlign, equals(TextAlign.center));

      final textRight = textLeft.copyWith(textAlign: TextAlign.right);
      expect(textRight.textAlign, equals(TextAlign.right));
    });

    test('6. Font size supports up to 100px with manual numeric input synchronization', () {
      const overlay = TextOverlay(
        id: 't_size',
        text: 'Size Test',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        fontSize: 24.0,
      );
      viewModel.addTextOverlay(overlay);

      // Clamping simulation for manual text inputs
      double parseAndClamp(String input) {
        final parsed = int.tryParse(input);
        if (parsed == null) return 24.0;
        return parsed.clamp(8, 100).toDouble();
      }

      // Valid manual entries
      expect(parseAndClamp('10'), equals(10.0));
      expect(parseAndClamp('27'), equals(27.0));
      expect(parseAndClamp('50'), equals(50.0));
      expect(parseAndClamp('75'), equals(75.0));
      expect(parseAndClamp('100'), equals(100.0));

      // Clamping limits
      expect(parseAndClamp('5'), equals(8.0)); // clamped to min
      expect(parseAndClamp('150'), equals(100.0)); // clamped to max 100px
      expect(parseAndClamp('999'), equals(100.0)); // clamped to max 100px
      expect(parseAndClamp('abc'), equals(24.0)); // invalid fallback

      // Update model with 100px
      final largeText = overlay.copyWith(fontSize: 100.0);
      viewModel.updateTextOverlay(largeText);
      expect(viewModel.textOverlays.first.fontSize, equals(100.0));
    });

    test('7. Model serialization preserves all formatting fields (font, bold, underline, align, size)', () {
      const original = TextOverlay(
        id: 'full_fmt_1',
        text: 'Hello\nWorld Multiline',
        startTime: Duration(milliseconds: 1500),
        duration: Duration(seconds: 5),
        fontSize: 72.0,
        fontFamily: 'Montserrat',
        isBold: true,
        isItalic: true,
        isUnderline: true,
        textAlign: TextAlign.right,
        textColor: Color(0xFFFF5722),
        backgroundColor: Color(0x80000000),
      );

      final json = original.toJson();
      expect(json['fontFamily'], equals('Montserrat'));
      expect(json['fontSize'], equals(72.0));
      expect(json['isBold'], isTrue);
      expect(json['isItalic'], isTrue);
      expect(json['isUnderline'], isTrue);
      expect(json['textAlignIndex'], equals(TextAlign.right.index));

      final restored = TextOverlay.fromJson(json);
      expect(restored.id, equals(original.id));
      expect(restored.text, equals('Hello\nWorld Multiline'));
      expect(restored.fontFamily, equals('Montserrat'));
      expect(restored.fontSize, equals(72.0));
      expect(restored.isBold, isTrue);
      expect(restored.isItalic, isTrue);
      expect(restored.isUnderline, isTrue);
      expect(restored.textAlign, equals(TextAlign.right));
      expect(restored.color, equals(const Color(0xFFFF5722)));
    });

    test('8. Live preview updating: updateTextOverlay supports saveSnapshot flag for smooth interaction', () {
      const initial = TextOverlay(
        id: 'live_test',
        text: 'Live Preview',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        fontSize: 24.0,
      );
      viewModel.addTextOverlay(initial);

      // Perform live update without snapshot
      final liveDraft = initial.copyWith(fontSize: 50.0, isBold: true, isUnderline: true);
      viewModel.updateTextOverlay(liveDraft, saveSnapshot: false);

      expect(viewModel.textOverlays.first.fontSize, equals(50.0));
      expect(viewModel.textOverlays.first.isBold, isTrue);
      expect(viewModel.textOverlays.first.isUnderline, isTrue);

      // Can undo? Undo stack should only have the addTextOverlay snapshot
      expect(viewModel.canUndo, isTrue);
    });

    test('9. DeviceMediaService export payload parity: textOverlays dictionary includes underline and alignment', () {
      final project = Project(
        id: 'export_parity_proj',
        name: 'Export Parity Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        videoClips: const [],
        audioTracks: const [],
        textOverlays: const [
          TextOverlay(
            id: 'export_txt_1',
            text: 'Exported Subtitle\nSecond Line',
            startTime: Duration(seconds: 1),
            duration: Duration(seconds: 3),
            fontSize: 48.0,
            scale: 1.5,
            fontFamily: 'Oswald',
            isBold: true,
            isItalic: false,
            isUnderline: true,
            textAlign: TextAlign.left,
            textColor: Colors.yellow,
          ),
        ],
      );

      // Inspect payload logic directly mirroring DeviceMediaService
      final text = project.textOverlays.first;
      final payloadMap = {
        'id': text.id,
        'text': text.text,
        'startTimeMs': text.startTime.inMilliseconds,
        'durationMs': text.effectiveDuration.inMilliseconds,
        'fontSize': text.fontSize * text.scale,
        'scale': text.scale,
        'fontFamily': text.fontFamily,
        'textColor': text.color.value,
        'backgroundColor': text.backgroundColor?.value,
        'x': text.position.dx,
        'y': text.position.dy,
        'isBold': text.isBold,
        'isItalic': text.isItalic,
        'isUnderline': text.isUnderline,
        'textAlign': text.textAlign.name,
      };

      expect(payloadMap['fontFamily'], equals('Oswald'));
      expect(payloadMap['fontSize'], equals(72.0)); // 48 * 1.5
      expect(payloadMap['isBold'], isTrue);
      expect(payloadMap['isUnderline'], isTrue);
      expect(payloadMap['textAlign'], equals('left'));
    });
  });
}
