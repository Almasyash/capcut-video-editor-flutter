import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/views/editor_screen.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/desktop_assets_panel.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/desktop_tools_panel.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/edit_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  testWidgets('Desktop NLE 3-panel layout renders when width >= 850', (tester) async {
    // 1280 x 800 desktop resolution
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: EditorScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify desktop 3-panel components
    expect(find.byType(DesktopAssetsPanel), findsOneWidget);
    expect(find.byType(VideoPreviewSection), findsOneWidget);
    expect(find.byType(DesktopToolsPanel), findsOneWidget);
    expect(find.byType(TimelineSection), findsOneWidget);
    expect(find.byType(ActionToolbar), findsOneWidget);

    // Verify Desktop Assets Panel headers
    expect(find.text('Media Library'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);

    // Verify Desktop Tools Panel renders EditDrawer
    expect(find.byType(EditDrawer), findsOneWidget);

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  testWidgets('Mobile layout is 100% preserved when width < 850', (tester) async {
    // Standard phone resolution (540 logical width)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: EditorScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Desktop panels must NOT exist in mobile layout
    expect(find.byType(DesktopAssetsPanel), findsNothing);
    expect(find.byType(DesktopToolsPanel), findsNothing);

    // Mobile layout elements exist
    expect(find.byType(VideoPreviewSection), findsOneWidget);
    expect(find.byType(ActionToolbar), findsOneWidget);
    expect(find.byType(TimelineSection), findsOneWidget);

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  testWidgets('Action toolbar contains shortcuts tooltips for desktop user experience', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: EditorScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify tooltip widgets with shortcut combinations
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message).toList();

    expect(tooltips, contains('Split at playhead (S)'));
    expect(tooltips, contains('Left Cut / Trim head to playhead (Q)'));
    expect(tooltips, contains('Right Cut / Trim tail to playhead (W)'));
    expect(tooltips, contains('Cut selected (Ctrl+X)'));
    expect(tooltips, contains('Copy selected (Ctrl+C)'));
    expect(tooltips, contains('Paste from clipboard at playhead (Ctrl+V)'));
    expect(tooltips, contains('Previous Cut / Boundary (Left Arrow)'));
    expect(tooltips, contains('Next Cut / Boundary (Right Arrow)'));

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
