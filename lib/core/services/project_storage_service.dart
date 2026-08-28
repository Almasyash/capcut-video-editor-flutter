import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/domain/models/project.dart';

/// Centralized file-based persistence service for Projects and Drafts
class ProjectStorageService {
  ProjectStorageService._();
  static final ProjectStorageService instance = ProjectStorageService._();

  static const MethodChannel _platform = MethodChannel('com.mahmas.studio/file_picker');

  String? _cachedProjectsDirPath;
  final Map<String, Project> _memoryCache = {};

  /// Retrieves the persistent root directory path for saved projects
  Future<String> getProjectsDirectoryPath() async {
    if (_cachedProjectsDirPath != null) {
      return _cachedProjectsDirPath!;
    }

    String basePath;
    try {
      final nativeFilesDir = await _platform.invokeMethod<String>('getAppFilesDir');
      if (nativeFilesDir != null && nativeFilesDir.trim().isNotEmpty) {
        basePath = nativeFilesDir;
      } else {
        basePath = Directory.systemTemp.path;
      }
    } catch (_) {
      basePath = Directory.systemTemp.path;
    }

    final projectsDir = Directory('$basePath/projects');
    if (!projectsDir.existsSync()) {
      try {
        projectsDir.createSync(recursive: true);
      } catch (e) {
        debugPrint('[ProjectStorageService] Error creating projects dir: $e');
      }
    }

    _cachedProjectsDirPath = projectsDir.path;
    return _cachedProjectsDirPath!;
  }

  /// Loads all saved drafts and projects from disk, ordered by most recently updated
  Future<List<Project>> getAllProjects() async {
    final List<Project> projects = [];

    try {
      final dirPath = await getProjectsDirectoryPath();
      final dir = Directory(dirPath);

      if (dir.existsSync()) {
        final entries = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));

        for (final file in entries) {
          try {
            final jsonStr = file.readAsStringSync();
            final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
            final project = Project.fromJson(jsonMap);
            projects.add(project);
            _memoryCache[project.id] = project;
          } catch (e) {
            debugPrint('[ProjectStorageService] Error reading project file ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[ProjectStorageService] Failed to load projects: $e');
    }

    // Include any memory-only projects not yet flushed
    for (final p in _memoryCache.values) {
      if (!projects.any((existing) => existing.id == p.id)) {
        projects.add(p);
      }
    }

    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// Retrieves a specific project by its unique ID
  Future<Project?> getProjectById(String id) async {
    if (_memoryCache.containsKey(id)) {
      return _memoryCache[id];
    }

    try {
      final dirPath = await getProjectsDirectoryPath();
      final file = File('$dirPath/$id.json');
      if (file.existsSync()) {
        final jsonStr = file.readAsStringSync();
        final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
        final project = Project.fromJson(jsonMap);
        _memoryCache[project.id] = project;
        return project;
      }
    } catch (e) {
      debugPrint('[ProjectStorageService] Error fetching project $id: $e');
    }

    return null;
  }

  /// Atomically saves or updates a project draft to disk
  Future<void> saveProject(Project project) async {
    final updated = project.copyWith(updatedAt: DateTime.now());
    _memoryCache[updated.id] = updated;

    try {
      final dirPath = await getProjectsDirectoryPath();
      final file = File('$dirPath/${updated.id}.json');
      final jsonStr = const JsonEncoder.withIndent('  ').convert(updated.toJson());
      file.writeAsStringSync(jsonStr, flush: true);
      debugPrint('[ProjectStorageService] Saved project "${updated.name}" (${updated.id}) to ${file.path}');
    } catch (e) {
      debugPrint('[ProjectStorageService] Error saving project ${updated.id}: $e');
    }
  }

  /// Deletes a project draft from disk and memory cache
  Future<void> deleteProject(String id) async {
    _memoryCache.remove(id);

    try {
      final dirPath = await getProjectsDirectoryPath();
      final file = File('$dirPath/$id.json');
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint('[ProjectStorageService] Deleted project file: ${file.path}');
      }
    } catch (e) {
      debugPrint('[ProjectStorageService] Error deleting project $id: $e');
    }
  }

  /// Creates and saves a new blank project draft
  Future<Project> createNewProject({String? name}) async {
    final now = DateTime.now();
    final dateStr = '${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final project = Project(
      id: 'proj_${now.millisecondsSinceEpoch}',
      name: name ?? 'Project $dateStr',
      createdAt: now,
      updatedAt: now,
    );

    await saveProject(project);
    return project;
  }
}
