import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/domain/models/project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('editor_fs_crash_recovery_');
    ProjectStorageService.instance.overrideDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    ProjectStorageService.instance.overrideDirectoryForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProjectStorageService Crash Recovery Tests', () {
    test('getProjectById auto-recovers project from .tmp file when main .json is missing', () async {
      final now = DateTime.now();
      final project = Project(
        id: 'crash_proj_1',
        name: 'Recovered Draft 1',
        createdAt: now,
        updatedAt: now,
      );

      final projectsDirPath = await ProjectStorageService.instance.getProjectsDirectoryPath();
      final tmpFile = File('$projectsDirPath/crash_proj_1.json.tmp');
      await tmpFile.writeAsString(jsonEncode(project.toJson()), flush: true);

      // Verify main .json does not exist initially
      final mainFile = File('$projectsDirPath/crash_proj_1.json');
      expect(await mainFile.exists(), isFalse);

      // Fetch project by ID -> should trigger crash recovery
      final recovered = await ProjectStorageService.instance.getProjectById('crash_proj_1');
      expect(recovered, isNotNull);
      expect(recovered!.id, equals('crash_proj_1'));
      expect(recovered.name, equals('Recovered Draft 1'));

      // Main file should now exist
      expect(await mainFile.exists(), isTrue);
      // Temp file should have been cleaned up
      expect(await tmpFile.exists(), isFalse);
    });

    test('getProjectById auto-recovers project from .tmp file when main .json is 0 bytes', () async {
      final now = DateTime.now();
      final project = Project(
        id: 'crash_proj_2',
        name: 'Recovered Draft 2',
        createdAt: now,
        updatedAt: now,
      );

      final projectsDirPath = await ProjectStorageService.instance.getProjectsDirectoryPath();
      final mainFile = File('$projectsDirPath/crash_proj_2.json');
      await mainFile.writeAsString('', flush: true); // 0-byte corrupt file
      expect(await mainFile.length(), equals(0));

      final tmpFile = File('$projectsDirPath/crash_proj_2.json.tmp');
      await tmpFile.writeAsString(jsonEncode(project.toJson()), flush: true);

      final recovered = await ProjectStorageService.instance.getProjectById('crash_proj_2');
      expect(recovered, isNotNull);
      expect(recovered!.name, equals('Recovered Draft 2'));
      expect(await mainFile.length(), greaterThan(0));
    });

    test('getAllProjects auto-recovers orphaned .tmp files during listing', () async {
      final now = DateTime.now();
      final project = Project(
        id: 'crash_proj_3',
        name: 'Recovered Draft 3',
        createdAt: now,
        updatedAt: now,
      );

      final projectsDirPath = await ProjectStorageService.instance.getProjectsDirectoryPath();
      final tmpFile = File('$projectsDirPath/crash_proj_3.json.tmp');
      await tmpFile.writeAsString(jsonEncode(project.toJson()), flush: true);

      final allProjects = await ProjectStorageService.instance.getAllProjects();
      expect(allProjects.any((p) => p.id == 'crash_proj_3'), isTrue);

      final mainFile = File('$projectsDirPath/crash_proj_3.json');
      expect(await mainFile.exists(), isTrue);
      expect(await tmpFile.exists(), isFalse);
    });
  });
}
