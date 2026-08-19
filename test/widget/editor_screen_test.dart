import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/app.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  testWidgets('EditorScreen renders top preview, middle action toolbar, and bottom timeline', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(const CapCutVideoEditorApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify main sections are present in widget tree
    expect(find.byType(VideoPreviewSection), findsOneWidget);
    expect(find.byType(ActionToolbar), findsOneWidget);
    expect(find.byType(TimelineSection), findsOneWidget);

    // Verify action buttons
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Trim Left'), findsOneWidget);
    expect(find.text('Trim Right'), findsOneWidget);

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
