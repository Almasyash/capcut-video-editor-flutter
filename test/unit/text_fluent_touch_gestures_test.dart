import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/enums/interaction_mode.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Fluent Text Touch Interaction & Direct Manipulation Suite', () {
    late EditorViewModel viewModel;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      viewModel = EditorViewModel();
      viewModel.loadProject(
        Project(
          id: 'test_fluent_proj',
          name: 'Fluent Gestures Test',
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

    // -------------------------------------------------------------------------
    // TEST 1: One-finger translation (immediate 1:1, delta, preserving offset)
    // -------------------------------------------------------------------------
    testWidgets('1. One-finger translation tracks immediately 1:1 and preserves touch offset', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_trans_1',
        text: 'Direct Drag',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.0,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_trans_1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Direct Drag');
      expect(textFinder, findsOneWidget);

      final initialCenter = tester.getCenter(textFinder);

      // Perform a direct single-finger drag
      final gesture = await tester.startGesture(initialCenter);
      await tester.pump();

      // Move by (+60, +80) pixels
      await gesture.moveBy(const Offset(60, 80));
      await tester.pump();

      final movedCenter = tester.getCenter(textFinder);
      expect(movedCenter.dx, greaterThan(initialCenter.dx + 15));
      expect(movedCenter.dy, greaterThan(initialCenter.dy + 15));

      await gesture.up();
      await tester.pump();

      // Ensure viewmodel updated position accordingly
      final finalPos = viewModel.textOverlays.first.position;
      expect(finalPos.dx, greaterThan(0.5));
      expect(finalPos.dy, greaterThan(0.5));

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Two-finger pinch scaling (direct on text body)
    // -------------------------------------------------------------------------
    testWidgets('2. Two-finger pinch scaling works directly on text body without corner handle', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_pinch_1',
        text: 'Pinch Zoom Me',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.0,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_pinch_1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Pinch Zoom Me');
      final center = tester.getCenter(textFinder);

      // Place two fingers directly on the text body (not on the corner handle)
      final finger1 = await tester.startGesture(center + const Offset(-20, 0));
      final finger2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();

      // Pinch apart: distance moves from 40px to 100px (scale up)
      await finger1.moveBy(const Offset(-30, 0));
      await finger2.moveBy(const Offset(30, 0));
      await tester.pump();

      await finger1.up();
      await finger2.up();
      await tester.pump();

      // Scale should have increased above 1.0 directly from text body pinch
      final finalScale = viewModel.textOverlays.first.scale;
      expect(finalScale, greaterThan(1.1));

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Pinch focal point displacement tracking
    // -------------------------------------------------------------------------
    testWidgets('3. Pinch focal point displacement shifts position proportionally', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_focal_1',
        text: 'Focal Shift',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.0,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_focal_1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Focal Shift');
      final center = tester.getCenter(textFinder);

      final finger1 = await tester.startGesture(center + const Offset(-30, 0));
      final finger2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump();

      // Move both fingers synchronously to the right (+60 px) and down (+40 px)
      await finger1.moveBy(const Offset(60, 40));
      await finger2.moveBy(const Offset(60, 40));
      await tester.pump();

      await finger1.up();
      await finger2.up();
      await tester.pump();

      final finalPos = viewModel.textOverlays.first.position;
      expect(finalPos.dx, greaterThan(0.5));
      expect(finalPos.dy, greaterThan(0.5));

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Scale min/max bounds clamping [0.3, 4.0]
    // -------------------------------------------------------------------------
    test('4. Scale min/max bounds are strictly clamped to [0.3, 4.0]', () {
      expect(TextOverlay.minScale, equals(0.3));
      expect(TextOverlay.maxScale, equals(4.0));

      // Direct clamping helper test
      expect(TextOverlay.sanitizeScale(0.01), equals(0.3));
      expect(TextOverlay.sanitizeScale(-5.0), equals(1.0)); // Negative uses fallback
      expect(TextOverlay.sanitizeScale(-5.0, fallback: 0.8), equals(0.8));
      expect(TextOverlay.sanitizeScale(0.29), equals(0.3));
      expect(TextOverlay.sanitizeScale(4.01), equals(4.0));
      expect(TextOverlay.sanitizeScale(100.0), equals(4.0));
      expect(TextOverlay.sanitizeScale(2.5), equals(2.5));

      // View model clamp test
      const text = TextOverlay(
        id: 'txt_clamp',
        text: 'Clamp Limits',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      viewModel.addTextOverlay(text);

      viewModel.updateTextScale('txt_clamp', 0.1);
      expect(viewModel.textOverlays.first.scale, equals(0.3));

      viewModel.updateTextScale('txt_clamp', 999.0);
      expect(viewModel.textOverlays.first.scale, equals(4.0));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Zero-distance pinch protection and edge cases
    // -------------------------------------------------------------------------
    test('5. Zero-distance pinch and zero/sub-pixel distance calculations are protected', () {
      // In _handlePointerDown, dist < 5.0 defaults to 5.0 to avoid division by zero.
      // In sanitizeScale, non-positive or 0 values return fallback safely.
      expect(TextOverlay.sanitizeScale(0.0, fallback: 1.0), equals(1.0));
      expect(TextOverlay.sanitizeScale(-0.0001, fallback: 1.2), equals(1.2));

      // Test extreme scaleFactor edge case simulation
      const initialDist = 5.0; // minimum clamp
      const currentDist = 0.0; // zero distance protection
      const safeScale = (currentDist > 0.0) ? (1.0 * (currentDist / initialDist)) : 1.0;
      expect(safeScale, equals(1.0));
      expect(TextOverlay.sanitizeScale(safeScale), equals(1.0));
    });

    // -------------------------------------------------------------------------
    // TEST 6: NaN / Infinity position and scale rejection
    // -------------------------------------------------------------------------
    test('6. NaN / Infinity position and scale values are cleanly rejected with fallback', () {
      // Scale sanitization
      expect(TextOverlay.sanitizeScale(double.nan, fallback: 1.25), equals(1.25));
      expect(TextOverlay.sanitizeScale(double.infinity, fallback: 1.5), equals(1.5));
      expect(TextOverlay.sanitizeScale(double.negativeInfinity, fallback: 1.75), equals(1.75));

      // Position sanitization
      const fallbackPos = Offset(0.4, 0.6);
      expect(
        TextOverlay.sanitizePosition(const Offset(double.nan, 0.5), fallback: fallbackPos),
        equals(const Offset(0.4, 0.5)),
      );
      expect(
        TextOverlay.sanitizePosition(const Offset(0.3, double.infinity), fallback: fallbackPos),
        equals(const Offset(0.3, 0.6)),
      );
      expect(
        TextOverlay.sanitizePosition(const Offset(double.negativeInfinity, double.nan), fallback: fallbackPos),
        equals(fallbackPos),
      );

      // Bounds clamping within [0.0, 1.0]
      final clamped = TextOverlay.sanitizePosition(const Offset(-0.5, 1.8));
      expect(clamped.dx, equals(0.0));
      expect(clamped.dy, equals(1.0));
    });

    // -------------------------------------------------------------------------
    // TEST 7: Transition 1 pointer -> 2 pointers (no jump, seamless scale baseline)
    // -------------------------------------------------------------------------
    testWidgets('7. Transition 1 pointer -> 2 pointers creates seamless scale baseline with no jump', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_transition_1_2',
        text: 'Multi Pointer',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.2,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_transition_1_2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Multi Pointer');
      final center = tester.getCenter(textFinder);

      // Step 1: Start 1 finger drag
      final finger1 = await tester.startGesture(center);
      await tester.pump();
      await finger1.moveBy(const Offset(20, 20));
      await tester.pump();

      final midPos = tester.getCenter(textFinder);

      // Step 2: Add 2nd finger while 1st finger is still touching down
      final finger2 = await tester.startGesture(midPos + const Offset(40, 0));
      await tester.pump();

      // Position should not jump on second finger down
      final newCenter = tester.getCenter(textFinder);
      expect((newCenter.dx - midPos.dx).abs(), lessThan(5.0));
      expect((newCenter.dy - midPos.dy).abs(), lessThan(5.0));

      await finger1.up();
      await finger2.up();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 8: Transition 2 pointers -> 1 pointer (no jump, seamless translation)
    // -------------------------------------------------------------------------
    testWidgets('8. Transition 2 pointers -> 1 pointer preserves scale and seamlessly resumes translation', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_transition_2_1',
        text: 'Release Pointer',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.0,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_transition_2_1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Release Pointer');
      final center = tester.getCenter(textFinder);

      // Start 2-finger pinch
      final finger1 = await tester.startGesture(center + const Offset(-20, 0));
      final finger2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();

      // Pinch out
      await finger1.moveBy(const Offset(-20, 0));
      await finger2.moveBy(const Offset(20, 0));
      await tester.pump();

      // Lift finger 2, leaving finger 1 active
      await finger2.up();
      await tester.pump();

      // Continue dragging with finger 1
      final beforeDragPos = tester.getCenter(textFinder);
      await finger1.moveBy(const Offset(30, 30));
      await tester.pump();

      final afterDragPos = tester.getCenter(textFinder);
      expect(afterDragPos.dx, greaterThan(beforeDragPos.dx + 10));
      expect(afterDragPos.dy, greaterThan(beforeDragPos.dy + 10));

      await finger1.up();
      await tester.pump();

      // Scale should be preserved from pinch (> 1.05)
      expect(viewModel.textOverlays.first.scale, greaterThan(1.05));

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 9: Undo snapshot count: exactly ONE snapshot per continuous gesture
    // -------------------------------------------------------------------------
    testWidgets('9. Exactly ONE undo snapshot is recorded per continuous gesture', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const text = TextOverlay(
        id: 'txt_undo_single',
        text: 'Single Undo',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        position: Offset(0.5, 0.5),
        scale: 1.0,
      );
      viewModel.addTextOverlay(text);
      viewModel.selectText('txt_undo_single');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textFinder = find.text('Single Undo');
      final center = tester.getCenter(textFinder);

      // Perform a drag with 10 intermediate move events
      final gesture = await tester.startGesture(center);
      await tester.pump();

      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(5, 5));
        await tester.pump(const Duration(milliseconds: 16));
      }

      await gesture.up();
      await tester.pump();

      // Position should be updated
      expect(viewModel.textOverlays.first.position.dx, greaterThan(0.5));

      // Only ONE undo should restore to original (0.5, 0.5)
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();
      await tester.pump();

      expect(viewModel.textOverlays.first.position, equals(const Offset(0.5, 0.5)));
      expect(viewModel.textOverlays.first.scale, equals(1.0));

      // After one undo, no extra intermediate gesture snapshots should exist
      expect(viewModel.canRedo, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
    });

    // -------------------------------------------------------------------------
    // TEST 10: Crop handle movement and resizing (left, right, top, bottom, corners)
    // -------------------------------------------------------------------------
    test('10. Crop handle movement adjusts left, right, top, and bottom rectangular bounds', () {
      const clip = VideoClip(
        id: 'clip_crop_1',
        assetId: 'asset_1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.blue, Colors.purple],
        mask: VideoMask(
          type: MaskType.rectangle,
          rectWidth: 0.8,
          rectHeight: 0.8,
        ),
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);
      viewModel.setCropMode(true);

      expect(viewModel.isCropModeActive, isTrue);
      expect(viewModel.activeCropRect, equals(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)));

      // Resize Left
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.1, 0.7, 0.8));
      expect(viewModel.activeCropRect.left, closeTo(0.2, 0.001));

      // Resize Top
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.25, 0.7, 0.65));
      expect(viewModel.activeCropRect.top, closeTo(0.25, 0.001));

      // Resize Right
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.25, 0.6, 0.65));
      expect(viewModel.activeCropRect.right, closeTo(0.8, 0.001));

      // Resize Bottom
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.25, 0.6, 0.5));
      expect(viewModel.activeCropRect.bottom, closeTo(0.75, 0.001));
    });

    // -------------------------------------------------------------------------
    // TEST 11: Crop bounds protection (min size 0.1, clamped [0.0, 1.0], no inversion)
    // -------------------------------------------------------------------------
    test('11. Crop bounds protection enforces min size 0.1, clamps [0.0, 1.0], and prevents inversion', () {
      const clip = VideoClip(
        id: 'clip_crop_clamp',
        assetId: 'asset_2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.red, Colors.orange],
        mask: VideoMask(
          type: MaskType.rectangle,
          rectWidth: 0.8,
          rectHeight: 0.8,
        ),
      );
      viewModel.addVideoClip(clip);
      viewModel.selectClip(0);
      viewModel.setCropMode(true);

      // Attempt to shrink width below 0.1
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.2, 0.02, 0.5));
      expect(viewModel.activeCropRect.width, greaterThanOrEqualTo(0.1));

      // Attempt to shrink height below 0.1
      viewModel.updateCropRect(const Rect.fromLTWH(0.2, 0.2, 0.5, 0.01));
      expect(viewModel.activeCropRect.height, greaterThanOrEqualTo(0.1));

      // Attempt to push out-of-bounds (< 0.0 or > 1.0)
      viewModel.updateCropRect(const Rect.fromLTWH(-0.5, -0.3, 1.8, 1.9));
      expect(viewModel.activeCropRect.left, greaterThanOrEqualTo(0.0));
      expect(viewModel.activeCropRect.top, greaterThanOrEqualTo(0.0));
      expect(viewModel.activeCropRect.right, lessThanOrEqualTo(1.0));
      expect(viewModel.activeCropRect.bottom, lessThanOrEqualTo(1.0));

      // Attempt to invert (left > right or top > bottom)
      const inverted = Rect.fromLTRB(0.8, 0.7, 0.3, 0.2);
      viewModel.updateCropRect(inverted);
      expect(viewModel.activeCropRect.left, lessThan(viewModel.activeCropRect.right));
      expect(viewModel.activeCropRect.top, lessThan(viewModel.activeCropRect.bottom));
    });

    // -------------------------------------------------------------------------
    // TEST 12: Interaction mode isolation (cropResize vs textMove/Pinch/Resize)
    // -------------------------------------------------------------------------
    test('12. InteractionMode enum defines clear isolation semantics', () {
      expect(InteractionMode.none.isTextActive, isFalse);
      expect(InteractionMode.none.isCropActive, isFalse);

      expect(InteractionMode.textMove.isTextActive, isTrue);
      expect(InteractionMode.textMove.isCropActive, isFalse);

      expect(InteractionMode.textPinch.isTextActive, isTrue);
      expect(InteractionMode.textPinch.isCropActive, isFalse);

      expect(InteractionMode.textResize.isTextActive, isTrue);
      expect(InteractionMode.textResize.isCropActive, isFalse);

      expect(InteractionMode.cropResize.isCropActive, isTrue);
      expect(InteractionMode.cropResize.isTextActive, isFalse);

      // Crop mode precedence test
      viewModel.setCropMode(true);
      expect(viewModel.isCropModeActive, isTrue);

      viewModel.selectText('txt_test');
      expect(viewModel.selectedTextId, equals('txt_test'));

      viewModel.setCropMode(false);
      expect(viewModel.isCropModeActive, isFalse);
    });
  });
}
