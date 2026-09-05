import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPreviewSection Transition Rendering Tests', () {
    late EditorViewModel viewModel;
    late VideoClip clip1;
    late VideoClip clip2;
    late Project project;

    setUp(() {
      clip1 = const VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Clip One',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.blue, Colors.black],
      );

      clip2 = const VideoClip(
        id: 'c2',
        assetId: 'a2',
        title: 'Clip Two',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.red, Colors.yellow],
      );

      project = Project(
        id: 'p1',
        name: 'Transition Test Project',
        videoClips: [clip1, clip2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      viewModel = EditorViewModel(initialProject: project);
    });

    testWidgets('renders transition badge and effect when playhead is in transition window',
        (WidgetTester tester) async {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 2.0,
        leftClipId: 'c1',
        rightClipId: 'c2',
      );
      viewModel.addTransition(transition);

      // Seek to midpoint of transition (boundary is at 5.0s, window is 4.0s - 6.0s)
      viewModel.seekTo(5.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );

      // Verify the active transition badge is displayed
      expect(find.textContaining('TRANSITION: FADE 50%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    for (final type in TransitionType.values) {
      if (type == TransitionType.none) continue;

      testWidgets('renders transition effect successfully for $type', (WidgetTester tester) async {
        final transition = Transition(
          type: type,
          duration: 2.0,
          leftClipId: 'c1',
          rightClipId: 'c2',
        );
        viewModel.addTransition(transition);

        // Test at 25% progress (4.5s)
        viewModel.seekTo(4.5);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VideoPreviewSection(viewModel: viewModel),
            ),
          ),
        );
        expect(tester.takeException(), isNull);

        // Test at 75% progress (5.5s)
        viewModel.seekTo(5.5);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VideoPreviewSection(viewModel: viewModel),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
      });
    }

    testWidgets('renders standard canvas when playhead is outside transition window',
        (WidgetTester tester) async {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 2.0,
        leftClipId: 'c1',
        rightClipId: 'c2',
      );
      viewModel.addTransition(transition);

      // Seek before transition
      viewModel.seekTo(2.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(viewModel: viewModel),
          ),
        ),
      );

      // Transition badge should NOT be present
      expect(find.textContaining('TRANSITION:'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
