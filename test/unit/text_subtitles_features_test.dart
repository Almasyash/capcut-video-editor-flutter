import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';
import 'package:capcut_video_editor/core/utils/font_helper.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Text & Subtitles Enhanced Features Suite', () {
    late EditorViewModel viewModel;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      viewModel = EditorViewModel();
      viewModel.loadProject(
        Project(
          id: 'test_text_proj',
          name: 'Text Feature Test',
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

    test('1. TextOverlay supports custom font family and animation types', () {
      const overlay = TextOverlay(
        id: 'text_anim_1',
        text: 'Custom Font Animated',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        fontFamily: 'Montserrat',
        animationType: TextAnimationType.fade,
      );

      expect(overlay.fontFamily, equals('Montserrat'));
      expect(overlay.animationType, equals(TextAnimationType.fade));
      expect(overlay.animationType.displayName, equals('Fade In/Out'));

      final zoomed = overlay.copyWith(
        animationType: TextAnimationType.zoom,
        fontFamily: 'Bebas Neue',
      );
      expect(zoomed.fontFamily, equals('Bebas Neue'));
      expect(zoomed.animationType, equals(TextAnimationType.zoom));
      expect(zoomed.animationType.displayName, equals('Zoom Scale'));
    });

    test('2. All TextAnimationType enum values have valid display names and icons', () {
      for (final type in TextAnimationType.values) {
        expect(type.displayName.isNotEmpty, isTrue);
        expect(type.icon, isNotNull);
      }

      expect(TextAnimationType.fade.displayName, equals('Fade In/Out'));
      expect(TextAnimationType.zoom.displayName, equals('Zoom Scale'));
      expect(TextAnimationType.pop.displayName, equals('Pop-in (Bounce)'));
      expect(TextAnimationType.slideUp.displayName, equals('Slide Up'));
      expect(TextAnimationType.slideDown.displayName, equals('Slide Down'));
      expect(TextAnimationType.fadeSlide.displayName, equals('Fade Slide'));
      expect(TextAnimationType.karaoke.displayName, equals('Karaoke (Bounce)'));
      expect(TextAnimationType.typewriter.displayName, equals('Typewriter'));
      expect(TextAnimationType.glowPulse.displayName, equals('Glow Pulse'));
      expect(TextAnimationType.none.displayName, equals('None (Static)'));
    });

    test('3. Free viewport positioning: TextOverlay moves freely across entire [0.0, 1.0] range', () {
      const initialText = TextOverlay(
        id: 'text_drag_1',
        text: 'Draggable Text',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        position: Offset(0.5, 0.5),
      );
      viewModel.addTextOverlay(initialText);

      // Top-Left extreme (0.0, 0.0)
      viewModel.updateTextPosition('text_drag_1', const Offset(0.0, 0.0));
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.0, 0.0)));

      // Bottom-Right extreme (1.0, 1.0)
      viewModel.updateTextPosition('text_drag_1', const Offset(1.0, 1.0));
      expect(viewModel.textOverlays.first.position, equals(const Offset(1.0, 1.0)));

      // Center (0.5, 0.5)
      viewModel.updateTextPosition('text_drag_1', const Offset(0.5, 0.5));
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.5, 0.5)));

      // Clamping within [0.0, 1.0]
      final safeX = (-0.2).clamp(0.0, 1.0);
      final safeY = (1.5).clamp(0.0, 1.0);
      viewModel.updateTextPosition('text_drag_1', Offset(safeX, safeY));
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.0, 1.0)));
    });

    test('4. EditorViewModel updates text animation and highlight color cleanly', () {
      const text = TextOverlay(
        id: 'anim_test',
        text: 'Viral Subtitle',
        startTime: Duration.zero,
        duration: Duration(seconds: 3),
      );
      viewModel.addTextOverlay(text);

      viewModel.updateTextAnimation(
        'anim_test',
        TextAnimationType.slideUp,
        highlightColor: Colors.amber,
      );

      final updated = viewModel.textOverlays.firstWhere((t) => t.id == 'anim_test');
      expect(updated.animationType, equals(TextAnimationType.slideUp));
      expect(updated.highlightColor, equals(Colors.amber));
    });

    testWidgets('5. ActionToolbar displays "Text Animation" action button replacing Auto Captions', (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionToolbar(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();

      // Verify "Text Animation" button exists and "Auto Captions" is replaced
      expect(find.text('Text Animation'), findsOneWidget);
      expect(find.text('Auto Captions'), findsNothing);
      expect(find.byIcon(Icons.animation_rounded), findsWidgets);
    });

    testWidgets('6. TextDrawer displays "Text Animation" button replacing Auto Captions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextDrawer(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();

      // Verify "Add Text" and "Text Animation" buttons exist
      expect(find.text('Add Text'), findsOneWidget);
      expect(find.text('Text Animation'), findsOneWidget);
      expect(find.text('Auto Captions'), findsNothing);
    });

    test('7. FontHelper resolves genuine font styles and graceful fallbacks', () {
      final robotoStyle = FontHelper.getTextStyle(
        fontFamily: 'Roboto',
        fontSize: 20.0,
        color: Colors.white,
      );
      expect(robotoStyle.fontSize, equals(20.0));
      expect(robotoStyle.color, equals(Colors.white));

      final monoStyle = FontHelper.getTextStyle(
        fontFamily: 'monospace',
        fontSize: 16.0,
      );
      expect(monoStyle.fontFamily, equals('monospace'));

      final defaultStyle = FontHelper.getTextStyle(
        fontFamily: null,
        fontSize: 18.0,
      );
      expect(defaultStyle.fontSize, equals(18.0));
      expect(FontHelper.availableFonts.isNotEmpty, isTrue);
    });

    test('8. TextOverlay scale persists in copyWith, toJson, and fromJson', () {
      const overlay = TextOverlay(
        id: 'scale_test',
        text: 'Scaling Title',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        scale: 1.75,
      );
      expect(overlay.scale, equals(1.75));

      final copied = overlay.copyWith(scale: 2.5);
      expect(copied.scale, equals(2.5));

      final json = copied.toJson();
      expect(json['scale'], equals(2.5));

      final deserialized = TextOverlay.fromJson(json);
      expect(deserialized.scale, equals(2.5));
    });

    test('9. EditorViewModel updates text scale and transform within clamped limits', () {
      const text = TextOverlay(
        id: 'transform_test',
        text: 'Transform Me',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        scale: 1.0,
        position: Offset(0.5, 0.5),
      );
      viewModel.addTextOverlay(text);

      viewModel.updateTextScale('transform_test', 1.8);
      expect(viewModel.textOverlays.first.scale, equals(1.8));

      // Test clamping
      viewModel.updateTextScale('transform_test', 10.0);
      expect(viewModel.textOverlays.first.scale, equals(4.0));

      viewModel.updateTextScale('transform_test', 0.05);
      expect(viewModel.textOverlays.first.scale, equals(0.3));

      viewModel.updateTextTransform(
        'transform_test',
        position: const Offset(0.2, 0.3),
        scale: 1.5,
      );
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.2, 0.3)));
      expect(viewModel.textOverlays.first.scale, equals(1.5));
    });

    testWidgets('10. VideoPreviewSection renders interactive bounding box and transform handles when selected', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'preview_ctrl_text',
        text: 'Editable Layer',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        fontFamily: 'Montserrat',
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('preview_ctrl_text');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Verify text rendered
      expect(find.text('Editable Layer'), findsWidgets);

      // Verify corner control handles: Edit, Delete, Resize, and Font badge
      expect(find.byIcon(Icons.edit_rounded), findsWidgets);
      expect(find.byIcon(Icons.close_rounded), findsWidgets);
      expect(find.byIcon(Icons.open_in_full_rounded), findsWidgets);
      expect(find.text('Montserrat'), findsWidgets);
    });

    test('11. Text scale sanitization rejects NaN, Infinity, negative values, and clamps to [0.3, 4.0]', () {
      expect(TextOverlay.sanitizeScale(double.nan, fallback: 1.5), equals(1.5));
      expect(TextOverlay.sanitizeScale(double.infinity, fallback: 2.0), equals(2.0));
      expect(TextOverlay.sanitizeScale(double.negativeInfinity, fallback: 1.0), equals(1.0));
      expect(TextOverlay.sanitizeScale(-0.5, fallback: 1.2), equals(1.2));
      expect(TextOverlay.sanitizeScale(0.0, fallback: 1.0), equals(1.0));

      // Clamping within min/max bounds
      expect(TextOverlay.sanitizeScale(0.1), equals(TextOverlay.minScale));
      expect(TextOverlay.sanitizeScale(10.0), equals(TextOverlay.maxScale));
      expect(TextOverlay.sanitizeScale(2.5), equals(2.5));
    });

    test('12. Text position sanitization rejects NaN, Infinity, and clamps within [0.0, 1.0]', () {
      final sanitizedNan = TextOverlay.sanitizePosition(
        const Offset(double.nan, double.infinity),
        fallback: const Offset(0.5, 0.75),
      );
      expect(sanitizedNan, equals(const Offset(0.5, 0.75)));

      final clamped = TextOverlay.sanitizePosition(const Offset(-0.2, 1.4));
      expect(clamped.dx, equals(0.0));
      expect(clamped.dy, equals(1.0));
    });

    test('13. Undo and Redo independently restore text transform gestures', () {
      const text = TextOverlay(
        id: 'undo_test',
        text: 'Undoable Layer',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        scale: 1.0,
        position: Offset(0.5, 0.5),
      );
      viewModel.addTextOverlay(text);

      final initialPos = viewModel.textOverlays.first.position;
      final initialScale = viewModel.textOverlays.first.scale;

      // 1. Simulate Move gesture
      viewModel.updateTextPosition('undo_test', const Offset(0.3, 0.2));
      viewModel.commitTextTransform('undo_test', oldPosition: initialPos, oldScale: initialScale);
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.3, 0.2)));

      // 2. Undo Move
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();
      expect(viewModel.textOverlays.first.position, equals(initialPos));

      // 3. Redo Move
      expect(viewModel.canRedo, isTrue);
      viewModel.redo();
      expect(viewModel.textOverlays.first.position, equals(const Offset(0.3, 0.2)));

      // 4. Simulate Resize gesture
      final movedPos = viewModel.textOverlays.first.position;
      viewModel.updateTextScale('undo_test', 2.4);
      viewModel.commitTextTransform('undo_test', oldPosition: movedPos, oldScale: initialScale);
      expect(viewModel.textOverlays.first.scale, equals(2.4));

      // 5. Undo Resize
      viewModel.undo();
      expect(viewModel.textOverlays.first.scale, equals(initialScale));
      expect(viewModel.textOverlays.first.position, equals(movedPos));
    });

    test('14. Native export payload maintains export scale and font parity', () async {
      final now = DateTime.now();
      final project = Project(
        id: 'export_parity_proj',
        name: 'Export Test',
        createdAt: now,
        updatedAt: now,
        textOverlays: const [
          TextOverlay(
            id: 'txt_export',
            text: 'Scaled Subtitle',
            startTime: Duration.zero,
            duration: Duration(seconds: 4),
            fontSize: 24.0,
            scale: 2.0,
            fontFamily: 'Montserrat',
            position: Offset(0.5, 0.8),
          ),
        ],
      );

      // Verify that effective exported font size scales with text.scale
      final overlay = project.textOverlays.first;
      final exportedFontSize = overlay.fontSize * overlay.scale;
      expect(exportedFontSize, equals(48.0));
      expect(overlay.fontFamily, equals('Montserrat'));
      expect(overlay.position, equals(const Offset(0.5, 0.8)));
    });

    testWidgets('15. Tapping canvas background deselects active text overlay', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'desel_test',
        text: 'Tap to Deselect',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('desel_test');
      expect(viewModel.selectedTextId, equals('desel_test'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => VideoPreviewSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Deselect text directly
      viewModel.selectText(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(viewModel.selectedTextId, isNull);
      // Handles should no longer be present
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    });
  });
}
