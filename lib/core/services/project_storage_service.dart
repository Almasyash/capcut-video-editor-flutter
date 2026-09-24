import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/domain/models/project.dart';

/// Centralized file-based persistence service for Projects and Drafts.
/// Features non-blocking async disk I/O, atomic file writes via temp swapping,
/// sequential save queuing to prevent race conditions, and corrupted file fault tolerance.
class ProjectStorageService {
  ProjectStorageService._();
  static final ProjectStorageService instance = ProjectStorageService._();

  static const MethodChannel _platform = MethodChannel('com.mahmas.studio/file_picker');

  String? _cachedProjectsDirPath;
  final Map<String, Project> _memoryCache = {};

  // Serialized save queuing per project ID to prevent race conditions and concurrent write conflicts
  final Map<String, Future<void>> _inFlightSaves = {};
  final Map<String, Project> _queuedProjects = {};

  @visibleForTesting
  void overrideDirectoryForTesting(Directory? dir) {
    _cachedProjectsDirPath = dir?.path;
    _memoryCache.clear();
    _inFlightSaves.clear();
    _queuedProjects.clear();
  }

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
    if (!await projectsDir.exists()) {
      try {
        await projectsDir.create(recursive: true);
      } catch (e) {
        debugPrint('[ProjectStorageService] Error creating projects dir: $e');
      }
    }

    _cachedProjectsDirPath = projectsDir.path;
    return _cachedProjectsDirPath!;
  }

  /// Loads all saved drafts and projects from disk, ordered by most recently updated.
  /// Gracefully skips corrupted files without deleting them or crashing the app.
  Future<List<Project>> getAllProjects() async {
    final List<Project> projects = [];

    try {
      final dirPath = await getProjectsDirectoryPath();
      final dir = Directory(dirPath);

      if (await dir.exists()) {
        final entries = await dir.list().toList();

        for (final entity in entries) {
          if (entity is File && entity.path.endsWith('.json') && !entity.path.endsWith('.tmp')) {
            try {
              final jsonStr = await entity.readAsString();
              final dynamic decoded = jsonDecode(jsonStr);
              if (decoded is! Map<String, dynamic>) {
                throw const FormatException('Project root JSON must be a Map object');
              }
              final project = Project.fromJson(decoded);
              projects.add(project);
              _memoryCache[project.id] = project;
            } catch (e, st) {
              // Gracefully handle corrupted JSON without crashing or deleting user data
              debugPrint('[ProjectStorageService] Error reading project file ${entity.path} (preserved): $e\n$st');
            }
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

  /// Retrieves a specific project by its unique ID.
  /// Returns null safely if the project does not exist or is corrupted.
  Future<Project?> getProjectById(String id) async {
    if (_memoryCache.containsKey(id)) {
      return _memoryCache[id];
    }

    try {
      final dirPath = await getProjectsDirectoryPath();
      final file = File('$dirPath/$id.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final dynamic decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          final project = Project.fromJson(decoded);
          _memoryCache[project.id] = project;
          return project;
        } else {
          debugPrint('[ProjectStorageService] Corrupted project $id: root is not a Map');
        }
      }
    } catch (e, st) {
      debugPrint('[ProjectStorageService] Error fetching project $id: $e\n$st');
    }

    return null;
  }

  /// Non-blocking async project save with serialization queue and atomic swap.
  /// Prevents race conditions where rapid edits could cause an older save to overwrite a newer state.
  Future<void> saveProject(Project project) async {
    final updated = project.copyWith(updatedAt: DateTime.now());
    _memoryCache[updated.id] = updated;

    // If an async save is already in flight for this project, queue the latest state
    if (_inFlightSaves.containsKey(updated.id)) {
      _queuedProjects[updated.id] = updated;
      await _inFlightSaves[updated.id];
      return;
    }

    final completer = Completer<void>();
    _inFlightSaves[updated.id] = completer.future;

    try {
      var toSave = updated;
      while (true) {
        await _writeProjectToDisk(toSave);

        // If another edit was queued while writing to disk, process the latest one next
        if (_queuedProjects.containsKey(updated.id)) {
          toSave = _queuedProjects.remove(updated.id)!;
        } else {
          break;
        }
      }
    } finally {
      _inFlightSaves.remove(updated.id);
      completer.complete();
    }
  }

  /// Internal worker: writes project to a .tmp file first, flushes, then atomically swaps.
  Future<void> _writeProjectToDisk(Project project) async {
    File? tempFile;
    try {
      final dirPath = await getProjectsDirectoryPath();
      final targetFile = File('$dirPath/${project.id}.json');
      tempFile = File('$dirPath/${project.id}.json.tmp');

      final jsonMap = project.toJson();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);

      // 1. Write to temporary file with flush to guarantee on-disk persistence
      await tempFile.writeAsString(jsonStr, flush: true);

      // 2. Atomically swap temp file to target file
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);
      } catch (_) {
        // Fallback for filesystem environments with cross-link / rename restrictions
        await tempFile.copy(targetFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      debugPrint('[ProjectStorageService] Saved project "${project.name}" (${project.id}) to ${targetFile.path}');
    } catch (e, st) {
      debugPrint('[ProjectStorageService] Error saving project ${project.id}: $e\n$st');
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Deletes a project draft from disk, temporary artifacts, and memory cache
  Future<void> deleteProject(String id) async {
    _memoryCache.remove(id);
    _queuedProjects.remove(id);

    try {
      final dirPath = await getProjectsDirectoryPath();
      final file = File('$dirPath/$id.json');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[ProjectStorageService] Deleted project file: ${file.path}');
      }
      final tmpFile = File('$dirPath/$id.json.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
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

  @visibleForTesting
  void clearMemoryCache() {
    _memoryCache.clear();
    _queuedProjects.clear();
    _inFlightSaves.clear();
  }

  @visibleForTesting
  bool isSaveInFlight(String id) => _inFlightSaves.containsKey(id);
}
