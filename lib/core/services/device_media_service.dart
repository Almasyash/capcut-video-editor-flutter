import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeviceMediaResult {
  final String fileName;
  final String filePath; // Actual content:// URI or filesystem path
  final String fileType; // 'video', 'photo', 'audio'
  final Duration estimatedDuration;
  final List<Color> gradient;
  final IconData icon;
  final int fileSizeMb;

  const DeviceMediaResult({
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.estimatedDuration,
    required this.gradient,
    required this.icon,
    this.fileSizeMb = 14,
  });
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

  /// Launches native system file picker intent (ACTION_GET_CONTENT) to pick actual video or photo from device
  static Future<DeviceMediaResult?> pickMediaFromNativeStorage({String type = 'media'}) async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>(
        'pickMediaFile',
        {'type': type},
      );

      if (result != null && result['uri'] != null) {
        final uri = result['uri'] as String;
        final name = (result['name'] as String?) ?? 'Selected_Media';
        final mime = (result['mimeType'] as String?) ?? '';
        final sizeBytes = (result['size'] as num?)?.toInt() ?? 0;
        final sizeMb = (sizeBytes / (1024 * 1024)).ceil();

        final isPhoto = mime.startsWith('image') ||
            name.toLowerCase().endsWith('.jpg') ||
            name.toLowerCase().endsWith('.jpeg') ||
            name.toLowerCase().endsWith('.png') ||
            name.toLowerCase().endsWith('.webp');

        final random = math.Random(name.hashCode);
        final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

        return DeviceMediaResult(
          fileName: name,
          filePath: uri,
          fileType: isPhoto ? 'photo' : 'video',
          estimatedDuration: isPhoto ? const Duration(seconds: 4) : const Duration(seconds: 12),
          gradient: gradient,
          icon: isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
          fileSizeMb: math.max(1, sizeMb),
        );
      }
    } on MissingPluginException {
      // Fallback for Web/desktop test environments
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Launches native system file picker intent to pick actual audio file from device
  static Future<DeviceMediaResult?> pickAudioFromNativeStorage() async {
    try {
      await requestStoragePermissions();

      final result = await _platform.invokeMapMethod<String, dynamic>('pickAudioFile');

      if (result != null && result['uri'] != null) {
        final uri = result['uri'] as String;
        final name = (result['name'] as String?) ?? 'Selected_Audio';
        final sizeBytes = (result['size'] as num?)?.toInt() ?? 0;
        final sizeMb = (sizeBytes / (1024 * 1024)).ceil();

        final random = math.Random(name.hashCode);
        final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

        return DeviceMediaResult(
          fileName: name,
          filePath: uri,
          fileType: 'audio',
          estimatedDuration: const Duration(seconds: 28),
          gradient: gradient,
          icon: Icons.music_note_rounded,
          fileSizeMb: math.max(1, sizeMb),
        );
      }
    } on MissingPluginException {
      // Fallback for Web/desktop test environments
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Creates custom video result with file attributes
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
      filePath: customPath ?? 'content://media/external/video/media/$formattedName',
      fileType: 'video',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.videocam_rounded,
      fileSizeMb: sizeMb,
    );
  }

  /// Creates custom photo result
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
      filePath: customPath ?? 'content://media/external/images/media/$formattedName',
      fileType: 'photo',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.image_rounded,
      fileSizeMb: sizeMb,
    );
  }

  /// Creates custom audio result
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
      filePath: customPath ?? 'content://media/external/audio/media/$formattedName',
      fileType: 'audio',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.music_note_rounded,
      fileSizeMb: sizeMb,
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
