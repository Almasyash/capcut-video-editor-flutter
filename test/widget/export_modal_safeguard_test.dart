import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/export_modal_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExportModalSheet PopScope Safeguard Tests', () {
    testWidgets('PopScope canPop is true when isExporting is false', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportModalSheet(viewModel: viewModel),
          ),
        ),
      );

      final popScopeFinder = find.descendant(
        of: find.byType(ExportModalSheet),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScopeFinder, findsOneWidget);

      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isTrue);
    });

    testWidgets('PopScope canPop is false when isExporting is true, blocking dismissal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final viewModel = EditorViewModel(enableMockFallback: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ExportModalSheet(viewModel: viewModel),
                  );
                },
                child: const Text('Open Export'),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportModalSheet), findsOneWidget);

      // Set isExporting to true
      viewModel.setIsExportingForTesting(true);
      await tester.pump();

      expect(viewModel.isExporting, isTrue);

      final popScopeFinder = find.descendant(
        of: find.byType(ExportModalSheet),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Attempt to pop via Navigator.maybePop from the sheet's context
      final sheetContext = tester.element(find.byType(ExportModalSheet));
      final navigatorState = Navigator.of(sheetContext);
      await navigatorState.maybePop();
      await tester.pumpAndSettle();

      // Ensure the sheet was NOT dismissed and is still in the tree
      expect(find.byType(ExportModalSheet), findsOneWidget);

      // Now finish/cancel export
      viewModel.setIsExportingForTesting(false);
      await tester.pump();

      expect(viewModel.isExporting, isFalse);
      final popScopeAfterCancel = tester.widget<PopScope>(popScopeFinder);
      expect(popScopeAfterCancel.canPop, isTrue);

      // Verify the sheet can now pop successfully
      final secondPopResult = await navigatorState.maybePop();
      expect(secondPopResult, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(ExportModalSheet), findsNothing);
    });
  });
}
