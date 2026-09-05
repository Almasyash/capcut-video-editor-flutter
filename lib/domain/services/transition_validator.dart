import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';

/// Validates transitions against the current project state.
///
/// Returns a list of error messages; empty list means the transition is valid.
class TransitionValidator {
  final Project project;

  TransitionValidator(this.project);

  /// Validate the whole project transition set.
  List<String> validateAll(List<Transition> candidateTransitions) {
    // We create a temporary candidate project with the new transitions
    // to reuse the existing rules without modifying the live project instance.
    final candidateProject = project.copyWith(transitions: candidateTransitions);
    final temporaryValidator = TransitionValidator(candidateProject);
    final allErrors = <String>[];
    for (final t in candidateTransitions) {
      allErrors.addAll(temporaryValidator.validate(t));
    }
    return allErrors;
  }

  /// Validate a single [transition].
  List<String> validate(Transition transition) {
    final errors = <String>[];
    // 1. left clip exists
    VideoClip? leftClip;
    try {
      leftClip = project.videoClips.firstWhere((c) => c.id == transition.leftClipId);
    } catch (_) {}

    if (leftClip == null) {
      errors.add('Left clip (id=${transition.leftClipId}) does not exist');
    }
    
    // 2. right clip exists
    VideoClip? rightClip;
    try {
      rightClip = project.videoClips.firstWhere((c) => c.id == transition.rightClipId);
    } catch (_) {}

    if (rightClip == null) {
      errors.add('Right clip (id=${transition.rightClipId}) does not exist');
    }

    // 4. adjacency: left end == right start (consider trims)
    if (leftClip != null && rightClip != null) {
      final leftIndex = project.videoClips.indexOf(leftClip);
      final rightIndex = project.videoClips.indexOf(rightClip);
      if (rightIndex != leftIndex + 1) {
        errors.add('Clips are not adjacent in the timeline');
      }
    }
    
    // 5. duration constraints
    final duration = transition.duration;
    if (duration < 0.1) {
      errors.add('Transition duration must be >= 0.1s');
    }
    if (duration > 2.0) {
      errors.add('Transition duration must be <= 2.0s');
    }
    
    // 6. usable left duration (consider trim and speed)
    if (leftClip != null) {
      final usableLeft = _usableDuration(leftClip);
      if (duration > usableLeft) {
        errors.add('Transition duration exceeds usable left clip duration ($usableLeft s)');
      }
    }
    // 7. usable right duration
    if (rightClip != null) {
      final usableRight = _usableDuration(rightClip);
      if (duration > usableRight) {
        errors.add('Transition duration exceeds usable right clip duration ($usableRight s)');
      }
    }
    return errors;
  }

  /// Helper to compute usable duration after trim and speed.
  double _usableDuration(VideoClip clip) {
    final start = clip.trimStart.inMilliseconds / 1000.0;
    final end = clip.trimEnd.inMilliseconds / 1000.0;
    final base = (end - start).clamp(0.0, clip.originalDuration.inMilliseconds / 1000.0);
    final speed = clip.speed;
    return base / speed;
  }
}
