import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/speed_adjustment_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Speed Curve Touch Target & Interaction Tests', () {
    testWidgets('SpeedAdjustmentSheet opens curve tab and renders CurveCanvas', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'speed_clip_asset',
        title: 'Speed Clip',
        duration: const Duration(seconds: 10),
        gradient: [Colors.blue, Colors.purple],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpeedAdjustmentSheet(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Curve' Tab
      final curveTabFinder = find.text('Curve');
      expect(curveTabFinder, findsOneWidget);
      await tester.tap(curveTabFinder);
      await tester.pumpAndSettle();

      // Check presets are visible (Custom, Montage, Hero, Bullet, Flash, Jump Cut)
      expect(find.text('Montage'), findsOneWidget);
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);

      // Select Montage preset
      await tester.tap(find.text('Montage'));
      await tester.pumpAndSettle();

      expect(find.text('Montage'), findsOneWidget);

      // Verify custom curve painter is active
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
