import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  testWidgets('ActionToolbar smoke test', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionToolbar(viewModel: viewModel),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Trim Left'), findsOneWidget);
  });

  testWidgets('VideoPreviewSection smoke test', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoPreviewSection(viewModel: viewModel),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(VideoPreviewSection), findsOneWidget);
  });
}
