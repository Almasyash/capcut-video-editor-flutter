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

  group('Phase 8.1 — True CapCut-Style Transition Engine & Overlap Tests', () {
    test('calculateMaxDuration dynamically clamps duration by clip active lengths and handles', () {
      // 1. Untrimmed clips with 1.2s and 0.8s active durations
      const clip1 = VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(milliseconds: 1200),
        previewGradient: [Colors.blue, Colors.green],
      );
      const clip2 = VideoClip(
        id: 'c2',
        assetId: 'a2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: Duration(milliseconds: 800),
        previewGradient: [Colors.purple, Colors.pink],
      );

      final maxDurUntrimmed = TransitionValidator.calculateMaxDuration(clip1, clip2);
      expect(maxDurUntrimmed, 0.8);

      // 2. Trimmed clips with handles (e.g. clip A has 0.6s tail, clip B has 0.8s head)
      const clipTrimmedA = VideoClip(
        id: 'cta',
        assetId: 'a1',
        title: 'Trimmed A',
        originalDuration: Duration(milliseconds: 5000),
        trimStart: Duration(milliseconds: 1000),
        trimEnd: Duration(milliseconds: 4400), // available tail = 600ms = 0.6s
        previewGradient: [Colors.blue, Colors.green],
      );
      const clipTrimmedB = VideoClip(
        id: 'ctb',
        assetId: 'a2',
        title: 'Trimmed B',
        originalDuration: Duration(milliseconds: 5000),
        trimStart: Duration(milliseconds: 800), // available head = 800ms = 0.8s
        trimEnd: Duration(milliseconds: 4000),
        previewGradient: [Colors.purple, Colors.pink],
      );

      final maxDurHandles = TransitionValidator.calculateMaxDuration(clipTrimmedA, clipTrimmedB);
      // 2.0 * min(0.6, 0.8) = 1.2s
      expect(maxDurHandles, 1.2);

      // 3. Clamped by adjacent existing transition to prevent overlapping transition windows
      final existingTrans = [
        Transition(
          id: 'trans_prev',
          type: TransitionType.fade,
          duration: 1.0, // takes 0.5s on left of clipTrimmedA
          leftClipId: 'c_prior',
          rightClipId: 'cta',
        ),
      ];
      final maxDurAdjacent = TransitionValidator.calculateMaxDuration(
        clipTrimmedA,
        clipTrimmedB,
        existingTransitions: existingTrans,
      );
      expect(maxDurAdjacent <= 1.2, isTrue);
    });

    test('timelineToSourceTime accurately computes head and tail source times across transition window', () {
      const clipA = VideoClip(
        id: 'cA',
        assetId: 'aA',
        title: 'Clip A',
        originalDuration: Duration(milliseconds: 6000),
        trimStart: Duration(milliseconds: 1000),
        trimEnd: Duration(milliseconds: 5000), // 4.0s active
        speed: 1.0,
        previewGradient: [Colors.blue, Colors.green],
      );
      const clipB = VideoClip(
        id: 'cB',
        assetId: 'aB',
        title: 'Clip B',
        originalDuration: Duration(milliseconds: 6000),
        trimStart: Duration(milliseconds: 2000), // 2.0s head handle
        trimEnd: Duration(milliseconds: 6000), // 4.0s active
        speed: 1.0,
        previewGradient: [Colors.purple, Colors.pink],
      );

      // Cut boundary is at timeline 4.0s. 1.0s transition spans [3.5s, 4.5s]
      // At 3.5s (transition start):
      final srcAStart = EditorViewModel.timelineToSourceTime(clipA, 3.5, 0.0);
      final srcBStart = EditorViewModel.timelineToSourceTime(clipB, 3.5, 4.0);
      // Clip A is at 1.0s + 3.5s = 4.5s
      expect(srcAStart, closeTo(4.5, 0.01));
      // Clip B has 2.0s trimStart - 0.5s = 1.5s (reading head handle!)
      expect(srcBStart, closeTo(1.5, 0.01));

      // At 4.0s (midpoint / cut):
      final srcAMid = EditorViewModel.timelineToSourceTime(clipA, 4.0, 0.0);
      final srcBMid = EditorViewModel.timelineToSourceTime(clipB, 4.0, 4.0);
      expect(srcAMid, closeTo(5.0, 0.01)); // trimEnd
      expect(srcBMid, closeTo(2.0, 0.01)); // trimStart

      // At 4.5s (transition end):
      final srcAEnd = EditorViewModel.timelineToSourceTime(clipA, 4.5, 0.0);
      final srcBEnd = EditorViewModel.timelineToSourceTime(clipB, 4.5, 4.0);
      expect(srcAEnd, closeTo(5.5, 0.01)); // reading tail handle!
      expect(srcBEnd, closeTo(2.5, 0.01));
    });

    test('EditorViewModel supports boundary selection and dynamic max duration lookup', () {
      final vm = EditorViewModel();
      const clip1 = VideoClip(
        id: 'clip_1',
        assetId: 'a1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 2), // 2.0s
        previewGradient: [Colors.blue, Colors.green],
      );
      const clip2 = VideoClip(
        id: 'clip_2',
        assetId: 'a2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 1), // 1.0s
        previewGradient: [Colors.purple, Colors.pink],
      );

      vm.loadProject(Project(
        id: 'test_phase8_1',
        name: 'Phase 8.1 Test',
        videoClips: [clip1, clip2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(vm.selectedTransitionBoundaryIndex, isNull);
      vm.selectTransitionBoundary(0);
      expect(vm.selectedTransitionBoundaryIndex, 0);

      final maxDur = vm.getMaxTransitionDurationForBoundary('clip_1', 'clip_2');
      expect(maxDur, 1.0); // limited by 1.0s active duration of clip2

      vm.selectTransitionBoundary(null);
      expect(vm.selectedTransitionBoundaryIndex, isNull);
    });

    test('ActiveTransitionState provides millisecond source offsets for hardware decoding', () {
      final vm = EditorViewModel();
      const clip1 = VideoClip(
        id: 'c1',
        assetId: 'a1',
        title: 'Clip 1',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        previewGradient: [Colors.blue, Colors.green],
      );
      const clip2 = VideoClip(
        id: 'c2',
        assetId: 'a2',
        title: 'Clip 2',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 4),
        previewGradient: [Colors.purple, Colors.pink],
      );

      vm.loadProject(Project(
        id: 'test_phase8_1_ms',
        name: 'Phase 8.1 MS',
        videoClips: [clip1, clip2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transitions: [
          Transition(
            id: 't1',
            type: TransitionType.slideLeft,
            duration: 1.0,
            leftClipId: 'c1',
            rightClipId: 'c2',
          ),
        ],
      ));

      // Seek to transition midpoint (4.0s)
      vm.seekTo(4.0);
      final state = vm.activeTransitionAtPlayhead;
      expect(state, isNotNull);
      expect(state!.progress, closeTo(0.5, 0.01));
      expect(state.sourceOffsetMsA, 4000);
      expect(state.sourceOffsetMsB, 0);
    });
  });
}
