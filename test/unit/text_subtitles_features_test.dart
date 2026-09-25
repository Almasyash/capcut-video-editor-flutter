import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Text & Subtitles Enhanced Features Suite', () {
    late EditorViewModel viewModel;

    setUp(() {
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
  });
}
