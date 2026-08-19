import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';

void main() {
  group('EditorViewModel State & Actions Test', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initial state loads mock clips, audio track, and text overlays', () {
      expect(viewModel.videoClips.isNotEmpty, isTrue);
      expect(viewModel.selectedClipIndex, equals(0));
      expect(viewModel.playheadPosition, equals(0.0));
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.audioTrack, isNotNull);
      expect(viewModel.textOverlays.isNotEmpty, isTrue);
      expect(viewModel.totalDurationInSeconds, greaterThan(0));
    });

    test('Split at playhead splits the target clip into two valid segments', () {
      final initialCount = viewModel.videoClips.length;
      final initialTotalDuration = viewModel.totalDurationInSeconds;

      // Position playhead at 2.5 seconds (inside first clip)
      viewModel.seekTo(2.5);

      final splitSuccess = viewModel.splitAtPlayhead();
      expect(splitSuccess, isTrue);
      expect(viewModel.videoClips.length, equals(initialCount + 1));

      // Total timeline duration should remain approximately unchanged
      expect((viewModel.totalDurationInSeconds - initialTotalDuration).abs(), lessThan(0.05));

      // Undo split
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();
      expect(viewModel.videoClips.length, equals(initialCount));

      // Redo split
      expect(viewModel.canRedo, isTrue);
      viewModel.redo();
      expect(viewModel.videoClips.length, equals(initialCount + 1));
    });

    test('Delete and duplicate clip operations work accurately', () {
      final initialCount = viewModel.videoClips.length;

      // Duplicate
      viewModel.selectClip(0);
      viewModel.duplicateSelectedClip();
      expect(viewModel.videoClips.length, equals(initialCount + 1));

      // Delete
      viewModel.deleteSelectedClip();
      expect(viewModel.videoClips.length, equals(initialCount));
    });

    test('Aspect ratio changing updates state properly', () {
      expect(viewModel.aspectRatio, equals(AspectRatioPreset.ratio9x16));
      viewModel.setAspectRatio(AspectRatioPreset.ratio16x9);
      expect(viewModel.aspectRatio, equals(AspectRatioPreset.ratio16x9));
    });
  });
}
