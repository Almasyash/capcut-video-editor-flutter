import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/audio_track_item.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_clip_item.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_ruler.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';

void main() {
  group('Timeline Multi-Layer & Vertical Scrolling Tests', () {
    testWidgets('1. Fresh project initializes with clean timeline and 0 audio tracks', (tester) async {
      final viewModel = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineSection(viewModel: viewModel),
          ),
        ),
      );
      await tester.pump();

      expect(viewModel.audioTracks.length, 0);
      expect(find.byType(AudioTrackItem), findsNothing);
      expect(find.byType(TimelineRuler), findsOneWidget);
      expect(find.byType(TimelineClipItem), findsWidgets);
      viewModel.dispose();
    });

    testWidgets('2. Timeline renders with 1 layer without any overflow', (tester) async {
      final viewModel = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineClipItem), findsWidgets);
      viewModel.dispose();
    });

    testWidgets('3. Timeline with 5+ layers (video, overlay, effect, text, audio) renders cleanly', (tester) async {
      final project = Project(
        id: 'test_5_layers',
        name: '5 Layers Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        overlayClips: const [
          OverlayClip(
            id: 'pip_1',
            title: 'PIP Layer 1',
            startTime: Duration.zero,
            duration: Duration(seconds: 5),
          ),
        ],
        activeEffect: VideoEffect.presets[1], // Glitch Art
        textOverlays: const [
          TextOverlay(
            id: 'text_1',
            text: 'Title Overlay',
            startTime: Duration.zero,
            duration: Duration(seconds: 4),
          ),
        ],
        audioTracks: const [
          AudioTrack(
            id: 'audio_1',
            assetId: 'asset_audio_1',
            title: 'Background Music',
            artist: 'Artist',
            duration: Duration(seconds: 10),
          ),
        ],
      );

      final viewModel = EditorViewModel(initialProject: project);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 220,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('PIP Layer 1'), findsOneWidget);
      expect(find.textContaining('Effect: Glitch Art'), findsOneWidget);
      expect(find.text('Title Overlay'), findsOneWidget);
      expect(find.textContaining('Background Music'), findsOneWidget);
      viewModel.dispose();
    });

    testWidgets('4. Multi-Layer Scaling: 15+ layers render with ZERO RenderFlex overflow', (tester) async {
      final List<OverlayClip> pips = List.generate(
        4,
        (i) => OverlayClip(
          id: 'pip_$i',
          title: 'PIP Track #$i',
          startTime: Duration(seconds: i * 2),
          duration: const Duration(seconds: 4),
        ),
      );

      final List<TextOverlay> texts = List.generate(
        4,
        (i) => TextOverlay(
          id: 'text_$i',
          text: 'Text Subtitle #$i',
          startTime: Duration(seconds: i * 2),
          duration: const Duration(seconds: 3),
        ),
      );

      final List<AudioTrack> audios = List.generate(
        6,
        (i) => AudioTrack(
          id: 'audio_$i',
          assetId: 'asset_audio_$i',
          title: 'SFX Track #$i',
          artist: 'Library',
          duration: const Duration(seconds: 8),
        ),
      );

      final List<StickerOverlay> stickers = [
        const StickerOverlay(
          id: 'sticker_1',
          preset: StickerPreset(
            id: 'stk_1',
            label: 'Sparkle',
            content: '✨',
            category: StickerCategory.emojis,
          ),
          startTime: Duration.zero,
          duration: Duration(seconds: 4),
        ),
      ];

      final project = Project(
        id: 'massive_multi_layer',
        name: 'Massive Multi-Layer Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        overlayClips: pips,
        activeEffect: VideoEffect.presets[2], // VHS Cam
        textOverlays: texts,
        stickerOverlays: stickers,
        audioTracks: audios,
      );

      final viewModel = EditorViewModel(initialProject: project);

      // Render in constrained timeline viewport (180dp height)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 180,
              width: 380,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure no RenderFlex or layout exceptions occurred
      expect(tester.takeException(), isNull);

      // Verify that all 6 audio tracks, 4 PIPs, 4 text overlays, stickers, and effect exist in tree
      expect(find.byType(AudioTrackItem), findsNWidgets(6));
      expect(find.text('PIP Track #0'), findsOneWidget);
      expect(find.text('Text Subtitle #0'), findsOneWidget);
      expect(find.textContaining('Effect: VHS Cam'), findsOneWidget);
      expect(find.text('Sparkle'), findsOneWidget);

      viewModel.dispose();
    });

    testWidgets('5. Vertical layer scrolling works smoothly without affecting playhead', (tester) async {
      final List<AudioTrack> audios = List.generate(
        8,
        (i) => AudioTrack(
          id: 'scroll_audio_$i',
          assetId: 'asset_scroll_audio_$i',
          title: 'Sound Track #$i',
          artist: 'Sound FX',
          duration: const Duration(seconds: 12),
        ),
      );

      final project = Project(
        id: 'scroll_test_proj',
        name: 'Scroll Test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        audioTracks: audios,
      );

      final viewModel = EditorViewModel(initialProject: project);
      final initialPlayhead = viewModel.playheadPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      // Drag vertically on the timeline
      await tester.drag(find.byType(TimelineSection), const Offset(0, -200));
      await tester.pumpAndSettle();

      // Playhead position should remain intact during vertical scrolling
      expect(viewModel.playheadPosition, initialPlayhead);
      expect(tester.takeException(), isNull);

      viewModel.dispose();
    });

    testWidgets('6. Horizontal scrubbing updates playhead independently of vertical scrolling', (tester) async {
      final viewModel = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 240,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      // Horizontal drag on timeline
      await tester.drag(find.byType(TimelineSection), const Offset(-100, 0));
      await tester.pumpAndSettle();

      // Playhead should have moved forward
      expect(viewModel.playheadPosition, greaterThan(0.0));
      expect(tester.takeException(), isNull);

      viewModel.dispose();
    });

    testWidgets('7. Pinned TimelineRuler stays rendered at top of timeline canvas', (tester) async {
      final viewModel = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 240,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TimelineRuler), findsOneWidget);
      viewModel.dispose();
    });

    testWidgets('8. Auto-scroll mechanism triggers safely when layers are dynamically added', (tester) async {
      final viewModel = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: TimelineSection(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pump();

      // Add multiple audio tracks dynamically
      for (int i = 0; i < 5; i++) {
        viewModel.addAudioTrack(
          AudioTrack(
            id: 'dyn_audio_$i',
            assetId: 'dyn_asset_$i',
            title: 'Dynamic Beat #$i',
            artist: 'Editor',
            duration: const Duration(seconds: 15),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(viewModel.audioTracks.length, 5);
      expect(find.byType(AudioTrackItem), findsNWidgets(5));
      expect(tester.takeException(), isNull);

      viewModel.dispose();
    });
  });
}
