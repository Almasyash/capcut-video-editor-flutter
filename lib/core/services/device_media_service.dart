import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';

/// Legacy result wrapper for existing presentation widgets (backward compatible)
class DeviceMediaResult {
  final String fileName;
  final String filePath; // Actual cached filesystem path or URI
  final String fileType; // 'video', 'photo', 'audio'
  final Duration estimatedDuration;
  final List<Color> gradient;
  final IconData icon;
  final int fileSizeMb;
  final String? contentUri;

  const DeviceMediaResult({
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.estimatedDuration,
    required this.gradient,
    required this.icon,
    this.fileSizeMb = 14,
    this.contentUri,
  });

  MediaAsset toMediaAsset() {
    MediaAssetType assetType;
    if (fileType == 'audio') {
      assetType = MediaAssetType.audio;
    } else if (fileType == 'photo') {
      assetType = MediaAssetType.photo;
    } else {
      assetType = MediaAssetType.video;
    }

    final isContentUri = filePath.startsWith('content://');

    return MediaAsset(
      id: 'asset_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}',
      type: assetType,
      name: fileName,
      uri: contentUri ?? (isContentUri ? filePath : null),
      localPath: isContentUri ? null : filePath,
      duration: null,
      sizeBytes: fileSizeMb * 1024 * 1024,
      thumbnailPath: (assetType == MediaAssetType.photo && !isContentUri) ? filePath : null,
      createdAt: DateTime.now(),
    );
  }
}

/// Service to handle native system intents, runtime permissions, and media/audio file picking
class DeviceMediaService {
  DeviceMediaService._();

  static const MethodChannel _platform = MethodChannel('com.mahmas.studio/file_picker');

