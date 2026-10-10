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
    testDir = await Directory.systemTemp.createTemp('editor_fs_cleanup_test_');
    ProjectStorageService.instance.overrideDirectoryForTesting(testDir);
  });

  tearDown(() async {
    ProjectStorageService.instance.overrideDirectoryForTesting(null);
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Empty Project Auto-Cleanup on Exit Tests', () {
    test('Untouched blank project is identified correctly', () async {
      final blankProject = await ProjectStorageService.instance.createNewProject();
      final viewModel = EditorViewModel(
        initialProject: blankProject,
        enableMockFallback: false,
      );

      expect(viewModel.isUntouchedBlankProject, isTrue);
    });

    test('Untouched blank project is deleted on saveOrCleanupOnExit', () async {
      final blankProject = await ProjectStorageService.instance.createNewProject();
      final projectFile = File('${testDir.path}/${blankProject.id}.json');

      // Ensure file exists initially from createNewProject
      expect(await projectFile.exists(), isTrue);

      final viewModel = EditorViewModel(
        initialProject: blankProject,
        enableMockFallback: false,
      );

      expect(viewModel.isUntouchedBlankProject, isTrue);

      // Perform exit cleanup
      await viewModel.saveOrCleanupOnExit();

      // Ensure file was deleted
      expect(await projectFile.exists(), isFalse);
      final allProjects = await ProjectStorageService.instance.getAllProjects();
      expect(allProjects.any((p) => p.id == blankProject.id), isFalse);
    });

    test('Project with video clips is preserved on saveOrCleanupOnExit', () async {
      final project = await ProjectStorageService.instance.createNewProject();
      final projectFile = File('${testDir.path}/${project.id}.json');

      final viewModel = EditorViewModel(
        initialProject: project,
        enableMockFallback: false,
      );

      // Add a video clip
      viewModel.addClip(
        const VideoClip(
          id: 'clip_01',
          assetId: 'asset_01',
          title: 'Sample Video',
          originalDuration: Duration(seconds: 5),
          trimStart: Duration.zero,
          trimEnd: Duration(seconds: 5),
          previewGradient: [Color(0xFF0000FF), Color(0xFF800080)],
        ),
      );

      expect(viewModel.isUntouchedBlankProject, isFalse);

      await viewModel.saveOrCleanupOnExit();

      // Ensure file remains saved on disk
      expect(await projectFile.exists(), isTrue);
      final allProjects = await ProjectStorageService.instance.getAllProjects();
      expect(allProjects.any((p) => p.id == project.id), isTrue);
    });
  });
}
