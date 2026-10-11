import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('editor_fs_autosave_race_test_');
    ProjectStorageService.instance.overrideDirectoryForTesting(testDir);
  });

  tearDown(() async {
    ProjectStorageService.instance.overrideDirectoryForTesting(null);
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (await testDir.exists()) {
          await testDir.delete(recursive: true);
        }
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  group('Autosave & Project Storage Concurrency Race Tests', () {
    test('1. Debounce timer does not resurrect deleted project after saveOrCleanupOnExit', () async {
      final blankProject = await ProjectStorageService.instance.createNewProject();
      final projectFile = File('${testDir.path}/${blankProject.id}.json');
      expect(await projectFile.exists(), isTrue);

      final viewModel = EditorViewModel(
        initialProject: blankProject,
        enableMockFallback: false,
      );

      // Trigger debounced autosave
      viewModel.scheduleAutoSave();

      // Immediately exit and cleanup
      await viewModel.saveOrCleanupOnExit();
      expect(await projectFile.exists(), isFalse);

      // Wait 400ms for debounce timer duration (300ms) to elapse
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Project must NOT be resurrected on disk
      expect(await projectFile.exists(), isFalse);
      final all = await ProjectStorageService.instance.getAllProjects();
      expect(all.any((p) => p.id == blankProject.id), isFalse);

      viewModel.dispose();
    });

    test('2. Concurrent in-flight save and deleteProject does not throw or leak files', () async {
      final project = await ProjectStorageService.instance.createNewProject();
      final targetFile = File('${testDir.path}/${project.id}.json');
      final tmpFile = File('${testDir.path}/${project.id}.json.tmp');

      // Start saving asynchronously
      final saveFuture = ProjectStorageService.instance.saveProject(
        project.copyWith(name: 'Concurrent Save Test'),
      );

      // Concurrently trigger deleteProject
      final deleteFuture = ProjectStorageService.instance.deleteProject(project.id);

      // Both must complete cleanly without throwing
      await Future.wait([saveFuture, deleteFuture]);

      // Both target and temp file must be absent
      expect(await targetFile.exists(), isFalse);
      expect(await tmpFile.exists(), isFalse);
    });

    test('3. ViewModel disposal does not recreate untouched blank draft', () async {
      final blankProject = await ProjectStorageService.instance.createNewProject();
      final projectFile = File('${testDir.path}/${blankProject.id}.json');
      expect(await projectFile.exists(), isTrue);

      final viewModel = EditorViewModel(
        initialProject: blankProject,
        enableMockFallback: false,
      );

      await viewModel.saveOrCleanupOnExit();
      expect(await projectFile.exists(), isFalse);

      // Dispose view model
      viewModel.dispose();

      // Must remain absent
      expect(await projectFile.exists(), isFalse);
    });

    test('4. Rapid sequential project creation and exit leaves zero orphaned drafts', () async {
      for (int i = 0; i < 5; i++) {
        final project = await ProjectStorageService.instance.createNewProject(name: 'Quick $i');
        final viewModel = EditorViewModel(
          initialProject: project,
          enableMockFallback: false,
        );

        viewModel.scheduleAutoSave();
        await viewModel.saveOrCleanupOnExit();
        viewModel.dispose();
      }

      await Future<void>.delayed(const Duration(milliseconds: 350));
      final all = await ProjectStorageService.instance.getAllProjects();
      expect(all, isEmpty);
    });

    test('5. Non-empty project persists changes and survives auto-save cycle', () async {
      final project = await ProjectStorageService.instance.createNewProject(name: 'Valid Project');
      final projectFile = File('${testDir.path}/${project.id}.json');

      final viewModel = EditorViewModel(
        initialProject: project,
        enableMockFallback: false,
      );

      viewModel.addClip(
        const VideoClip(
          id: 'clip_keep',
          assetId: 'asset_keep',
          title: 'Preserved Video',
          originalDuration: Duration(seconds: 4),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 4),
          previewGradient: [Colors.purple, Colors.blue],
        ),
      );

      expect(viewModel.isUntouchedBlankProject, isFalse);

      viewModel.scheduleAutoSave();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(await projectFile.exists(), isTrue);
      final loaded = await ProjectStorageService.instance.getProjectById(project.id);
      expect(loaded, isNotNull);
      expect(loaded!.videoClips.length, equals(1));

      await viewModel.saveOrCleanupOnExit();
      expect(await projectFile.exists(), isTrue);
      viewModel.dispose();
    });
  });
}
