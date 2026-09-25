import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/ui/features/editor/views/editor_screen.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/video_preview_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_clip_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Timeline Full-Screen Exit Layout Reproduction Tests', () {
    late Project testProject;

    setUp(() {
      testProject = Project(
        id: 'fullscreen_timeline_test',
        name: 'Fullscreen Timeline Test',
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
          VideoClip(
            id: 'clip_3',
            assetId: 'asset_3',
            title: 'Clip 3',
            originalDuration: Duration(seconds: 4),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 4),
            previewGradient: [Colors.orange, Colors.red],
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
    });

    testWidgets('Entering and exiting full-screen preview verifies clip layout and rebuild', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(initialProject: testProject),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(VideoPreviewSection), findsOneWidget);
      expect(find.byType(TimelineSection), findsOneWidget);

      final clipsInitial = find.byType(TimelineClipItem);
      expect(clipsInitial, findsNWidgets(3));

      // Get initial rects of clips on main track
      final rect1Before = tester.getRect(find.byKey(const ValueKey('clip_1')));
      final rect2Before = tester.getRect(find.byKey(const ValueKey('clip_2')));
      final rect3Before = tester.getRect(find.byKey(const ValueKey('clip_3')));

      debugPrint('Before Fullscreen:');
      debugPrint('Clip 1 rect: $rect1Before');
      debugPrint('Clip 2 rect: $rect2Before');
      debugPrint('Clip 3 rect: $rect3Before');

      // Verify no overlap before entering fullscreen
      expect(rect1Before.right <= rect2Before.left + 0.1, isTrue, reason: 'Clip 1 and 2 do not overlap');
      expect(rect2Before.right <= rect3Before.left + 0.1, isTrue, reason: 'Clip 2 and 3 do not overlap');

      // Tap fullscreen toggle button
      final fullscreenBtn = find.byIcon(Icons.fullscreen_rounded);
      expect(fullscreenBtn, findsOneWidget);
      await tester.tap(fullscreenBtn);
      await tester.pumpAndSettle();

      // Verify fullscreen mode is active
      expect(find.textContaining('Fullscreen Mode'), findsOneWidget);

      // Scrub playhead inside fullscreen slider to 6.0 seconds (into Clip 2)
      final overlaySliders = find.byType(Slider);
      expect(overlaySliders, findsNWidgets(2));
      // The fullscreen scrubber slider has min: 0.0, max: 12.0
      final scrubberFinder = find.byWidgetPredicate(
        (w) => w is Slider && w.min == 0.0,
      );
      expect(scrubberFinder, findsOneWidget);
      await tester.tap(scrubberFinder);
      await tester.pumpAndSettle();

      // Exit fullscreen
      final minimizeBtn = find.byIcon(Icons.fullscreen_exit_rounded);
      expect(minimizeBtn, findsOneWidget);
      await tester.tap(minimizeBtn);
      await tester.pumpAndSettle();

      // Now verify state after exiting fullscreen
      expect(find.byType(VideoPreviewSection), findsOneWidget);
      expect(find.byType(TimelineSection), findsOneWidget);

      final clipsAfter = find.byType(TimelineClipItem);
      expect(clipsAfter, findsNWidgets(3));

      final rect1After = tester.getRect(find.byKey(const ValueKey('clip_1')));
      final rect2After = tester.getRect(find.byKey(const ValueKey('clip_2')));
      final rect3After = tester.getRect(find.byKey(const ValueKey('clip_3')));

      debugPrint('After Fullscreen Exit:');
      debugPrint('Clip 1 rect: $rect1After');
      debugPrint('Clip 2 rect: $rect2After');
      debugPrint('Clip 3 rect: $rect3After');

      // Check whether clips overlap or incorrectly display
      expect(rect1After.right <= rect2After.left + 0.1, isTrue,
          reason: 'Clip 1 and Clip 2 must NOT overlap after exiting fullscreen');
      expect(rect2After.right <= rect3After.left + 0.1, isTrue,
          reason: 'Clip 2 and Clip 3 must NOT overlap after exiting fullscreen');
    });
  });
}
