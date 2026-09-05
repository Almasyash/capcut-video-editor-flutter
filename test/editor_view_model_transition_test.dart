import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  group('EditorViewModel Transition Tests', () {
    late EditorViewModel viewModel;
    late VideoClip clip1;
    late VideoClip clip2;
    late Project initialProject;

    setUp(() {
      clip1 = const VideoClip(
        id: 'clip1',
        assetId: 'asset1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.black, Colors.white],
      );

      clip2 = const VideoClip(
        id: 'clip2',
        assetId: 'asset2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        previewGradient: [Colors.black, Colors.white],
      );

      initialProject = Project(
        id: 'test_proj',
        name: 'Test Project',
        videoClips: [clip1, clip2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      viewModel = EditorViewModel(initialProject: initialProject);
    });

    test('addTransition successfully adds a valid transition', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 1.0,
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      final result = viewModel.addTransition(transition);

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(viewModel.transitions.length, 1);
      expect(viewModel.transitions.first.id, transition.id);
    });

    test('addTransition rejects an invalid transition (too long)', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 15.0, // Exceeds clip duration
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      final result = viewModel.addTransition(transition);

      expect(result.success, isFalse);
      expect(result.errors, isNotEmpty);
      expect(viewModel.transitions, isEmpty); // Unchanged
    });

    test('undo/redo restores transitions properly', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 1.0,
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      viewModel.addTransition(transition);
      expect(viewModel.transitions.length, 1);

      viewModel.undo();
      expect(viewModel.transitions, isEmpty);

      viewModel.redo();
      expect(viewModel.transitions.length, 1);
      expect(viewModel.transitions.first.id, transition.id);
    });

    test('removeTransition removes an existing transition', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 1.0,
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      viewModel.addTransition(transition);
      expect(viewModel.transitions.length, 1);

      final result = viewModel.removeTransition(transition.id);
      expect(result.success, isTrue);
      expect(viewModel.transitions, isEmpty);
    });

    test('editTransition updates an existing transition', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 1.0,
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      viewModel.addTransition(transition);

      final updated = transition.copyWith(duration: 1.5);
      final result = viewModel.editTransition(id: transition.id, newTransition: updated);

      expect(result.success, isTrue);
      expect(viewModel.transitions.first.duration, 1.5);
    });

    test('clip mutation cleans up invalid transitions', () {
      final transition = Transition(
        type: TransitionType.fade,
        duration: 2.0, // Needs 2.0 seconds from clip1
        leftClipId: 'clip1',
        rightClipId: 'clip2',
      );

      viewModel.addTransition(transition);
      expect(viewModel.transitions.length, 1);

      // Mutate clip1 so its duration is shorter than the transition duration
      // clip1 duration was 10. Trim it to 1 second.
      viewModel.updateClipTrim(0, Duration.zero, const Duration(milliseconds: 500));

      // After trimming, the transition should be cleaned up because it exceeds the remaining 0.5s duration
      expect(viewModel.transitions, isEmpty);
    });
  });
}
