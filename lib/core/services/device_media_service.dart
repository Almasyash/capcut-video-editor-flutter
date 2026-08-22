import 'dart:math' as math;
import 'package:flutter/material.dart';

class DeviceMediaResult {
  final String fileName;
  final String filePath;
  final String fileType; // 'video', 'photo', 'audio'
  final Duration estimatedDuration;
  final List<Color> gradient;
  final IconData icon;

  const DeviceMediaResult({
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.estimatedDuration,
    required this.gradient,
    required this.icon,
  });
}

/// Service to handle selecting and uploading media files from the user's device
class DeviceMediaService {
  DeviceMediaService._();

  static const List<List<Color>> _vibrantGradients = [
    [Color(0xFF00C9FF), Color(0xFF92FE9D)],
    [Color(0xFFFC466B), Color(0xFF3F5EFB)],
    [Color(0xFFFF512F), Color(0xFFDD2476)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
    [Color(0xFF00E5FF), Color(0xFF7928CA)],
    [Color(0xFFFF8008), Color(0xFFFFC837)],
  ];

  /// Simulates picking video from device with realistic file attributes
  static DeviceMediaResult createCustomVideoResult({
    required String name,
    Duration duration = const Duration(seconds: 12),
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

    return DeviceMediaResult(
      fileName: name.endsWith('.mp4') ? name : '$name.mp4',
      filePath: '/storage/emulated/0/DCIM/Camera/$name.mp4',
      fileType: 'video',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.videocam_rounded,
    );
  }

  /// Simulates picking photo from device
  static DeviceMediaResult createCustomPhotoResult({
    required String name,
    Duration duration = const Duration(seconds: 4),
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

    return DeviceMediaResult(
      fileName: name.endsWith('.jpg') ? name : '$name.jpg',
      filePath: '/storage/emulated/0/DCIM/Pictures/$name.jpg',
      fileType: 'photo',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.image_rounded,
    );
  }

  /// Simulates picking audio from device
  static DeviceMediaResult createCustomAudioResult({
    required String name,
    Duration duration = const Duration(seconds: 25),
  }) {
    final random = math.Random(name.hashCode);
    final gradient = _vibrantGradients[random.nextInt(_vibrantGradients.length)];

    return DeviceMediaResult(
      fileName: name.endsWith('.mp3') ? name : '$name.mp3',
      filePath: '/storage/emulated/0/Music/$name.mp3',
      fileType: 'audio',
      estimatedDuration: duration,
      gradient: gradient,
      icon: Icons.music_note_rounded,
    );
  }
}
