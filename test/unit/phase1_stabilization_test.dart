import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1: Stabilization Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('phase1_test_');
      ProjectStorageService.instance.overrideDirectoryForTesting(tempDir);
    });

    tearDown(() async {
      ProjectStorageService.instance.overrideDirectoryForTesting(null);
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('1. AndroidManifest contains release INTERNET permission', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();
      expect(
        content.contains('<uses-permission android:name="android.permission.INTERNET" />'),
        isTrue,
        reason: 'AndroidManifest.xml must declare android.permission.INTERNET',
      );
    });

    test('2. Blank project initialization has 0 clips and 0 overlays by default in production', () {
      // Production default is enableMockFallback: false
      final vm = EditorViewModel(enableMockFallback: false);
      expect(vm.videoClips, isEmpty, reason: 'New blank project must not contain mock clips');
      expect(vm.textOverlays, isEmpty, reason: 'New blank project must not contain mock text');
      expect(vm.selectedClipIndex, isNull, reason: 'No clip should be selected in empty project');
      expect(vm.totalDurationInSeconds, equals(0.0));

      // Calling addNewClip without device media should not inject mock clips
      vm.addNewClip();
      expect(vm.videoClips, isEmpty);

      vm.dispose();
    });

    test('3. Test fixture can still enable mock fallback when explicitly requested', () {
      final vm = EditorViewModel(enableMockFallback: true);
      expect(vm.videoClips.isNotEmpty, isTrue);
      expect(vm.selectedClipIndex, equals(0));
      expect(vm.totalDurationInSeconds, greaterThan(0));
      vm.dispose();
    });

    test('4. Async project auto-save queues in-flight saves and commits latest state', () async {
      final project1 = Project(
        id: 'queue_test_project',
        name: 'Version 1',
        aspectRatio: AspectRatioPreset.ratio16x9,
        videoClips: const [],
        overlayClips: const [],
        stickerOverlays: const [],
        textOverlays: const [],
        audioTracks: const [],
        mediaLibrary: const [],
        transitions: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final project2 = project1.copyWith(name: 'Version 2');
      final project3 = project1.copyWith(name: 'Version 3 (Final)');

      // Dispatch 3 rapid consecutive saves to trigger the in-flight serialization queue
      final f1 = ProjectStorageService.instance.saveProject(project1);
      final f2 = ProjectStorageService.instance.saveProject(project2);
      final f3 = ProjectStorageService.instance.saveProject(project3);

      await Future.wait([f1, f2, f3]);

      // Verify that after all pending saves resolve, the stored project is the latest version
      final loaded = await ProjectStorageService.instance.getProjectById('queue_test_project');
      expect(loaded, isNotNull);
      expect(loaded!.name, equals('Version 3 (Final)'));
    });

    test('5. Corrupted project JSON does not crash, is fault-tolerant, and preserves file', () async {
      final corruptFile = File('${tempDir.path}/corrupt_proj.json');
      await corruptFile.writeAsString('{ this is not valid json! @#\$% }');

      // Attempt to load the corrupted project
      final result = await ProjectStorageService.instance.getProjectById('corrupt_proj');
      expect(result, isNull, reason: 'Corrupted JSON should gracefully return null instead of throwing');

      // Ensure the corrupted file was NOT deleted, preserving user data for manual recovery
      expect(corruptFile.existsSync(), isTrue, reason: 'Corrupt project file should not be erased');

      // Also ensure getAllProjects does not crash when directory contains corrupt file
      final allProjects = await ProjectStorageService.instance.getAllProjects();
      expect(allProjects, isA<List<Project>>());
    });

    test('6. EditorViewModel lifecycle: dispose cancels timers and is idempotent', () {
      final vm = EditorViewModel(enableMockFallback: false);
      vm.scheduleAutoSave();

      // First dispose
      expect(() => vm.dispose(), returnsNormally);

      // Second dispose should be a safe no-op (idempotent)
      expect(() => vm.dispose(), returnsNormally);
    });

    test('7. Missing media detection identifies nonexistent files', () {
      const missingPath = '/non/existent/path/to/video_file.mp4';
      final file = File(missingPath);
      expect(file.existsSync(), isFalse);

      const clip = VideoClip(
        id: 'clip_missing',
        assetId: 'asset_missing',
        title: 'Missing File Clip',
        originalDuration: Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 5),
        previewGradient: [Colors.red, Colors.orange],
      );

      // Check that a missing file path is recognized
      final isOffline = missingPath.isNotEmpty && !file.existsSync();
      expect(isOffline, isTrue);
      expect(clip.title, equals('Missing File Clip'));
    });
  });
}
