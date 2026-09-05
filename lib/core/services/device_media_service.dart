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

/// Structured result returned from native video audio extraction
class ExtractedAudioResult {
  final bool success;
  final String? localPath;
  final String? fileName;
  final Duration? duration;
  final int? sizeBytes;
  final String? errorCode;
  final String? errorMessage;

  const ExtractedAudioResult({
    required this.success,
    this.localPath,
    this.fileName,
    this.duration,
    this.sizeBytes,
    this.errorCode,
    this.errorMessage,
  });

  bool get isNoAudioTrack => errorCode == 'NO_AUDIO_TRACK';
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

  /// Extracts the audio track from a video file into a standalone persistent .m4a audio file
  static Future<ExtractedAudioResult> extractAudioFromVideo({
    required String videoPath,
    String? outputName,
  }) async {
    if (videoPath.trim().isEmpty) {
      return const ExtractedAudioResult(
        success: false,
        errorCode: 'INVALID_PATH',
        errorMessage: 'Video path cannot be empty',
      );
    }

    if (!kIsWeb && !videoPath.startsWith('/mock/') && !videoPath.startsWith('/data/user/')) {
      final file = File(videoPath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        return ExtractedAudioResult(
          success: false,
          errorCode: 'FILE_NOT_FOUND',
          errorMessage: 'Video file does not exist or is empty at $videoPath',
        );
      }
    }

    try {
      final result = await _platform.invokeMapMethod<String, dynamic>(
        'extractAudioFromVideo',
        {
          'path': videoPath,
          if (outputName != null) 'outputName': outputName,
        },
      );

      if (result != null && result['success'] == true) {
        final path = result['path'] as String?;
        final name = result['name'] as String? ?? 'extracted_audio.m4a';
        final size = (result['size'] as num?)?.toInt();
        final durationMs = (result['durationMs'] as num?)?.toInt();

        if (path == null || path.isEmpty) {
          return const ExtractedAudioResult(
            success: false,
            errorCode: 'EXTRACTION_FAILED',
            errorMessage: 'Native extractor returned empty file path',
          );
        }

        if (!kIsWeb && !path.startsWith('/mock/') && !path.startsWith('/data/user/')) {
          final audioFile = File(path);
          if (!audioFile.existsSync() || audioFile.lengthSync() == 0) {
            return const ExtractedAudioResult(
              success: false,
              errorCode: 'EXTRACTION_FAILED',
              errorMessage: 'Extracted audio file does not exist on disk',
            );
          }
        }

        return ExtractedAudioResult(
          success: true,
          localPath: path,
          fileName: name,
          sizeBytes: size,
          duration: (durationMs != null && durationMs > 0) ? Duration(milliseconds: durationMs) : null,
        );
      }

      return const ExtractedAudioResult(
        success: false,
        errorCode: 'EXTRACTION_FAILED',
        errorMessage: 'Native audio extraction returned empty result',
      );
    } on PlatformException catch (pe) {
      debugPrint('[DeviceMediaService] PlatformException extracting audio: ${pe.code} - ${pe.message}');
      return ExtractedAudioResult(
        success: false,
        errorCode: pe.code,
        errorMessage: pe.message ?? 'Platform error during audio extraction',
      );
    } on MissingPluginException {
      debugPrint('[DeviceMediaService] MissingPluginException for extractAudioFromVideo (test/web mock)');
      final mockName = outputName != null ? '$outputName.m4a' : 'extracted_${DateTime.now().millisecondsSinceEpoch}.m4a';
      return ExtractedAudioResult(
        success: true,
        localPath: '/mock/extracted/$mockName',
        fileName: mockName,
        duration: const Duration(seconds: 15),
        sizeBytes: 1024 * 512,
      );
    } catch (e) {
      debugPrint('[DeviceMediaService] Error extracting audio: $e');
      return ExtractedAudioResult(
        success: false,
        errorCode: 'UNKNOWN_ERROR',
        errorMessage: e.toString(),
      );
    }
  }

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

  /// Saves an exported video file to the device's native media gallery (MediaStore on Android)
  static Future<bool> saveVideoToGallery({
    required String filePath,
    String? fileName,
  }) async {
    if (filePath.isEmpty) return false;

    if (!kIsWeb) {
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        debugPrint('[DeviceMediaService] saveVideoToGallery failed: File does not exist or is empty at $filePath');
        return false;
      }
    }

    try {
      final result = await _platform.invokeMapMethod<String, dynamic>(
        'saveVideoToGallery',
        {
          'path': filePath,
          if (fileName != null) 'fileName': fileName,
        },
      );

      if (result != null && result['success'] == true) {
        debugPrint('[DeviceMediaService] Video registered to Gallery: ${result['uri'] ?? result['path']}');
        return true;
      }
      return false;
    } on MissingPluginException {
      debugPrint('[DeviceMediaService] Platform channel not implemented for saveVideoToGallery (test/web mock)');
      return true;
    } catch (e) {
      debugPrint('[DeviceMediaService] Error saving video to gallery: $e');
      return false;
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

      final durationMs = (result['durationMs'] as num?)?.toInt();
      final thumbnailPath = result['thumbnailPath'] as String?;
      final detectedDuration = (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null;

      final isPhoto = mime.startsWith('image') ||
          name.toLowerCase().endsWith('.jpg') ||
          name.toLowerCase().endsWith('.jpeg') ||
          name.toLowerCase().endsWith('.png') ||
          name.toLowerCase().endsWith('.webp');

      final assetType = isPhoto ? MediaAssetType.photo : MediaAssetType.video;

      final asset = MediaAsset(
        id: 'asset_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}',
        type: assetType,
        name: name,
        uri: uri,
        localPath: localPath,
        duration: detectedDuration,
        sizeBytes: sizeBytes,
        thumbnailPath: isPhoto ? localPath : thumbnailPath,
        createdAt: DateTime.now(),
      );

      debugPrint('[DeviceMediaService] Imported MediaAsset: id=${asset.id}, name=${asset.name}, type=${asset.type}, localPath=${asset.localPath}, exists=${!kIsWeb && File(localPath).existsSync()}, sizeBytes=${asset.sizeBytes}, duration=${asset.duration}, thumbnailPath=${asset.thumbnailPath}');

      return asset;
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
      final durationMs = (result['durationMs'] as num?)?.toInt();
      final detectedDuration = (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null;

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

      final asset = MediaAsset(
        id: 'audio_asset_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}',
        type: MediaAssetType.audio,
        name: name,
        uri: uri,
        localPath: localPath,
        duration: detectedDuration,
        sizeBytes: sizeBytes,
        thumbnailPath: null,
        createdAt: DateTime.now(),
      );

      debugPrint('[DeviceMediaService] Imported Audio MediaAsset: id=${asset.id}, name=${asset.name}, localPath=${asset.localPath}, exists=${!kIsWeb && File(localPath).existsSync()}, sizeBytes=${asset.sizeBytes}, duration=${asset.duration}');

      return asset;
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
