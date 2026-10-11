import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/motion_graph_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionGraphSheet Interactive Canvas & Bezier Tests', () {
    testWidgets('MotionGraphSheet renders without overflow and supports Value/Speed toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'motion_test_clip',
        title: 'Motion Test Clip',
        duration: const Duration(seconds: 8),
        gradient: [Colors.blue, Colors.purple],
      );

      // Add two keyframes to create an interpolation segment
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(3.0);
      viewModel.addKeyframeAtPlayhead();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionGraphSheet(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header title and mode switcher
      expect(find.text('Motion Graph'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);

      // Switch to Speed mode
      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();

      // In speed mode, speed curve painter renders with Max Speed legend
      expect(find.byType(CustomPaint), findsWidgets);

      // Switch back to Value mode
      await tester.tap(find.text('Value'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Selecting Bezier curve reveals Tangent Modes and updates curve', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'motion_test_clip_2',
        title: 'Bezier Clip',
        duration: const Duration(seconds: 8),
        gradient: [Colors.teal, Colors.indigo],
      );

      // Add keyframe at 1.0s
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionGraphSheet(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag horizontal easing list to reveal Bézier button
      await tester.drag(find.byType(Scrollable).last, const Offset(-250, 0));
      await tester.pumpAndSettle();

      final bezierButton = find.text('Bézier');
      expect(bezierButton, findsOneWidget);
      await tester.tap(bezierButton);
      await tester.pumpAndSettle();

      // Verify Tangent Mode controls appear
      expect(find.text('TANGENTS:'), findsOneWidget);
      expect(find.text('Auto Smooth'), findsOneWidget);
      expect(find.text('Broken Corner'), findsOneWidget);
      expect(find.text('Reset Handles'), findsOneWidget);

      // Tap 'Broken Corner' mode
      await tester.tap(find.text('Broken Corner'));
      await tester.pumpAndSettle();

      // Check that the keyframe's easing has TangentMode.broken
      final track = viewModel.selectedClip?.effectiveKeyframeTracks.tracks[AnimatableProperty.scale];
      final kf = track?.getKeyframeAt(1000);
      expect(kf?.easing.mode, equals(InterpolationMode.cubicBezier));
      expect(kf?.easing.tangentMode, equals(TangentMode.broken));

      // Resolve debounced auto-save timer
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Canvas touch drag interaction executes without exceptions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'motion_test_clip_3',
        title: 'Drag Clip',
        duration: const Duration(seconds: 10),
        gradient: [Colors.orange, Colors.red],
      );

      viewModel.seekTo(2.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(6.0);
      viewModel.addKeyframeAtPlayhead();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionGraphSheet(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the CustomPaint canvas widget
      final canvasFinder = find.byType(CustomPaint).last;
      expect(canvasFinder, findsOneWidget);

      final center = tester.getCenter(canvasFinder);

      // Perform a pan gesture (touch drag) on the canvas
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(30, -40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Ensure no crash occurred and state remained consistent
      expect(find.byType(MotionGraphSheet), findsOneWidget);

      // Resolve debounced auto-save timer
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
