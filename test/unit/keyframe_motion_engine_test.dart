import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EasingCurve & Cubic Bezier Solver Tests', () {
    test('Standard interpolation modes evaluate correctly at 0, 0.5, 1.0', () {
      // Linear
      expect(EasingCurve.linear.solve(0.0), equals(0.0));
      expect(EasingCurve.linear.solve(0.5), equals(0.5));
      expect(EasingCurve.linear.solve(1.0), equals(1.0));

      // Ease In (cubic slow start)
      expect(EasingCurve.easeIn.solve(0.0), equals(0.0));
      expect(EasingCurve.easeIn.solve(0.5), equals(0.125));
      expect(EasingCurve.easeIn.solve(1.0), equals(1.0));

      // Ease Out (cubic slow finish)
      expect(EasingCurve.easeOut.solve(0.0), equals(0.0));
      expect(EasingCurve.easeOut.solve(0.5), equals(0.875));
      expect(EasingCurve.easeOut.solve(1.0), equals(1.0));

      // Ease In Out (S-curve)
      expect(EasingCurve.easeInOut.solve(0.0), closeTo(0.0, 1e-4));
      expect(EasingCurve.easeInOut.solve(0.5), closeTo(0.5, 1e-4));
      expect(EasingCurve.easeInOut.solve(1.0), closeTo(1.0, 1e-4));
      expect(EasingCurve.easeInOut.solve(0.25), lessThan(0.25));
      expect(EasingCurve.easeInOut.solve(0.75), greaterThan(0.75));

      // Hold (step function: 0 until 1.0)
      expect(EasingCurve.hold.solve(0.0), equals(0.0));
      expect(EasingCurve.hold.solve(0.5), equals(0.0));
      expect(EasingCurve.hold.solve(0.999), equals(0.0));
      expect(EasingCurve.hold.solve(1.0), equals(1.0));
    });

    test('Custom Cubic Bezier solves via Newton-Raphson with exact boundary clamping', () {
      const customBezier = EasingCurve(
        mode: InterpolationMode.cubicBezier,
        x1: 0.25,
        y1: 0.1,
        x2: 0.25,
        y2: 1.0,
      );

      expect(customBezier.solve(-0.1), equals(0.0));
      expect(customBezier.solve(0.0), equals(0.0));
      expect(customBezier.solve(1.0), equals(1.0));
      expect(customBezier.solve(1.2), equals(1.0));

      final mid = customBezier.solve(0.5);
      expect(mid, greaterThan(0.5)); // fast ramp-up
    });

    test('EasingCurve JSON serialization and deserialization roundtrip', () {
      const original = EasingCurve(
        mode: InterpolationMode.cubicBezier,
        x1: 0.17,
        y1: 0.67,
        x2: 0.83,
        y2: 0.67,
      );

      final json = original.toJson();
      final restored = EasingCurve.fromJson(json);

      expect(restored.mode, equals(InterpolationMode.cubicBezier));
      expect(restored.x1, closeTo(0.17, 1e-4));
      expect(restored.y1, closeTo(0.67, 1e-4));
      expect(restored.x2, closeTo(0.83, 1e-4));
      expect(restored.y2, closeTo(0.67, 1e-4));
    });
  });

  group('MotionKeyframe Model Tests', () {
    test('Creation, copyWith, and JSON roundtrip', () {
      const kf = MotionKeyframe(
        id: 'kf_test_1',
        timestampMs: 1500,
        value: 1.75,
        easing: EasingCurve.easeIn,
      );

      expect(kf.timeInSeconds, equals(1.5));
      expect(kf.value, equals(1.75));

      final copy = kf.copyWith(value: 2.0, timestampMs: 2000);
      expect(copy.id, equals('kf_test_1'));
      expect(copy.timestampMs, equals(2000));
      expect(copy.value, equals(2.0));
      expect(copy.easing.mode, equals(InterpolationMode.easeIn));

      final json = kf.toJson();
      final restored = MotionKeyframe.fromJson(json);
      expect(restored.id, equals('kf_test_1'));
      expect(restored.timestampMs, equals(1500));
      expect(restored.value, equals(1.75));
      expect(restored.easing.mode, equals(InterpolationMode.easeIn));
    });
  });

  group('KeyframeTrack Evaluation & Binary Search Tests', () {
    test('Empty track returns defaultValue', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        defaultValue: 1.0,
        keyframes: [],
      );

      expect(track.evaluate(0.0), equals(1.0));
      expect(track.evaluate(5.0), equals(1.0));
    });

    test('Single keyframe returns its value across entire timeline', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.opacity,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(id: 'k1', timestampMs: 2000, value: 0.6),
        ],
      );

      expect(track.evaluate(0.0), equals(0.6));
      expect(track.evaluate(2.0), equals(0.6));
      expect(track.evaluate(10.0), equals(0.6));
    });

    test('Boundary evaluation clamps to first and last keyframe values', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.positionX,
        defaultValue: 0.0,
        keyframes: [
          MotionKeyframe(id: 'k1', timestampMs: 1000, value: 50.0),
          MotionKeyframe(id: 'k2', timestampMs: 3000, value: 150.0),
        ],
      );

      // Before first keyframe
      expect(track.evaluate(0.0), equals(50.0));
      expect(track.evaluate(0.99), equals(50.0));

      // Exact first keyframe
      expect(track.evaluate(1.0), equals(50.0));

      // Exact last keyframe
      expect(track.evaluate(3.0), equals(150.0));

      // After last keyframe
      expect(track.evaluate(3.01), equals(150.0));
      expect(track.evaluate(10.0), equals(150.0));
    });

    test('Linear interpolation evaluates midpoints proportionally', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(
            id: 'k1',
            timestampMs: 0,
            value: 1.0,
            easing: EasingCurve.linear,
          ),
          MotionKeyframe(
            id: 'k2',
            timestampMs: 2000,
            value: 3.0,
            easing: EasingCurve.linear,
          ),
        ],
      );

      expect(track.evaluate(0.0), equals(1.0));
      expect(track.evaluate(1.0), closeTo(2.0, 1e-4));
      expect(track.evaluate(1.5), closeTo(2.5, 1e-4));
      expect(track.evaluate(2.0), equals(3.0));
    });

    test('Hold interpolation sustains prior value until next keyframe', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.positionY,
        defaultValue: 0.0,
        keyframes: [
          MotionKeyframe(
            id: 'k1',
            timestampMs: 0,
            value: 10.0,
            easing: EasingCurve.hold,
          ),
          MotionKeyframe(
            id: 'k2',
            timestampMs: 2000,
            value: 80.0,
          ),
        ],
      );

      expect(track.evaluate(0.0), equals(10.0));
      expect(track.evaluate(1.0), equals(10.0));
      expect(track.evaluate(1.98), equals(10.0));
      expect(track.evaluate(2.0), equals(80.0));
    });

    test('Multi-turn continuous rotation interpolates smoothly past 360 degrees', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.rotation,
        defaultValue: 0.0,
        keyframes: [
          MotionKeyframe(
            id: 'k1',
            timestampMs: 0,
            value: 0.0,
            easing: EasingCurve.linear,
          ),
          MotionKeyframe(
            id: 'k2',
            timestampMs: 4000,
            value: 720.0, // 2 full revolutions
            easing: EasingCurve.linear,
          ),
        ],
      );

      expect(track.evaluate(1.0), closeTo(180.0, 1e-4));
      expect(track.evaluate(2.0), closeTo(360.0, 1e-4));
      expect(track.evaluate(3.0), closeTo(540.0, 1e-4));
      expect(track.evaluate(4.0), equals(720.0));
    });

    test('getKeyframeAt snaps within tolerance threshold', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(id: 'k1', timestampMs: 1000, value: 1.5),
          MotionKeyframe(id: 'k2', timestampMs: 3000, value: 2.0),
        ],
      );

      // Within tolerance (15ms)
      expect(track.getKeyframeAt(1005, toleranceMs: 15), isNotNull);
      expect(track.getKeyframeAt(1005, toleranceMs: 15)!.id, equals('k1'));
      expect(track.getKeyframeAt(990, toleranceMs: 15), isNotNull);

      // Outside tolerance
      expect(track.getKeyframeAt(1030, toleranceMs: 15), isNull);
      expect(track.getKeyframeAt(2000, toleranceMs: 15), isNull);
    });

    test('splitAt divides track into two parts with boundary keyframes', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(id: 'k1', timestampMs: 0, value: 1.0, easing: EasingCurve.linear),
          MotionKeyframe(id: 'k2', timestampMs: 4000, value: 3.0, easing: EasingCurve.linear),
        ],
      );

      // Split at 2000ms (t = 2.0s, scale = 2.0)
      final (left, right) = track.splitAt(2000);

      expect(left.keyframes.length, equals(2));
      expect(left.keyframes.first.timestampMs, equals(0));
      expect(left.keyframes.first.value, equals(1.0));
      expect(left.keyframes.last.timestampMs, equals(2000));
      expect(left.keyframes.last.value, closeTo(2.0, 1e-3));

      expect(right.keyframes.length, equals(2));
      expect(right.keyframes.first.timestampMs, equals(0)); // relative to split point
      expect(right.keyframes.first.value, closeTo(2.0, 1e-3));
      expect(right.keyframes.last.timestampMs, equals(2000));
      expect(right.keyframes.last.value, equals(3.0));
    });

    test('duplicate creates identical values with fresh unique IDs', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.opacity,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(id: 'orig_1', timestampMs: 500, value: 0.5),
          MotionKeyframe(id: 'orig_2', timestampMs: 1500, value: 0.9),
        ],
      );

      final duplicated = track.duplicate();
      expect(duplicated.keyframes.length, equals(2));
      expect(duplicated.keyframes[0].value, equals(0.5));
      expect(duplicated.keyframes[1].value, equals(0.9));
      expect(duplicated.keyframes[0].id, isNot(equals('orig_1')));
      expect(duplicated.keyframes[1].id, isNot(equals('orig_2')));
    });

    test('clampToDuration drops keyframes past duration', () {
      const track = KeyframeTrack(
        property: AnimatableProperty.scale,
        defaultValue: 1.0,
        keyframes: [
          MotionKeyframe(id: 'k1', timestampMs: 0, value: 1.0, easing: EasingCurve.linear),
          MotionKeyframe(id: 'k2', timestampMs: 2000, value: 2.0, easing: EasingCurve.linear),
          MotionKeyframe(id: 'k3', timestampMs: 5000, value: 3.0, easing: EasingCurve.linear),
        ],
      );

      // Trim duration to 3000ms: drops k3 (5000ms), keeps k1 (0ms) and k2 (2000ms)
      final clamped = track.clampToDuration(3000);
      expect(clamped.keyframes.length, equals(2));
      expect(clamped.keyframes.last.timestampMs, equals(2000));
      expect(clamped.keyframes.last.value, equals(2.0));
    });
  });

  group('KeyframeTrackGroup Multi-Track Tests', () {
    test('addTransformKeyframe records all spatial properties simultaneously', () {
      var group = const KeyframeTrackGroup();

      group = group.addTransformKeyframe(
        timeMs: 1500,
        posX: 40.0,
        posY: -15.0,
        scale: 1.25,
        rotation: 45.0,
        opacity: 0.85,
      );

      expect(group.hasProperty(AnimatableProperty.positionX), isTrue);
      expect(group.hasProperty(AnimatableProperty.positionY), isTrue);
      expect(group.hasProperty(AnimatableProperty.scale), isTrue);
      expect(group.hasProperty(AnimatableProperty.rotation), isTrue);
      expect(group.hasProperty(AnimatableProperty.opacity), isTrue);

      expect(group.evaluate(AnimatableProperty.positionX, 1.5), equals(40.0));
      expect(group.evaluate(AnimatableProperty.positionY, 1.5), equals(-15.0));
      expect(group.evaluate(AnimatableProperty.scale, 1.5), equals(1.25));
      expect(group.evaluate(AnimatableProperty.rotation, 1.5), equals(45.0));
      expect(group.evaluate(AnimatableProperty.opacity, 1.5), equals(0.85));
    });

    test('evaluateAll evaluates complete property map at once', () {
      var group = const KeyframeTrackGroup();
      group = group.addTransformKeyframe(
        timeMs: 0,
        posX: 0.0,
        posY: 0.0,
        scale: 1.0,
        rotation: 0.0,
        opacity: 1.0,
      );
      group = group.addTransformKeyframe(
        timeMs: 2000,
        posX: 100.0,
        posY: 50.0,
        scale: 2.0,
        rotation: 90.0,
        opacity: 0.5,
      );

      final values = group.evaluateAll(1.0);
      expect(values[AnimatableProperty.positionX], closeTo(50.0, 1.0));
      expect(values[AnimatableProperty.positionY], closeTo(25.0, 1.0));
      expect(values[AnimatableProperty.scale], closeTo(1.5, 0.1));
      expect(values[AnimatableProperty.rotation], closeTo(45.0, 1.0));
    });

    test('KeyframeTrackGroup JSON serialization roundtrip', () {
      var group = const KeyframeTrackGroup();
      group = group.addTransformKeyframe(
        timeMs: 1000,
        posX: 12.5,
        posY: -8.0,
        scale: 1.5,
        rotation: 30.0,
        opacity: 1.0,
      );

      final json = group.toJson();
      final restored = KeyframeTrackGroup.fromJson(json);

      expect(restored.hasProperty(AnimatableProperty.positionX), isTrue);
      expect(restored.evaluate(AnimatableProperty.positionX, 1.0), equals(12.5));
      expect(restored.evaluate(AnimatableProperty.scale, 1.0), equals(1.5));
      expect(restored.evaluate(AnimatableProperty.rotation, 1.0), equals(30.0));
    });
  });

  group('Layer Models Keyframe Integration Tests', () {
    test('VideoClip keyframeTracks serialization & effectiveKeyframeTracks bridge', () {
      var group = const KeyframeTrackGroup();
      group = group.addTransformKeyframe(
        timeMs: 1000,
        posX: 0.0,
        posY: 0.0,
        scale: 1.8,
        rotation: 0.0,
        opacity: 1.0,
      );

      final clip = VideoClip(
        id: 'clip_1',
        assetId: 'asset_1',
        title: 'Video Segment',
        originalDuration: const Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        previewGradient: const [Color(0xFF000000), Color(0xFF111111)],
        keyframeTracks: group,
      );

      expect(clip.effectiveKeyframeTracks.hasProperty(AnimatableProperty.scale), isTrue);
      expect(clip.effectiveKeyframeTracks.evaluate(AnimatableProperty.scale, 1.0), equals(1.8));

      final json = clip.toJson();
      final restored = VideoClip.fromJson(json);
      expect(restored.keyframeTracks?.hasProperty(AnimatableProperty.scale), isTrue);
      expect(restored.keyframeTracks?.evaluate(AnimatableProperty.scale, 1.0), equals(1.8));
    });

    test('OverlayClip keyframeTracks serialization & backward-compatibility', () {
      var group = const KeyframeTrackGroup();
      group = group.addTransformKeyframe(
        timeMs: 500,
        posX: 0.5,
        posY: 0.5,
        scale: 1.0,
        rotation: 0.0,
        opacity: 0.6,
      );

      const overlay = OverlayClip(
        id: 'pip_1',
        title: 'PIP Test',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
      );
      final overlayWithKf = overlay.copyWith(keyframeTracks: group);

      expect(overlayWithKf.effectiveKeyframeTracks.hasProperty(AnimatableProperty.opacity), isTrue);
      expect(overlayWithKf.effectiveKeyframeTracks.evaluate(AnimatableProperty.opacity, 0.5), equals(0.6));

      final json = overlayWithKf.toJson();
      final restored = OverlayClip.fromJson(json);
      expect(restored.keyframeTracks?.hasProperty(AnimatableProperty.opacity), isTrue);
      expect(restored.keyframeTracks?.evaluate(AnimatableProperty.opacity, 0.5), equals(0.6));
    });

    test('TextOverlay keyframeTracks serialization & evaluation', () {
      var group = const KeyframeTrackGroup();
      group = group.addTransformKeyframe(
        timeMs: 2000,
        posX: 0.5,
        posY: 0.5,
        scale: 1.0,
        rotation: 180.0,
        opacity: 1.0,
      );

      const text = TextOverlay(
        id: 'txt_1',
        text: 'Title Motion',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
      );
      final textWithKf = text.copyWith(keyframeTracks: group);

      expect(textWithKf.effectiveKeyframeTracks.hasProperty(AnimatableProperty.rotation), isTrue);
      expect(textWithKf.effectiveKeyframeTracks.evaluate(AnimatableProperty.rotation, 2.0), equals(180.0));

      final json = textWithKf.toJson();
      final restored = TextOverlay.fromJson(json);
      expect(restored.keyframeTracks?.hasProperty(AnimatableProperty.rotation), isTrue);
    });

    test('AudioTrack getVolumeAt modulates keyframe volume with fade envelope', () {
      const trackGroup = KeyframeTrackGroup(
        tracks: {
          AnimatableProperty.volume: KeyframeTrack(
            property: AnimatableProperty.volume,
            defaultValue: 1.0,
            keyframes: [
              MotionKeyframe(id: 'vk1', timestampMs: 0, value: 0.5, easing: EasingCurve.linear),
              MotionKeyframe(id: 'vk2', timestampMs: 4000, value: 1.0, easing: EasingCurve.linear),
            ],
          ),
        },
      );

      const track = AudioTrack(
        id: 'audio_1',
        assetId: 'audio_asset_1',
        name: 'Background Music',
        volume: 1.0,
        duration: Duration(seconds: 4),
        fadeInDuration: Duration(seconds: 1),
        fadeOutDuration: Duration(seconds: 1),
        keyframeTracks: trackGroup,
      );

      // At start (0s): fade = 0.0 -> effective volume = 0.0
      expect(track.getVolumeAt(0.0), equals(0.0));

      // At midpoint (2s): keyframed volume = 0.75, outside fade -> effective volume = 0.75
      expect(track.getVolumeAt(2.0), closeTo(0.75, 1e-3));

      // At end (4s): fade = 0.0 -> effective volume = 0.0
      expect(track.getVolumeAt(4.0), equals(0.0));
    });
  });

  group('EditorViewModel Motion Graph & Keyframe Management Tests', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();
      viewModel.initForTesting();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Add, check, and remove keyframe on selected video clip', () {
      viewModel.selectClip(0);
      expect(viewModel.keyframeCountForSelected, equals(0));

      // Seek to 1.5s and add keyframe
      viewModel.seekTo(1.5);
      viewModel.addKeyframeAtPlayhead();

      expect(viewModel.hasKeyframeAtPlayhead, isTrue);
      expect(viewModel.keyframeCountForSelected, greaterThan(0));

      // Remove keyframe
      viewModel.removeKeyframeAtPlayhead();
      expect(viewModel.hasKeyframeAtPlayhead, isFalse);
      expect(viewModel.keyframeCountForSelected, equals(0));
    });

    test('updateKeyframeValue modifies property at exact timestamp', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();

      final clipId = viewModel.videoClips[0].id;
      final kf = viewModel.videoClips[0].effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first;

      viewModel.updateKeyframeValue(
        layerId: clipId,
        property: AnimatableProperty.scale,
        keyframeId: kf.id,
        newValue: 2.5,
      );

      final updatedClip = viewModel.videoClips[0];
      final updatedTrack = updatedClip.effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!;
      expect(updatedTrack.keyframes.first.value, equals(2.5));
    });

    test('changeKeyframeEasing modifies curve for interpolation segment', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();

      final clipId = viewModel.videoClips[0].id;
      final kf = viewModel.videoClips[0].effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first;

      viewModel.changeKeyframeEasing(
        layerId: clipId,
        property: AnimatableProperty.scale,
        keyframeId: kf.id,
        easing: EasingCurve.easeIn,
      );

      final updatedClip = viewModel.videoClips[0];
      final updatedKf = updatedClip.effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first;
      expect(updatedKf.easing.mode, equals(InterpolationMode.easeIn));
    });

    test('moveKeyframe re-times keyframe without duplicating', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();

      final clipId = viewModel.videoClips[0].id;
      final kf = viewModel.videoClips[0].effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first;

      viewModel.moveKeyframe(
        layerId: clipId,
        property: AnimatableProperty.scale,
        keyframeId: kf.id,
        newTimestampMs: 2500,
      );

      final updatedClip = viewModel.videoClips[0];
      final updatedKf = updatedClip.effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first;
      expect(updatedKf.timestampMs, equals(2500));
    });

    test('resetKeyframeAnimation clears all motion tracks for layer', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(2.0);
      viewModel.addKeyframeAtPlayhead();
      expect(viewModel.keyframeCountForSelected, greaterThan(0));

      final clipId = viewModel.videoClips[0].id;
      viewModel.resetKeyframeAnimation(clipId);

      expect(viewModel.keyframeCountForSelected, equals(0));
      expect(viewModel.videoClips[0].effectiveKeyframeTracks.tracks, isEmpty);
    });

    test('Undo and redo restore keyframe tracks deterministically', () {
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      expect(viewModel.keyframeCountForSelected, greaterThan(0));

      // Undo
      viewModel.undo();
      expect(viewModel.keyframeCountForSelected, equals(0));

      // Redo
      viewModel.redo();
      expect(viewModel.keyframeCountForSelected, greaterThan(0));
      expect(viewModel.hasKeyframeAtPlayhead, isTrue);
    });

    test('splitClipAtPlayhead splits keyframe tracks into both clip halves', () {
      final initialCount = viewModel.videoClips.length;
      viewModel.selectClip(0);
      viewModel.seekTo(1.0);
      viewModel.addKeyframeAtPlayhead();
      viewModel.seekTo(4.0);
      viewModel.addKeyframeAtPlayhead();

      // Split at 2.5s
      viewModel.seekTo(2.5);
      viewModel.splitClipAtPlayhead();

      expect(viewModel.videoClips.length, equals(initialCount + 1));
      final firstHalf = viewModel.videoClips[0];
      final secondHalf = viewModel.videoClips[1];

      // Both halves must retain valid keyframe tracks
      expect(firstHalf.effectiveKeyframeTracks.tracks, isNotEmpty);
      expect(secondHalf.effectiveKeyframeTracks.tracks, isNotEmpty);
    });

    test('duplicateSelectedClip creates independent deep copy of keyframes', () {
      final initialCount = viewModel.videoClips.length;
      viewModel.selectClip(0);
      viewModel.seekTo(1.5);
      viewModel.addKeyframeAtPlayhead();

      final origCount = viewModel.videoClips[0].effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.length;
      expect(origCount, greaterThan(0));

      viewModel.duplicateSelectedClip();
      expect(viewModel.videoClips.length, equals(initialCount + 1));

      final duplicatedClip = viewModel.videoClips[1];
      final dupKeyframes = duplicatedClip.effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes;
      expect(dupKeyframes.length, equals(origCount));
      expect(dupKeyframes.first.id, isNot(equals(viewModel.videoClips[0].effectiveKeyframeTracks.tracks[AnimatableProperty.scale]!.keyframes.first.id)));
    });

    test('updateEasingForTransformProperties synchronizes scale, pos, rot, opacity smoothly', () {
      var group = const KeyframeTrackGroup().addTransformKeyframe(
        timeMs: 1000,
        posX: 10.0,
        posY: 20.0,
        scale: 1.5,
        rotation: 45.0,
        opacity: 0.8,
        easing: EasingCurve.linear,
      );

      // Verify all tracks initially have linear easing
      for (final prop in const [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
      ]) {
        expect(group.tracks[prop]!.getKeyframeAt(1000)!.easing.mode, equals(InterpolationMode.linear));
      }

      // Sync easeInOut curve across all transforms
      group = group.updateEasingForTransformProperties(1000, EasingCurve.easeInOut);

      for (final prop in const [
        AnimatableProperty.scale,
        AnimatableProperty.positionX,
        AnimatableProperty.positionY,
        AnimatableProperty.rotation,
        AnimatableProperty.opacity,
      ]) {
        expect(group.tracks[prop]!.getKeyframeAt(1000)!.easing.mode, equals(InterpolationMode.easeInOut));
      }
    });

    test('getKeyframeAtOrBefore correctly resolves segment-governing keyframe', () {
      var track = const KeyframeTrack(property: AnimatableProperty.scale);
      track = track.addOrUpdate(1000, 1.0);
      track = track.addOrUpdate(3000, 2.0);

      // Direct match
      expect(track.getKeyframeAtOrBefore(1000)!.timestampMs, equals(1000));
      // In-between at 2.0s -> resolves to preceding keyframe at 1.0s
      expect(track.getKeyframeAtOrBefore(2000)!.timestampMs, equals(1000));
      // In-between at 3.5s -> resolves to preceding keyframe at 3.0s
      expect(track.getKeyframeAtOrBefore(3500)!.timestampMs, equals(3000));
    });

    test('Cubic Bezier bisection fallback converges on flat and steep tangents', () {
      // Steep curve
      const steepCurve = EasingCurve(
        mode: InterpolationMode.cubicBezier,
        x1: 0.0,
        y1: 1.0,
        x2: 0.0,
        y2: 1.0,
      );
      expect(steepCurve.solve(0.0), closeTo(0.0, 1e-4));
      expect(steepCurve.solve(0.5), isA<double>());
      expect(steepCurve.solve(1.0), closeTo(1.0, 1e-4));

      // Overshoot curve (anticipation / bounce)
      const overshootCurve = EasingCurve(
        mode: InterpolationMode.cubicBezier,
        x1: 0.68,
        y1: -0.55,
        x2: 0.265,
        y2: 1.55,
      );
      // At t=0.1, it should overshoot negatively below 0.0
      expect(overshootCurve.solve(0.1), lessThan(0.0));
      // At t=0.9, it should overshoot positively above 1.0
      expect(overshootCurve.solve(0.9), greaterThan(1.0));
    });
  });
}