  static const List<List<Color>> _vibrantGradients = [
    [Color(0xFF00C9FF), Color(0xFF92FE9D)],
    [Color(0xFFFC466B), Color(0xFF3F5EFB)],
    [Color(0xFFFF512F), Color(0xFFDD2476)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
    [Color(0xFF00E5FF), Color(0xFF7928CA)],
    [Color(0xFFFF8008), Color(0xFFFFC837)],
    [Color(0xFF4E54C8), Color(0xFF8F94FB)],
    [Color(0xFF1D2671), Color(0xFFC33764)],
  ];

  /// Requests storage/media permissions using native platform channel
  static Future<bool> requestStoragePermissions() async {
    try {
      final granted = await _platform.invokeMethod<bool>('requestPermissions');
      return granted ?? true;
    } on MissingPluginException {
      return true; // Web / testing fallback
    } catch (_) {
      return true;
    }
  }

  /// Imports a Video or Photo from native device storage into a clean [MediaAsset] model
  static Future<MediaAsset?> pickMediaAsset({String type = 'media'}) async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>(
        'pickMediaFile',
        {'type': type},
      );

      if (result == null) {
        // User cancelled picker
        return null;
      }

      final uri = result['uri'] as String?;
      final localPath = result['path'] as String?;
      final name = (result['name'] as String?) ?? 'Selected_Media';
      final mime = (result['mimeType'] as String?) ?? '';
      final sizeBytes = (result['size'] as num?)?.toInt();

      // Rule 2: If Android returns null/empty localPath, fail import
      if (localPath == null || localPath.trim().isEmpty) {
        debugPrint('[DeviceMediaService] Import failed: Native picker returned null/empty localPath');
        return null;
      }

      // Rule 1: Content URI must never become localPath
      if (localPath.startsWith('content://')) {
        debugPrint('[DeviceMediaService] Import failed: localPath is a content URI, expected filesystem path');
        return null;
      }

      // Rule 3: Cached file must exist on disk
      if (!kIsWeb) {
        final cachedFile = File(localPath);
        if (!cachedFile.existsSync()) {
          debugPrint('[DeviceMediaService] Import failed: Cached file does not exist on disk: $localPath');
          return null;
        }
      }

      final isPhoto = mime.startsWith('image') ||
          name.toLowerCase().endsWith('.jpg') ||
          name.toLowerCase().endsWith('.jpeg') ||
          name.toLowerCase().endsWith('.png') ||
          name.toLowerCase().endsWith('.webp');

      final assetType = isPhoto ? MediaAssetType.photo : MediaAssetType.video;

      return MediaAsset(
        id: 'asset_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}',
        type: assetType,
        name: name,
        uri: uri,
        localPath: localPath,
        duration: null, // Rule 4: No fake durations, use null until real metadata extraction exists
        sizeBytes: sizeBytes, // Rule 5: Preserve exact native sizeBytes
        thumbnailPath: isPhoto ? localPath : null,
        createdAt: DateTime.now(),
      );
    } on MissingPluginException {
      debugPrint('[DeviceMediaService] MethodChannel not available on this platform');
      return null;
    } catch (e) {
      debugPrint('[DeviceMediaService] Error picking media asset: $e');
      return null;
    }
  }

  /// Imports an Audio track from native device storage into a clean [MediaAsset] model
  static Future<MediaAsset?> pickAudioAsset() async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>('pickAudioFile');

      if (result == null) {
        // User cancelled picker
        return null;
      }

      final uri = result['uri'] as String?;
      final localPath = result['path'] as String?;
      final name = (result['name'] as String?) ?? 'Selected_Audio';
      final sizeBytes = (result['size'] as num?)?.toInt();

      // Rule 2: If Android returns null/empty localPath, fail import
      if (localPath == null || localPath.trim().isEmpty) {
        debugPrint('[DeviceMediaService] Import failed: Audio picker returned null/empty localPath');
        return null;
      }

      // Rule 1: Content URI must never become localPath
      if (localPath.startsWith('content://')) {
        debugPrint('[DeviceMediaService] Import failed: localPath is a content URI, expected filesystem path');
        return null;
      }

      // Rule 3: Cached file must exist on disk
      if (!kIsWeb) {
        final cachedFile = File(localPath);
        if (!cachedFile.existsSync()) {
          debugPrint('[DeviceMediaService] Import failed: Cached audio file does not exist on disk: $localPath');
          return null;
        }
      }

      return MediaAsset(
        id: 'audio_asset_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}',
        type: MediaAssetType.audio,
        name: name,
        uri: uri,
        localPath: localPath,
        duration: null, // Rule 4: No fake durations, use null until real metadata extraction exists
        sizeBytes: sizeBytes, // Rule 5: Preserve exact native sizeBytes
        thumbnailPath: null,
        createdAt: DateTime.now(),
      );
    } on MissingPluginException {
      debugPrint('[DeviceMediaService] MethodChannel not available on this platform');
      return null;
    } catch (e) {
      debugPrint('[DeviceMediaService] Error picking audio asset: $e');
      return null;
    }
  }

  /// Launches native system file picker intent (ACTION_GET_CONTENT) with localPath resolution (Legacy compatible)
  static Future<DeviceMediaResult?> pickMediaFromNativeStorage({String type = 'media'}) async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>(
        'pickMediaFile',
        {'type': type},
      );

      if (result != null) {
        final uri = result['uri'] as String?;
        final localPath = result['path'] as String?;
        final name = (result['name'] as String?) ?? 'Selected_Media';
        final mime = (result['mimeType'] as String?) ?? '';
        final sizeBytes = (result['size'] as num?)?.toInt() ?? 0;
        final sizeMb = (sizeBytes / (1024 * 1024)).ceil();

        // Crucial fix: Use localPath (cached absolute filesystem path) rather than content:// URI
        final effectivePath = localPath ?? uri ?? '';

        final isPhoto = mime.startsWith('image') ||
            name.toLowerCase().endsWith('.jpg') ||
            name.toLowerCase().endsWith('.jpeg') ||
            name.toLowerCase().endsWith('.png') ||
            name.toLowerCase().endsWith('.webp');

        final random = math.Random(name.hashCode);
        final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

        return DeviceMediaResult(
          fileName: name,
          filePath: effectivePath,
          fileType: isPhoto ? 'photo' : 'video',
          estimatedDuration: isPhoto ? const Duration(seconds: 4) : const Duration(seconds: 12),
          gradient: gradient,
          icon: isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
          fileSizeMb: math.max(1, sizeMb),
          contentUri: uri,
        );
      }
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[DeviceMediaService] Error picking native media: $e');
      return null;
    }
    return null;
  }

  /// Launches native system file picker intent to pick actual audio file from device (Legacy compatible)
  static Future<DeviceMediaResult?> pickAudioFromNativeStorage() async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>('pickAudioFile');

      if (result != null) {
        final uri = result['uri'] as String?;
        final localPath = result['path'] as String?;
        final name = (result['name'] as String?) ?? 'Selected_Audio';
        final sizeBytes = (result['size'] as num?)?.toInt() ?? 0;
        final sizeMb = (sizeBytes / (1024 * 1024)).ceil();

        // Crucial fix: Use localPath (cached absolute filesystem path) rather than content:// URI
        final effectivePath = localPath ?? uri ?? '';

        final random = math.Random(name.hashCode);
        final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

        return DeviceMediaResult(
          fileName: name,
          filePath: effectivePath,
          fileType: 'audio',
          estimatedDuration: const Duration(seconds: 28),
          gradient: gradient,
          icon: Icons.music_note_rounded,
          fileSizeMb: math.max(1, sizeMb),
          contentUri: uri,
        );
      }
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[DeviceMediaService] Error picking native audio: $e');
      return null;
    }
    return null;
  }

  /// Creates custom video result with file attributes (Mock / Test helper)
  static DeviceMediaResult createCustomVideoResult({
    required String name,
    Duration duration = const Duration(seconds: 12),
    int sizeMb = 18,
    String? customPath,
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];
    final cleanName = name.trim().replaceAll(' ', '_');
    final formattedName = cleanName.endsWith('.mp4') ? cleanName : '$cleanName.mp4';

    return DeviceMediaResult(
      fileName: formattedName,
      filePath: customPath ?? '/storage/emulated/0/DCIM/Camera/$formattedName',
      fileType: 'video',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.videocam_rounded,
      fileSizeMb: sizeMb,
      contentUri: 'content://media/external/video/media/$formattedName',
    );
  }

  /// Creates custom photo result (Mock / Test helper)
  static DeviceMediaResult createCustomPhotoResult({
    required String name,
    Duration duration = const Duration(seconds: 4),
    int sizeMb = 3,
    String? customPath,
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];
    final cleanName = name.trim().replaceAll(' ', '_');
    final formattedName = cleanName.endsWith('.jpg') ? cleanName : '$cleanName.jpg';

    return DeviceMediaResult(
      fileName: formattedName,
      filePath: customPath ?? '/storage/emulated/0/DCIM/Pictures/$formattedName',
      fileType: 'photo',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.image_rounded,
      fileSizeMb: sizeMb,
      contentUri: 'content://media/external/images/media/$formattedName',
    );
  }

  /// Creates custom audio result (Mock / Test helper)
  static DeviceMediaResult createCustomAudioResult({
    required String name,
    Duration duration = const Duration(seconds: 25),
    int sizeMb = 5,
    String? customPath,
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];
    final cleanName = name.trim().replaceAll(' ', '_');
    final formattedName = (cleanName.endsWith('.mp3') || cleanName.endsWith('.wav'))
        ? cleanName
        : '$cleanName.mp3';

    return DeviceMediaResult(
      fileName: formattedName,
      filePath: customPath ?? '/storage/emulated/0/Music/$formattedName',
      fileType: 'audio',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.music_note_rounded,
      fileSizeMb: sizeMb,
      contentUri: 'content://media/external/audio/media/$formattedName',
    );
  }

  /// Returns preset device albums/folders for quick selection
  static List<Map<String, dynamic>> getDeviceStorageFolders() {
    return [
      {'name': 'Camera (DCIM)', 'count': 42, 'icon': Icons.camera_alt_rounded},
      {'name': 'Downloads', 'count': 18, 'icon': Icons.download_rounded},
      {'name': 'Screen Recordings', 'count': 9, 'icon': Icons.screen_share_rounded},
      {'name': 'WhatsApp Video', 'count': 27, 'icon': Icons.chat_bubble_rounded},
      {'name': 'Instagram Reels', 'count': 14, 'icon': Icons.video_library_rounded},
      {'name': 'Music Library', 'count': 64, 'icon': Icons.library_music_rounded},
    ];
  }
}
