import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

Project _createTestProject({List<VideoClip> clips = const [], List<TextOverlay> texts = const []}) {
  return Project(
    id: 'test_editing_controls_project',
    name: 'Test Editing Controls Project',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    videoClips: clips,
    textOverlays: texts,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7.5 — Video Speed Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      const clip = VideoClip(
        id: 'clip_speed_1',
        assetId: 'asset_1',
        title: 'Speed Test Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        speed: 1.0,
        volume: 1.0,
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel = EditorViewModel(
        initialProject: _createTestProject(clips: [clip]),
      );
    });

    test('Default speed is 1.0x and activeDuration matches original duration', () {
      expect(viewModel.videoClips[0].speed, 1.0);
      expect(viewModel.videoClips[0].activeDuration, const Duration(seconds: 10));
      expect(viewModel.videoClips[0].durationInSeconds, 10.0);
    });

    test('Setting speed to 2.0x halves activeDuration to 5s', () {
      viewModel.selectClip(0);
      viewModel.setClipSpeed(2.0);

      expect(viewModel.videoClips[0].speed, 2.0);
      expect(viewModel.videoClips[0].activeDuration, const Duration(seconds: 5));
      expect(viewModel.videoClips[0].durationInSeconds, 5.0);
      expect(viewModel.totalDurationInSeconds, 5.0);
    });

    test('Setting speed to 0.5x doubles activeDuration to 20s', () {
      viewModel.selectClip(0);
      viewModel.setClipSpeed(0.5);

      expect(viewModel.videoClips[0].speed, 0.5);
      expect(viewModel.videoClips[0].activeDuration, const Duration(seconds: 20));
      expect(viewModel.videoClips[0].durationInSeconds, 20.0);
      expect(viewModel.totalDurationInSeconds, 20.0);
    });

    test('Speed is clamped between 0.25x and 4.0x', () {
      viewModel.selectClip(0);
      viewModel.setClipSpeed(0.1);
      expect(viewModel.videoClips[0].speed, 0.25);

      viewModel.setClipSpeed(10.0);
      expect(viewModel.videoClips[0].speed, 4.0);
    });

    test('Playhead is clamped if duration shortens below current playhead', () {
      viewModel.seekTo(8.0);
      expect(viewModel.playheadPosition, 8.0);

      viewModel.selectClip(0);
      viewModel.setClipSpeed(2.0);

      expect(viewModel.playheadPosition, 5.0);
    });

    test('Speed change is reversible via Undo and Redo', () {
      viewModel.selectClip(0);
      viewModel.setClipSpeed(2.0);
      expect(viewModel.videoClips[0].speed, 2.0);
      expect(viewModel.canUndo, isTrue);

      viewModel.undo();
      expect(viewModel.videoClips[0].speed, 1.0);
      expect(viewModel.canRedo, isTrue);

      viewModel.redo();
      expect(viewModel.videoClips[0].speed, 2.0);
    });
  });

  group('Phase 7.5 — Video Volume & Mute Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      const clip = VideoClip(
        id: 'clip_vol_1',
        assetId: 'asset_1',
        title: 'Volume Test Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        volume: 1.0,
        isMuted: false,
        previewGradient: [Colors.blue, Colors.purple],
      );
      viewModel = EditorViewModel(
        initialProject: _createTestProject(clips: [clip]),
      );
    });

    test('Default volume is 1.0 and effectiveVolume is 1.0 when not muted', () {
      expect(viewModel.videoClips[0].volume, 1.0);
      expect(viewModel.videoClips[0].isMuted, isFalse);
      expect(viewModel.videoClips[0].effectiveVolume, 1.0);
    });

    test('toggleClipMute toggles isMuted and sets effectiveVolume to 0.0 without losing volume setting', () {
      viewModel.selectClip(0);
      viewModel.toggleClipMute();

      expect(viewModel.videoClips[0].isMuted, isTrue);
      expect(viewModel.videoClips[0].volume, 1.0);
      expect(viewModel.videoClips[0].effectiveVolume, 0.0);

      viewModel.toggleClipMute();
      expect(viewModel.videoClips[0].isMuted, isFalse);
      expect(viewModel.videoClips[0].volume, 1.0);
      expect(viewModel.videoClips[0].effectiveVolume, 1.0);
    });

    test('Setting volume to 0.0 automatically marks clip as muted', () {
      viewModel.selectClip(0);
      viewModel.setClipVolume(0.0);

      expect(viewModel.videoClips[0].volume, 0.0);
      expect(viewModel.videoClips[0].isMuted, isTrue);
      expect(viewModel.videoClips[0].effectiveVolume, 0.0);
    });

    test('Setting volume > 0.0 automatically unmutes the clip', () {
      viewModel.selectClip(0);
      viewModel.toggleClipMute();
      expect(viewModel.videoClips[0].isMuted, isTrue);

      viewModel.setClipVolume(0.75);
      expect(viewModel.videoClips[0].volume, 0.75);
      expect(viewModel.videoClips[0].isMuted, isFalse);
      expect(viewModel.videoClips[0].effectiveVolume, 0.75);
    });

    test('Volume and Mute changes are preserved through Undo / Redo', () {
      viewModel.selectClip(0);
      viewModel.toggleClipMute();
      expect(viewModel.videoClips[0].isMuted, isTrue);

      viewModel.undo();
      expect(viewModel.videoClips[0].isMuted, isFalse);
      expect(viewModel.videoClips[0].effectiveVolume, 1.0);

      viewModel.redo();
      expect(viewModel.videoClips[0].isMuted, isTrue);
      expect(viewModel.videoClips[0].effectiveVolume, 0.0);
    });
  });

  group('Phase 7.5 — Video Trim & Split Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      const clip = VideoClip(
        id: 'clip_split_1',
        assetId: 'asset_1',
        title: 'Split Clip',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        speed: 2.0,
        volume: 0.8,
        isMuted: false,
        xPos: 12.0,
        yPos: -8.0,
        scale: 1.35,
        rotationAngle: 0.25,
        flipHorizontal: true,
        previewGradient: [Colors.teal, Colors.green],
      );
      viewModel = EditorViewModel(
        initialProject: _createTestProject(clips: [clip]),
      );
    });

    test('splitClipAtPlayhead preserves spatial transforms, speed, volume, and flip states', () {
      viewModel.seekTo(2.5);
      final success = viewModel.splitClipAtPlayhead();

      expect(success, isTrue);
      expect(viewModel.videoClips.length, 2);

      final partA = viewModel.videoClips[0];
      final partB = viewModel.videoClips[1];

      expect(partA.speed, 2.0);
      expect(partA.volume, 0.8);
      expect(partA.xPos, 12.0);
      expect(partA.yPos, -8.0);
      expect(partA.scale, 1.35);
      expect(partA.rotationAngle, 0.25);
      expect(partA.flipHorizontal, isTrue);
      expect(partA.trimStart, Duration.zero);
      expect(partA.trimEnd.inMilliseconds, closeTo(5000, 50));

      expect(partB.speed, 2.0);
      expect(partB.volume, 0.8);
      expect(partB.xPos, 12.0);
      expect(partB.yPos, -8.0);
      expect(partB.scale, 1.35);
      expect(partB.rotationAngle, 0.25);
      expect(partB.flipHorizontal, isTrue);
      expect(partB.trimStart.inMilliseconds, closeTo(5000, 50));
      expect(partB.trimEnd, const Duration(seconds: 10));

      expect(partA.durationInSeconds + partB.durationInSeconds, closeTo(5.0, 0.05));
    });

    test('trimLeftToPlayhead adjusts trimStart taking speed into account', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.5);
      final success = viewModel.trimLeftToPlayhead();

      expect(success, isTrue);
      expect(viewModel.videoClips[0].trimStart.inMilliseconds, closeTo(3000, 50));
      expect(viewModel.videoClips[0].durationInSeconds, closeTo(3.5, 0.05));
    });

    test('trimRightToPlayhead adjusts trimEnd taking speed into account', () {
      viewModel.selectClip(0);
      viewModel.seekTo(3.5);
      final success = viewModel.trimRightToPlayhead();

      expect(success, isTrue);
      expect(viewModel.videoClips[0].trimEnd.inMilliseconds, closeTo(7000, 50));
      expect(viewModel.videoClips[0].durationInSeconds, closeTo(3.5, 0.05));
    });
  });

  group('Phase 7.5 — Delete & Ripple Delete Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      const clip1 = VideoClip(
        id: 'clip_1',
        assetId: 'asset_1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        previewGradient: [Colors.blue, Colors.cyan],
      );
      const clip2 = VideoClip(
        id: 'clip_2',
        assetId: 'asset_2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 6),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 6),
        previewGradient: [Colors.amber, Colors.orange],
      );
      const clip3 = VideoClip(
        id: 'clip_3',
        assetId: 'asset_3',
        title: 'Clip 3',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.purple, Colors.pink],
      );
      viewModel = EditorViewModel(
        initialProject: _createTestProject(clips: [clip1, clip2, clip3]),
      );
    });

    test('rippleDeleteSelectedClip shifts subsequent clips and closes gap', () {
      expect(viewModel.videoClips.length, 3);
      expect(viewModel.totalDurationInSeconds, 15.0);

      viewModel.selectClip(1);
      viewModel.seekTo(7.0);

      final success = viewModel.rippleDeleteSelectedClip();
      expect(success, isTrue);
      expect(viewModel.videoClips.length, 2);
      expect(viewModel.videoClips[0].id, 'clip_1');
      expect(viewModel.videoClips[1].id, 'clip_3');
      expect(viewModel.totalDurationInSeconds, 9.0);

      expect(viewModel.playheadPosition, 4.0);
      expect(viewModel.selectedClipIndex, 1);
    });

    test('deleteSelectedClip preserves selection bounds safely', () {
      viewModel.selectClip(2);
      viewModel.deleteSelectedClip();

      expect(viewModel.videoClips.length, 2);
      expect(viewModel.selectedClipIndex, 1);
    });
  });

  group('Phase 7.5 — Text Layer Editing Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel(
        initialProject: _createTestProject(),
      );
    });

    test('Adding and editing a text overlay updates timeline correctly', () {
      const overlay = TextOverlay(
        id: 'text_1',
        text: 'Title Headline',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
        textColor: Colors.yellow,
        fontSize: 28.0,
        position: Offset(0.5, 0.8),
        isBold: true,
      );

      viewModel.addTextOverlay(overlay);
      expect(viewModel.textOverlays.length, 1);
      expect(viewModel.textOverlays[0].text, 'Title Headline');
      expect(viewModel.textOverlays[0].startTimeInSeconds, 1.0);
      expect(viewModel.textOverlays[0].durationInSeconds, 4.0);
      expect(viewModel.textOverlays[0].endTimeInSeconds, 5.0);

      viewModel.updateTextPosition('text_1', const Offset(0.3, 0.4));
      expect(viewModel.textOverlays[0].position, const Offset(0.3, 0.4));

      viewModel.removeTextOverlay('text_1');
      expect(viewModel.textOverlays.isEmpty, isTrue);
    });
  });
}
