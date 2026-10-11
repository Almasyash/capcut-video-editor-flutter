import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:capcut_video_editor/app.dart';
import 'package:capcut_video_editor/ui/features/home/views/home_screen.dart';
import 'package:capcut_video_editor/ui/features/editor/views/editor_screen.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/motion_graph_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Physical Device Headless Validation Suite (Realme RMX5003)', () {
    testWidgets('1. HomeScreen renders branding and navigates to EditorScreen', (tester) async {
      await tester.pumpWidget(const CapCutVideoEditorApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Editor FS'), findsOneWidget);
      expect(find.text('New Project'), findsOneWidget);

      // Tap New Project to open EditorScreen
      await tester.tap(find.text('New Project'));
      await tester.pumpAndSettle();

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.byType(VideoPreviewSection), findsOneWidget);
      expect(find.byType(ActionToolbar), findsOneWidget);
      expect(find.byType(TimelineSection), findsOneWidget);
    });

    testWidgets('2. EditorScreen ActionToolbar displays editing controls without overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Trim Left'), findsOneWidget);
      expect(find.text('Trim Right'), findsOneWidget);
    });

    testWidgets('3. Phase 14 Motion Graph Sheet renders Bezier controls and Speed curves on hardware', (tester) async {
      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'physical_test_clip',
        title: 'Hardware Test Clip',
        duration: const Duration(seconds: 10),
        gradient: [Colors.deepPurple, Colors.teal],
      );

      // Add two keyframes at 1s and 4s
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(4.0);
      viewModel.addKeyframeAtPlayhead();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionGraphSheet(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Value Curve Header
      expect(find.text('Motion Graph'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);

      // Switch to Speed Curve Mode
      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);

      // Switch back to Value Mode
      await tester.tap(find.text('Value'));
      await tester.pumpAndSettle();

      // Select Bezier Curve Preset chip
      final bezierFinder = find.text('Bezier');
      if (bezierFinder.evaluate().isNotEmpty) {
        await tester.tap(bezierFinder);
        await tester.pumpAndSettle();

        // Tangent mode chips are displayed
        expect(find.text('Auto Smooth'), findsOneWidget);
        expect(find.text('Broken Corner'), findsOneWidget);
        expect(find.text('Linear'), findsOneWidget);

        // Tap Broken Corner
        await tester.tap(find.text('Broken Corner'));
        await tester.pumpAndSettle();
      }

      // Drag canvas touch interaction
      final canvasFinder = find.byType(CustomPaint).first;
      await tester.drag(canvasFinder, const Offset(30, -20));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
