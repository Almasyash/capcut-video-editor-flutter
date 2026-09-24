import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPreviewSection & Duplicate GlobalKey Regression Tests', () {
    late EditorViewModel viewModel;
    late Project testProject;

    setUp(() {
      testProject = Project(
        id: 'test_preview_proj',
        name: 'Preview Key Test',
        videoClips: const [
          VideoClip(
            id: 'clip_1',
            assetId: 'asset_1',
            title: 'Clip 1',
            originalDuration: Duration(seconds: 4),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 4),
            previewGradient: [Colors.blue, Colors.green],
          ),
          VideoClip(
            id: 'clip_2',
            assetId: 'asset_2',
            title: 'Clip 2',
            originalDuration: Duration(seconds: 4),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 4),
            previewGradient: [Colors.purple, Colors.pink],
          ),
        ],
        transitions: [
          Transition(
            id: 'trans_1',
            leftClipId: 'clip_1',
            rightClipId: 'clip_2',
            type: TransitionType.fade,
            duration: 1.0,
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      viewModel = EditorViewModel(
        initialProject: testProject,
        enableMockFallback: true,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets('1. VideoPreviewSection mounts cleanly with stable ValueKey', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(
              key: const ValueKey('mobile_video_preview'),
              viewModel: viewModel,
            ),
          ),
        ),
      );

      expect(find.byType(VideoPreviewSection), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile_video_preview')), findsOneWidget);
    });

    testWidgets('2. Transition overlap rendering does NOT create duplicate GlobalKeys', (tester) async {
      // Position playhead inside transition overlap (3.5s)
      viewModel.seekTo(3.5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(
              key: const ValueKey('mobile_video_preview'),
              viewModel: viewModel,
            ),
          ),
        ),
      );

      expect(find.byType(VideoPreviewSection), findsOneWidget);
      // No duplicate GlobalKey exception
    });

    testWidgets('3. EditorScreen renders responsive layout without duplicate GlobalKey error', (tester) async {
      // Mobile screen size (< 850)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('GlobalKey') || details.toString().contains('duplicate')) {
          caughtError = details;
        }
      };

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(initialProject: testProject),
          ),
        );
        await tester.pump();

        expect(find.byType(VideoPreviewSection), findsOneWidget);
        expect(caughtError, isNull, reason: 'No duplicate GlobalKey error on mobile');

        // Switch to Desktop size (>= 850)
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(initialProject: testProject),
          ),
        );
        await tester.pump();

        expect(find.byType(VideoPreviewSection), findsOneWidget);
        expect(caughtError, isNull, reason: 'No duplicate GlobalKey error when switching responsive layout');
      } finally {
        FlutterError.onError = originalOnError;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
      }
    });

    testWidgets('4. Switching transition duration, type, seeking does not throw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreviewSection(
              key: const ValueKey('mobile_video_preview'),
              viewModel: viewModel,
            ),
          ),
        ),
      );

      // Seek through transition
      viewModel.seekTo(3.2);
      await tester.pump();

      viewModel.seekTo(3.8);
      await tester.pump();

      // Change transition type
      viewModel.addTransition(
        Transition(
          id: 'trans_2',
          leftClipId: 'clip_1',
          rightClipId: 'clip_2',
          type: TransitionType.wipeRight,
          duration: 1.5,
        ),
      );
      await tester.pump();

      // Undo & Redo
      if (viewModel.canUndo) {
        viewModel.undo();
        await tester.pump();
      }

      if (viewModel.canRedo) {
        viewModel.redo();
        await tester.pump();
      }

      // Flush autosave timer
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(VideoPreviewSection), findsOneWidget);
    });
  });
}
