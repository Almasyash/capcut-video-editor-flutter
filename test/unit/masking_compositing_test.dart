import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

VideoClip createTestClip({
  String id = 'test_clip',
  String assetId = 'asset_1',
  String title = 'Test Clip',
  Duration duration = const Duration(seconds: 10),
  List<VideoMask> masks = const [],
}) {
  return VideoClip(
    id: id,
    assetId: assetId,
    title: title,
    originalDuration: duration,
    trimStart: Duration.zero,
    trimEnd: duration,
    previewGradient: const [Colors.blue, Colors.purple],
    masks: masks,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoMask Domain Model Tests', () {
    test('Default VideoMask initializes with correct presets and bounds', () {
      const mask = VideoMask(id: 'm1', name: 'Mask 1');

      expect(mask.id, 'm1');
      expect(mask.name, 'Mask 1');
      expect(mask.type, MaskType.none);
      expect(mask.enabled, isTrue);
      expect(mask.inverted, isFalse);
      expect(mask.opacity, 1.0);
      expect(mask.feather, 0.0);
      expect(mask.expansion, 0.0);
      expect(mask.positionX, 0.0);
      expect(mask.positionY, 0.0);
      expect(mask.scale, 1.0);
      expect(mask.rotation, 0.0);
      expect(mask.width, 0.5);
      expect(mask.height, 0.5);
      expect(mask.combineMode, MaskCombineMode.add);
      expect(mask.isActive, isFalse);
    });

    test('VideoMask types generate appropriate geometries', () {
      final rect = VideoMask(type: MaskType.rectangle, name: MaskType.rectangle.displayName);
      expect(rect.type, MaskType.rectangle);

      final ellipse = VideoMask(type: MaskType.ellipse, name: MaskType.ellipse.displayName);
      expect(ellipse.type, MaskType.ellipse);

      final linear = VideoMask(type: MaskType.linear, name: MaskType.linear.displayName);
      expect(linear.type, MaskType.linear);

      final radial = VideoMask(type: MaskType.radial, name: MaskType.radial.displayName);
      expect(radial.type, MaskType.radial);

      final polygon = VideoMask(
        type: MaskType.polygon,
        name: MaskType.polygon.displayName,
        points: const [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.5, 0.8)],
      );
      expect(polygon.type, MaskType.polygon);
      expect(polygon.points.length, 3);

      final star = VideoMask(type: MaskType.star, name: MaskType.star.displayName);
      expect(star.type, MaskType.star);

      final heart = VideoMask(type: MaskType.heart, name: MaskType.heart.displayName);
      expect(heart.type, MaskType.heart);
    });

    test('VideoMask toPath generates non-empty paths for all geometries', () {
      const canvasSize = Size(1920, 1080);

      for (final type in MaskType.values) {
        if (type == MaskType.none) continue;
        final mask = VideoMask(
          type: type,
          points: type == MaskType.polygon
              ? const [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.5, 0.8)]
              : const [],
        );
        final path = mask.toPath(canvasSize);

        expect(path, isNotNull);
        final bounds = path.getBounds();
        expect(bounds.width, greaterThan(0.0));
        expect(bounds.height, greaterThan(0.0));
      }
    });

    test('VideoMask toPath handles expansion and rotation properly', () {
      const canvasSize = Size(1000, 1000);
      const baseMask = VideoMask(
        id: 'rect',
        type: MaskType.rectangle,
        width: 0.5,
        height: 0.5,
        positionX: 0.5,
        positionY: 0.5,
      );

      final basePath = baseMask.toPath(canvasSize);
      final baseBounds = basePath.getBounds();

      final expandedMask = baseMask.copyWith(expansion: 0.2);
      final expandedPath = expandedMask.toPath(canvasSize);
      final expandedBounds = expandedPath.getBounds();

      expect(expandedBounds.width, greaterThan(baseBounds.width));
      expect(expandedBounds.height, greaterThan(baseBounds.height));

      final rotatedMask = baseMask.copyWith(rotation: 45.0);
      final rotatedPath = rotatedMask.toPath(canvasSize);
      final rotatedBounds = rotatedPath.getBounds();

      expect(rotatedBounds.width, greaterThan(baseBounds.width));
    });

    test('VideoMask evaluateAt evaluates keyframed properties deterministically', () {
      const trackGroup = KeyframeTrackGroup(
        tracks: {
          AnimatableProperty.maskPositionX: KeyframeTrack(
            property: AnimatableProperty.maskPositionX,
            defaultValue: 0.2,
            keyframes: [
              MotionKeyframe(id: 'k1', timestampMs: 0, value: 0.2),
              MotionKeyframe(id: 'k2', timestampMs: 1000, value: 0.8),
            ],
          ),
          AnimatableProperty.maskScale: KeyframeTrack(
            property: AnimatableProperty.maskScale,
            defaultValue: 1.0,
            keyframes: [
              MotionKeyframe(id: 'k3', timestampMs: 0, value: 1.0),
              MotionKeyframe(id: 'k4', timestampMs: 1000, value: 2.0),
            ],
          ),
        },
      );

      const mask = VideoMask(
        id: 'kMask',
        positionX: 0.2,
        scale: 1.0,
        keyframeTracks: trackGroup,
      );

      final at0 = mask.evaluateAt(0.0);
      expect(at0.positionX, closeTo(0.2, 0.01));
      expect(at0.scale, closeTo(1.0, 0.01));

      final atMid = mask.evaluateAt(0.5);
      expect(atMid.positionX, closeTo(0.5, 0.05));
      expect(atMid.scale, closeTo(1.5, 0.05));

      final at1 = mask.evaluateAt(1.0);
      expect(at1.positionX, closeTo(0.8, 0.01));
      expect(at1.scale, closeTo(2.0, 0.01));
    });

    test('VideoMask serialization and deserialization roundtrip preserves all fields', () {
      const original = VideoMask(
        id: 'test_mask_1',
        name: 'Vignette Ellipse',
        type: MaskType.ellipse,
        enabled: true,
        inverted: true,
        opacity: 0.85,
        feather: 0.4,
        expansion: 0.1,
        positionX: 0.6,
        positionY: 0.4,
        scale: 1.25,
        rotation: 30.0,
        width: 0.7,
        height: 0.5,
        cornerRadius: 0.15,
        combineMode: MaskCombineMode.intersect,
      );

      final json = original.toJson();
      final restored = VideoMask.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.enabled, original.enabled);
      expect(restored.inverted, original.inverted);
      expect(restored.opacity, closeTo(0.85, 0.001));
      expect(restored.feather, closeTo(0.4, 0.001));
      expect(restored.expansion, closeTo(0.1, 0.001));
      expect(restored.positionX, closeTo(0.6, 0.001));
      expect(restored.positionY, closeTo(0.4, 0.001));
      expect(restored.scale, closeTo(1.25, 0.001));
      expect(restored.rotation, closeTo(30.0, 0.001));
      expect(restored.width, closeTo(0.7, 0.001));
      expect(restored.height, closeTo(0.5, 0.001));
      expect(restored.cornerRadius, closeTo(0.15, 0.001));
      expect(restored.combineMode, MaskCombineMode.intersect);
    });

    test('VideoMask fromJson handles legacy and edge case formats smoothly', () {
      final legacyJson = {
        'type': 'rectangle',
        'feather': 0.5,
      };

      final mask = VideoMask.fromJson(legacyJson);
      expect(mask.type, MaskType.rectangle);
      expect(mask.feather, 0.5);
      expect(mask.enabled, isTrue);
      expect(mask.inverted, isFalse);
      expect(mask.combineMode, MaskCombineMode.add);
    });
  });

  group('VideoClip and OverlayClip Multi-Mask Integration Tests', () {
    test('VideoClip backwards compatibility: mask getter returns first mask', () {
      const m1 = VideoMask(id: 'm1', name: 'Mask 1');
      const m2 = VideoMask(id: 'm2', name: 'Mask 2');

      final clip = createTestClip(
        id: 'c1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
        masks: [m1, m2],
      );

      expect(clip.masks.length, 2);
      expect(clip.mask?.id, 'm1');
    });

    test('VideoClip copyWith supports single mask parameter for backward compatibility', () {
      final clip = createTestClip(
        id: 'c1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
      );

      final updated = clip.copyWith(
        mask: const VideoMask(id: 'new_m', name: 'New Mask'),
      );

      expect(updated.masks.length, 1);
      expect(updated.mask?.id, 'new_m');

      final cleared = updated.copyWith(clearMask: true);
      expect(cleared.masks, isEmpty);
      expect(cleared.mask, isNull);
    });

    test('OverlayClip backwards compatibility and multi-mask support', () {
      const m1 = VideoMask(id: 'pip_m1', name: 'PIP Mask 1');
      const m2 = VideoMask(id: 'pip_m2', name: 'PIP Mask 2');

      const overlay = OverlayClip(
        id: 'ov1',
        title: 'PIP 1',
        startTime: Duration.zero,
        duration: Duration(seconds: 4),
        masks: [m1, m2],
      );

      expect(overlay.masks.length, 2);
      expect(overlay.mask?.id, 'pip_m1');

      final updated = overlay.copyWith(
        mask: const VideoMask(id: 'pip_single', name: 'Single'),
      );
      expect(updated.masks.length, 1);
      expect(updated.mask?.id, 'pip_single');
    });

    test('VideoClip and OverlayClip json serialization handles masks list correctly', () {
      const m = VideoMask(id: 'm_json', name: 'JSON Mask');
      final clip = createTestClip(
        id: 'c_json',
        title: 'JSON Clip',
        duration: const Duration(seconds: 3),
        masks: [m],
      );

      final json = clip.toJson();
      expect(json['masks'], isNotNull);
      expect((json['masks'] as List).length, 1);

      final restored = VideoClip.fromJson(json);
      expect(restored.masks.length, 1);
      expect(restored.masks.first.id, 'm_json');
    });
  });

  group('EditorViewModel Masking & Compositing Workflow Tests', () {
    test('Adding, updating, duplicating, reordering, and removing masks on selected clip', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'test_clip',
        title: 'Main Track Clip',
        duration: const Duration(seconds: 10),
      ));
      vm.selectClip(0);

      // 1. Add mask
      vm.addMaskToSelectedClip(const VideoMask(id: 'm1', name: 'Rect Mask', type: MaskType.rectangle));
      expect(vm.selectedClip?.masks.length, 1);
      expect(vm.selectedClip?.masks.first.type, MaskType.rectangle);

      // 2. Add second mask
      vm.addMaskToSelectedClip(const VideoMask(id: 'm2', name: 'Ellipse Mask', type: MaskType.ellipse));
      expect(vm.selectedClip?.masks.length, 2);
      expect(vm.selectedClip?.masks[1].type, MaskType.ellipse);

      // 3. Update second mask
      final secondMask = vm.selectedClip!.masks[1];
      vm.updateMaskInSelectedClip(1, secondMask.copyWith(feather: 0.75, inverted: true));
      expect(vm.selectedClip?.masks[1].feather, 0.75);
      expect(vm.selectedClip?.masks[1].inverted, isTrue);

      // 4. Duplicate mask
      vm.duplicateMaskInSelectedClip(1);
      expect(vm.selectedClip?.masks.length, 3);
      expect(vm.selectedClip?.masks.last.name, contains('Copy'));

      // 5. Reorder masks
      vm.reorderMasksInSelectedClip(0, 2);
      expect(vm.selectedClip?.masks.length, 3);

      // 6. Remove mask
      vm.removeMaskFromSelectedClip(1);
      expect(vm.selectedClip?.masks.length, 2);

      // 7. Remove all masks
      vm.removeClipMask();
      expect(vm.selectedClip?.masks, isEmpty);
    });

    test('PIP Overlay masking methods in EditorViewModel', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'base_clip',
        title: 'Base',
        duration: const Duration(seconds: 10),
      ));

      vm.addOverlayClip(const OverlayClip(
        id: 'pip_1',
        title: 'Overlay',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
      ));
      vm.selectOverlay(0);

      // 1. Add mask to overlay
      vm.addMaskToSelectedOverlay(const VideoMask(id: 'ov_m1', name: 'Circle Mask', type: MaskType.circle));
      expect(vm.selectedOverlay?.masks.length, 1);
      expect(vm.selectedOverlay?.masks.first.type, MaskType.circle);

      // 2. Update mask in overlay
      final m = vm.selectedOverlay!.masks.first;
      vm.updateMaskInSelectedOverlay(0, m.copyWith(opacity: 0.6));
      expect(vm.selectedOverlay?.masks.first.opacity, closeTo(0.6, 0.01));

      // 3. Duplicate overlay mask
      vm.duplicateMaskInSelectedOverlay(0);
      expect(vm.selectedOverlay?.masks.length, 2);

      // 4. Remove overlay mask
      vm.removeMaskFromSelectedOverlay(0);
      expect(vm.selectedOverlay?.masks.length, 1);
    });

    test('addMaskKeyframeAtPlayhead records keyframes for active mask', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'clip_kf',
        title: 'KF Clip',
        duration: const Duration(seconds: 10),
      ));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'kf_mask', name: 'Mask KF', type: MaskType.rectangle));

      vm.seekTo(2.0);

      vm.addMaskKeyframeAtPlayhead();

      final updatedClip = vm.selectedClip!;
      expect(updatedClip.keyframeTracks, isNotNull);
      expect(updatedClip.keyframeTracks!.tracks.containsKey(AnimatableProperty.maskPositionX), isTrue);
      expect(updatedClip.keyframeTracks!.tracks.containsKey(AnimatableProperty.maskScale), isTrue);
    });

    test('Undo and redo properly roll back and reapply mask modifications', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'undo_clip',
        title: 'Undo Clip',
        duration: const Duration(seconds: 10),
      ));
      vm.selectClip(0);

      expect(vm.selectedClip?.masks, isEmpty);

      vm.addMaskToSelectedClip(const VideoMask(id: 'm_undo', name: 'Undo Mask', type: MaskType.rectangle));
      expect(vm.selectedClip?.masks.length, 1);

      // Undo add mask
      vm.undo();
      expect(vm.selectedClip?.masks, isEmpty);

      // Redo add mask
      vm.redo();
      expect(vm.selectedClip?.masks.length, 1);
      expect(vm.selectedClip?.masks.first.type, MaskType.rectangle);
    });
  });

  group('Advanced Masking & Compositing v1.6.0 Engine Tests', () {
    test('Polygon geometry fallback and point updates', () {
      // Empty points falls back to default hexagon points
      const emptyPoly = VideoMask(
        id: 'p_empty',
        type: MaskType.polygon,
        points: [],
      );
      final path = emptyPoly.toPath(const Size(1920, 1080));
      expect(path, isNotNull);
      expect(path.getBounds().isEmpty, isFalse);

      // Custom polygon with 4 points
      const customPoly = VideoMask(
        id: 'p_custom',
        type: MaskType.polygon,
        points: [
          Offset(-0.3, -0.3),
          Offset(0.3, -0.3),
          Offset(0.3, 0.3),
          Offset(-0.3, 0.3),
        ],
      );
      expect(customPoly.points.length, 4);
      final customPath = customPoly.toPath(const Size(1000, 1000));
      final bounds = customPath.getBounds();
      expect(bounds.width, closeTo(600, 10));
      expect(bounds.height, closeTo(600, 10));
    });

    test('Linear and Radial masks generate correct geometric bounds', () {
      const linear = VideoMask(
        id: 'lin1',
        type: MaskType.linear,
        linearStart: Offset(0.0, -0.3),
        linearEnd: Offset(0.0, 0.3),
      );
      final linPath = linear.toPath(const Size(1000, 1000));
      expect(linPath, isNotNull);
      expect(linPath.getBounds().isEmpty, isFalse);

      const radial = VideoMask(
        id: 'rad1',
        type: MaskType.radial,
        radialCenter: Offset(0.0, 0.0),
        radialRadius: 0.25,
      );
      final radPath = radial.toPath(const Size(1000, 1000));
      final radBounds = radPath.getBounds();
      expect(radBounds.width, closeTo(500, 20));
      expect(radBounds.height, closeTo(500, 20));
    });

    test('Safe getters handle NaN and Infinity without crashing', () {
      const nanMask = VideoMask(
        id: 'nan1',
        positionX: double.nan,
        positionY: double.infinity,
        scale: double.negativeInfinity,
        rotation: double.nan,
        opacity: double.nan,
        feather: double.infinity,
        expansion: double.nan,
        width: double.nan,
        height: double.infinity,
      );

      expect(nanMask.safePositionX, 0.0);
      expect(nanMask.safePositionY, 0.0);
      expect(nanMask.safeScale, 1.0);
      expect(nanMask.safeRotation, 0.0);
      expect(nanMask.safeOpacity, 1.0);
      expect(nanMask.safeFeather, 0.0);
      expect(nanMask.safeExpansion, 0.0);
      expect(nanMask.safeWidth, 0.5);
      expect(nanMask.safeHeight, 0.5);
    });

    test('Dual-track keyframe resolution: evaluates clip keyframes when mask tracks are null', () {
      const clipTracks = KeyframeTrackGroup(
        tracks: {
          AnimatableProperty.maskPositionX: KeyframeTrack(
            property: AnimatableProperty.maskPositionX,
            defaultValue: 0.0,
            keyframes: [
              MotionKeyframe(id: 'k1', timestampMs: 0, value: -0.5),
              MotionKeyframe(id: 'k2', timestampMs: 2000, value: 0.5),
            ],
          ),
        },
      );

      const maskWithoutTracks = VideoMask(
        id: 'no_tracks',
        positionX: 0.0,
        keyframeTracks: null,
      );

      final evaluated = maskWithoutTracks.evaluateAt(1.0, externalTracks: clipTracks);
      expect(evaluated.positionX, closeTo(0.0, 0.05));

      final evaluatedAtEnd = maskWithoutTracks.evaluateAt(2.0, externalTracks: clipTracks);
      expect(evaluatedAtEnd.positionX, closeTo(0.5, 0.05));
    });

    test('Gesture coalescing: commitMaskGesture creates exactly one undo point', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'gesture_clip',
        title: 'Gesture Clip',
        duration: const Duration(seconds: 10),
      ));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'g_mask', name: 'Gesture Mask', type: MaskType.rectangle));

      vm.setMaskModeActive(true);
      expect(vm.isMaskModeActive, isTrue);

      // Continuous drag updates mask property without creating undo steps
      vm.updateActiveMask(vm.activeMask!.copyWith(positionX: 0.1));
      vm.updateActiveMask(vm.activeMask!.copyWith(positionX: 0.2));
      vm.updateActiveMask(vm.activeMask!.copyWith(positionX: 0.3));
      vm.updateActiveMask(vm.activeMask!.copyWith(positionX: 0.4));

      // Commit gesture at drag end
      vm.commitMaskGesture();

      expect(vm.activeMask?.positionX, closeTo(0.4, 0.001));

      // Single undo should revert the entire drag back to initial state
      vm.undo();
      expect(vm.activeMask?.positionX, closeTo(0.0, 0.001));

      // Redo restores to end of drag
      vm.redo();
      expect(vm.activeMask?.positionX, closeTo(0.4, 0.001));
    });

    test('updateMaskPolygonPoint correctly modifies specific vertex', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(
        id: 'poly_clip',
        title: 'Poly Clip',
        duration: const Duration(seconds: 10),
      ));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(
        id: 'p_mask',
        name: 'Poly Mask',
        type: MaskType.polygon,
        points: [
          Offset(0.0, -0.4),
          Offset(0.35, -0.2),
          Offset(0.35, 0.2),
        ],
      ));

      vm.updateMaskPolygonPoint(0, 1, const Offset(0.5, -0.3));
      expect(vm.selectedClip?.masks.first.points[1], const Offset(0.5, -0.3));
    });

    test('Clip split preserves masks and keyframes on both resulting clips', () {
      final vm = EditorViewModel();
      final initialCount = vm.videoClips.length;
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'split_mask', name: 'Mask', type: MaskType.rectangle, positionX: 0.25));
      vm.seekTo(2.0);

      vm.splitClipAtPlayhead();

      expect(vm.videoClips.length, initialCount + 1);
      expect(vm.videoClips[0].masks.length, 1);
      expect(vm.videoClips[0].masks.first.positionX, 0.25);
      expect(vm.videoClips[1].masks.length, 1);
      expect(vm.videoClips[1].masks.first.positionX, 0.25);
    });

    test('v1.7.0: Mask renaming updates mask label and supports undo/redo on clips and overlays', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_rename', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'm_orig', name: 'Mask 1', type: MaskType.rectangle));

      expect(vm.selectedClip?.masks.first.name, 'Mask 1');

      vm.renameMaskInSelectedClip(0, 'Face Mask');
      expect(vm.selectedClip?.masks.first.name, 'Face Mask');

      vm.undo();
      expect(vm.selectedClip?.masks.first.name, 'Mask 1');

      vm.redo();
      expect(vm.selectedClip?.masks.first.name, 'Face Mask');

      // Test Overlay
      const overlay = OverlayClip(
        id: 'ov_rename',
        title: 'Overlay',
        startTime: Duration.zero,
        duration: Duration(seconds: 5),
        masks: [VideoMask(id: 'ov_m1', name: 'Overlay Mask 1', type: MaskType.ellipse)],
      );
      vm.addOverlayClip(overlay);
      vm.selectOverlay(vm.overlayClips.length - 1);

      vm.renameMaskInSelectedOverlay(0, 'PIP Vignette');
      expect(vm.selectedOverlay?.masks.first.name, 'PIP Vignette');

      vm.undo();
      expect(vm.selectedOverlay?.masks.first.name, 'Overlay Mask 1');
    });

    test('v1.7.0: Mask enable/bypass toggle updates enabled and isActive with undo/redo', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_toggle', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'm_tog', name: 'Mask', type: MaskType.rectangle, enabled: true));

      expect(vm.selectedClip?.masks.first.enabled, isTrue);
      expect(vm.selectedClip?.masks.first.isActive, isTrue);

      vm.toggleMaskEnabledInSelectedClip(0);
      expect(vm.selectedClip?.masks.first.enabled, isFalse);
      expect(vm.selectedClip?.masks.first.isActive, isFalse);

      vm.undo();
      expect(vm.selectedClip?.masks.first.enabled, isTrue);
      expect(vm.selectedClip?.masks.first.isActive, isTrue);

      vm.redo();
      expect(vm.selectedClip?.masks.first.enabled, isFalse);
    });

    test('v1.7.0: Mask reordering alters evaluation sequence with undo/redo', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_reorder', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'm1', name: 'First', type: MaskType.rectangle));
      vm.addMaskToSelectedClip(const VideoMask(id: 'm2', name: 'Second', type: MaskType.ellipse));

      expect(vm.selectedClip?.masks[0].name, 'First');
      expect(vm.selectedClip?.masks[1].name, 'Second');

      vm.reorderMasksInSelectedClip(0, 1);
      expect(vm.selectedClip?.masks[0].name, 'Second');
      expect(vm.selectedClip?.masks[1].name, 'First');

      vm.undo();
      expect(vm.selectedClip?.masks[0].name, 'First');
      expect(vm.selectedClip?.masks[1].name, 'Second');

      vm.redo();
      expect(vm.selectedClip?.masks[0].name, 'Second');
      expect(vm.selectedClip?.masks[1].name, 'First');
    });

    test('v1.7.0: Discrete mask update records undo snapshot for non-drag edits', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_disc', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);
      vm.addMaskToSelectedClip(const VideoMask(id: 'm_disc', name: 'Mask', type: MaskType.rectangle, inverted: false));

      final updated = vm.selectedClip!.masks.first.copyWith(inverted: true, combineMode: MaskCombineMode.subtract);
      vm.updateMaskDiscreteInSelectedClip(0, updated);

      expect(vm.selectedClip?.masks.first.inverted, isTrue);
      expect(vm.selectedClip?.masks.first.combineMode, MaskCombineMode.subtract);

      vm.undo();
      expect(vm.selectedClip?.masks.first.inverted, isFalse);
      expect(vm.selectedClip?.masks.first.combineMode, MaskCombineMode.add);
    });

    test('v1.7.0: Split clip splits individual mask keyframe tracks proportionally', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_split_kf', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);

      var maskTracks = const KeyframeTrackGroup();
      maskTracks = maskTracks.addKeyframe(AnimatableProperty.maskFeather, 0, 10.0);
      maskTracks = maskTracks.addKeyframe(AnimatableProperty.maskFeather, 2000, 20.0);
      maskTracks = maskTracks.addKeyframe(AnimatableProperty.maskFeather, 4000, 40.0);

      final maskWithTracks = VideoMask(
        id: 'm_kf_split',
        name: 'Animated Mask',
        type: MaskType.rectangle,
        keyframeTracks: maskTracks,
      );
      vm.addMaskToSelectedClip(maskWithTracks);

      // Seek to 2.0s and split
      vm.seekTo(2.0);
      final splitOk = vm.splitClipAtPlayhead();
      expect(splitOk, isTrue);

      final part1 = vm.videoClips[0];
      final part2 = vm.videoClips[1];

      expect(part1.masks.length, 1);
      expect(part2.masks.length, 1);

      // Part 1 mask should have keyframes up to 2000ms
      final p1Track = part1.masks.first.keyframeTracks?.tracks[AnimatableProperty.maskFeather];
      expect(p1Track, isNotNull);
      expect(p1Track!.keyframes.length, 2);
      expect(p1Track.keyframes.last.value, 20.0);

      // Part 2 mask should have keyframes shifted starting from 0ms
      final p2Track = part2.masks.first.keyframeTracks?.tracks[AnimatableProperty.maskFeather];
      expect(p2Track, isNotNull);
      expect(p2Track!.keyframes.first.timestampMs, 0);
      expect(p2Track.keyframes.first.value, 20.0);
      expect(p2Track.keyframes.last.timestampMs, 2000); // 4000 - 2000
      expect(p2Track.keyframes.last.value, 40.0);
    });

    test('v1.7.0: Clip duplicate deeply clones masks with unique IDs and cloned keyframes', () {
      final vm = EditorViewModel();
      vm.addClip(createTestClip(id: 'clip_dup_mask', title: 'Clip', duration: const Duration(seconds: 10)));
      vm.selectClip(0);

      var maskTracks = const KeyframeTrackGroup();
      maskTracks = maskTracks.addKeyframe(AnimatableProperty.maskScale, 0, 1.0);
      maskTracks = maskTracks.addKeyframe(AnimatableProperty.maskScale, 1000, 2.0);

      vm.addMaskToSelectedClip(VideoMask(
        id: 'original_mask_id',
        name: 'Original Mask',
        type: MaskType.ellipse,
        keyframeTracks: maskTracks,
      ));

      final initialCount = vm.videoClips.length;
      vm.duplicateSelectedClip();

      expect(vm.videoClips.length, initialCount + 1);
      final origClip = vm.videoClips[0];
      final dupClip = vm.videoClips[1];

      expect(dupClip.masks.length, 1);
      expect(dupClip.masks.first.id, isNot(equals(origClip.masks.first.id)));
      expect(dupClip.masks.first.type, MaskType.ellipse);
      expect(dupClip.masks.first.keyframeTracks?.tracks[AnimatableProperty.maskScale]?.keyframes.length, 2);
    });
  });
}
