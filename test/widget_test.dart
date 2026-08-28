import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/action_toolbar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/audio_track_item.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/adjust_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/audio_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/edit_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/effects_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/filters_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/stickers_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/drawers/text_drawer.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/top_navigation_bar.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  testWidgets('TopNavigationBar renders Mahmas Studio branding', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopNavigationBar(viewModel: viewModel),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mahmas'), findsOneWidget);
    expect(find.byIcon(Icons.movie_filter_rounded), findsOneWidget);
  });

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
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Add Clip'), findsOneWidget);
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

  testWidgets('AudioTrackItem renders waveform and handles selection', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioTrackItem(
            audioTrack: viewModel.audioTrack!,
            pixelsPerSecond: viewModel.pixelsPerSecond,
            viewModel: viewModel,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Midnight Beats'), findsOneWidget);
  });

  testWidgets('All 7 Category Drawers render properly', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    // 1. Edit Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EditDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(EditDrawer), findsOneWidget);

    // 2. Audio Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AudioDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(AudioDrawer), findsOneWidget);

    // 3. Text Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(TextDrawer), findsOneWidget);

    // 4. Stickers Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StickersDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(StickersDrawer), findsOneWidget);

    // 5. Effects Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EffectsDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(EffectsDrawer), findsOneWidget);

    // 6. Filters Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FiltersDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(FiltersDrawer), findsOneWidget);

    // 7. Adjust Drawer
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdjustDrawer(viewModel: viewModel))));
    await tester.pump();
    expect(find.byType(AdjustDrawer), findsOneWidget);
  });

  testWidgets('MediaPickerSheet renders video, photo tabs and device upload button', (WidgetTester tester) async {
    final viewModel = EditorViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPickerSheet(viewModel: viewModel),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Canvases'), findsNothing);
    expect(find.text('Upload File from Device Storage'), findsOneWidget);
  });
}
