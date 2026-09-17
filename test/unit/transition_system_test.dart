import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/services/transition_registry.dart';
import 'package:capcut_video_editor/domain/services/transition_validator.dart';
import 'package:capcut_video_editor/core/rendering/transition_shader_manager.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8 — Transition Registry & Metadata Tests', () {
    test('TransitionRegistry contains all 18 TransitionType values', () {
      final allDefs = TransitionRegistry.allDefinitions;
      expect(allDefs.length, 19); // 1 none + 18 transition definitions

      for (final type in TransitionType.values) {
        final def = TransitionRegistry.getByType(type);
        expect(def.type, type);
        expect(def.name.isNotEmpty, isTrue);
        expect(def.minDuration, 0.1);
        expect(def.maxDuration, 3.0);
        expect(def.defaultDuration, 0.5);

        if (type != TransitionType.none) {
          expect(def.shaderPath, isNotNull);
          expect(def.shaderPath!.endsWith('.frag'), isTrue);
        }
      }
    });

    test('Transition categories are properly assigned', () {
      expect(TransitionType.fade.category, TransitionCategory.basic);
      expect(TransitionType.dissolve.category, TransitionCategory.basic);
      expect(TransitionType.blackFade.category, TransitionCategory.basic);
      expect(TransitionType.whiteFade.category, TransitionCategory.basic);

      expect(TransitionType.wipeLeft.category, TransitionCategory.wipe);
      expect(TransitionType.wipeRight.category, TransitionCategory.wipe);
      expect(TransitionType.wipeUp.category, TransitionCategory.wipe);
      expect(TransitionType.wipeDown.category, TransitionCategory.wipe);

      expect(TransitionType.slideLeft.category, TransitionCategory.slide);
      expect(TransitionType.slideRight.category, TransitionCategory.slide);
      expect(TransitionType.slideUp.category, TransitionCategory.slide);
      expect(TransitionType.slideDown.category, TransitionCategory.slide);

      expect(TransitionType.zoomIn.category, TransitionCategory.zoom);
      expect(TransitionType.zoomOut.category, TransitionCategory.zoom);

      expect(TransitionType.circle.category, TransitionCategory.shape);
      expect(TransitionType.radial.category, TransitionCategory.shape);

      expect(TransitionType.blur.category, TransitionCategory.blur);
      expect(TransitionType.pixelate.category, TransitionCategory.creative);
    });

    test('TransitionRegistry lookups work by category and ID', () {
      final wipeDefs = TransitionRegistry.getByCategory(TransitionCategory.wipe);
      expect(wipeDefs.length, 4);

      final slideDefs = TransitionRegistry.getByCategory(TransitionCategory.slide);
      expect(slideDefs.length, 4);

      final shapeDefs = TransitionRegistry.getByCategory(TransitionCategory.shape);
      expect(shapeDefs.length, 2);

      final circleDef = TransitionRegistry.getById('circle');
      expect(circleDef, isNotNull);
      expect(circleDef!.type, TransitionType.circle);

      final pixelateDef = TransitionRegistry.getById('pixelate');
      expect(pixelateDef, isNotNull);
      expect(pixelateDef!.type, TransitionType.pixelate);
    });
  });

  group('Phase 8 — Transition Model & Validation Tests', () {
    test('Transition model JSON serialization roundtrip', () {
      final transition = Transition(
        id: 'trans_circle_1',
        type: TransitionType.circle,
        duration: 1.2,
        leftClipId: 'clip_1',
        rightClipId: 'clip_2',
        enabled: true,
      );

      final json = transition.toJson();
      expect(json['id'], 'trans_circle_1');
      expect(json['type'], 'circle');
      expect(json['duration'], 1.2);
      expect(json['leftClipId'], 'clip_1');
      expect(json['rightClipId'], 'clip_2');

      final reconstructed = Transition.fromJson(json);
      expect(reconstructed.id, transition.id);
      expect(reconstructed.type, TransitionType.circle);
      expect(reconstructed.duration, 1.2);
      expect(reconstructed.leftClipId, 'clip_1');
      expect(reconstructed.rightClipId, 'clip_2');
      expect(reconstructed.enabled, true);
    });

    test('TransitionValidator validates duration bounds and adjacency', () {
      const clip1 = VideoClip(
        id: 'clip_1',
        assetId: 'asset_1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        previewGradient: [Colors.blue, Colors.green],
      );
      const clip2 = VideoClip(
        id: 'clip_2',
        assetId: 'asset_2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.purple, Colors.pink],
      );
      const clip3 = VideoClip(
        id: 'clip_3',
        assetId: 'asset_3',
        title: 'Clip 3',
        originalDuration: Duration(seconds: 3),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 3),
        previewGradient: [Colors.orange, Colors.red],
      );

      final project = Project(
        id: 'test_project',
        name: 'Validation Project',
        videoClips: [clip1, clip2, clip3],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final validator = TransitionValidator(project);

      // 1. Valid transition
      final valid = Transition(
        type: TransitionType.wipeUp,
        duration: 0.8,
        leftClipId: 'clip_1',
        rightClipId: 'clip_2',
      );
      expect(validator.validate(valid), isEmpty);

      // 2. Duration too small (< 0.1)
      final tooShort = Transition(
        type: TransitionType.fade,
        duration: 0.05,
        leftClipId: 'clip_1',
        rightClipId: 'clip_2',
      );
      expect(validator.validate(tooShort), contains('Transition duration must be >= 0.1s'));

      // 3. Duration too large (> 3.0)
      final tooLong = Transition(
        type: TransitionType.fade,
        duration: 3.5,
        leftClipId: 'clip_1',
        rightClipId: 'clip_2',
      );
      expect(validator.validate(tooLong), contains('Transition duration must be <= 3.0s'));

      // 4. Non-adjacent clips
      final nonAdjacent = Transition(
        type: TransitionType.fade,
        duration: 0.5,
        leftClipId: 'clip_1',
        rightClipId: 'clip_3',
      );
      expect(validator.validate(nonAdjacent), contains('Clips are not adjacent in the timeline'));
    });
  });

  group('Phase 8 — EditorViewModel Transition Mutations & Undo/Redo', () {
    late EditorViewModel vm;
    const clipA = VideoClip(
      id: 'clip_a',
      assetId: 'asset_a',
      title: 'Clip A',
      originalDuration: Duration(seconds: 4),
      trimStart: Duration.zero,
      trimEnd: Duration(seconds: 4),
      previewGradient: [Colors.blue, Colors.green],
    );
    const clipB = VideoClip(
      id: 'clip_b',
      assetId: 'asset_b',
      title: 'Clip B',
      originalDuration: Duration(seconds: 4),
      trimStart: Duration.zero,
      trimEnd: Duration(seconds: 4),
      previewGradient: [Colors.purple, Colors.pink],
    );
    const clipC = VideoClip(
      id: 'clip_c',
      assetId: 'asset_c',
      title: 'Clip C',
      originalDuration: Duration(seconds: 4),
      trimStart: Duration.zero,
      trimEnd: Duration(seconds: 4),
      previewGradient: [Colors.orange, Colors.red],
    );

    setUp(() {
      vm = EditorViewModel();
      final project = Project(
        id: 'vm_trans_proj',
        name: 'VM Trans Proj',
        videoClips: [clipA, clipB, clipC],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      vm.loadProject(project);
    });

    test('addTransition adds transition and enables undo/redo', () {
      final trans = Transition(
        type: TransitionType.pixelate,
        duration: 0.6,
        leftClipId: 'clip_a',
        rightClipId: 'clip_b',
      );

      final result = vm.addTransition(trans);
      expect(result.success, isTrue);
      expect(vm.transitions.length, 1);
      expect(vm.transitions.first.type, TransitionType.pixelate);

      // Undo
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(vm.transitions.isEmpty, isTrue);

      // Redo
      expect(vm.canRedo, isTrue);
      vm.redo();
      expect(vm.transitions.length, 1);
      expect(vm.transitions.first.type, TransitionType.pixelate);
    });

    test('applyTransitionToAll adds transitions across all adjacent boundaries', () {
      final result = vm.applyTransitionToAll(
        type: TransitionType.radial,
        duration: 0.7,
      );

      expect(result.success, isTrue);
      expect(vm.transitions.length, 2); // between A-B and B-C
      expect(vm.transitions[0].leftClipId, 'clip_a');
      expect(vm.transitions[0].rightClipId, 'clip_b');
      expect(vm.transitions[0].type, TransitionType.radial);
      expect(vm.transitions[1].leftClipId, 'clip_b');
      expect(vm.transitions[1].rightClipId, 'clip_c');
      expect(vm.transitions[1].type, TransitionType.radial);

      // Undo removes all transitions
      vm.undo();
      expect(vm.transitions.isEmpty, isTrue);
    });

    test('activeTransitionAtPlayhead tracks boundary windows accurately', () {
      final trans = Transition(
        type: TransitionType.wipeDown,
        duration: 1.0,
        leftClipId: 'clip_a',
        rightClipId: 'clip_b',
      );
      vm.addTransition(trans);

      // clipA is 4.0s. Boundary is at 4.0s. Transition window is [3.5s, 4.5s]
      // At 3.0s: before transition
      vm.seekTo(3.0);
      expect(vm.activeTransitionAtPlayhead, isNull);

      // At 3.5s: exact transition start
      vm.seekTo(3.5);
      final atStart = vm.activeTransitionAtPlayhead;
      expect(atStart, isNotNull);
      expect(atStart!.progress, closeTo(0.0, 0.05));
      expect(atStart.transition.type, TransitionType.wipeDown);

      // At 4.0s: transition midpoint
      vm.seekTo(4.0);
      final atMid = vm.activeTransitionAtPlayhead;
      expect(atMid, isNotNull);
      expect(atMid!.progress, closeTo(0.5, 0.05));

      // At 4.5s: transition end
      vm.seekTo(4.5);
      final atEnd = vm.activeTransitionAtPlayhead;
      expect(atEnd, isNotNull);
      expect(atEnd!.progress, closeTo(1.0, 0.05));

      // At 5.0s: after transition
      vm.seekTo(5.0);
      expect(vm.activeTransitionAtPlayhead, isNull);
    });
  });

  group('Phase 8 — TransitionShaderManager Tests', () {
    test('Singleton instance initializes without errors', () {
      final manager = TransitionShaderManager();
      expect(manager, isNotNull);
      // Before preloading or on unsupported test platform, getProgram returns null
      expect(manager.getProgram(TransitionType.fade), isNull);
    });
  });
}
