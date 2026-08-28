import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents an active native video playback session attached to a Flutter texture.
class VideoPlayerSession {
  final int textureId;
  final Duration duration;
  final int width;
  final int height;
  final String path;
  bool isPlaying;
  bool isDisposed;

  VideoPlayerSession({
    required this.textureId,
    required this.duration,
    required this.width,
    required this.height,
    required this.path,
    this.isPlaying = false,
    this.isDisposed = false,
  });

  double get aspectRatio => (width > 0 && height > 0) ? (width / height) : 16 / 9;
  bool get isInitialized => textureId >= 0 && !isDisposed;
}

/// Centralized service managing native hardware-accelerated video decoding
/// and MP4 audio playback via Flutter Texture and platform channels.
class VideoPlaybackService {
  static const MethodChannel _channel = MethodChannel('com.mahmas.studio/video_player');
  static VideoPlaybackService? _instance;
  static VideoPlaybackService get instance => _instance ??= VideoPlaybackService._();

  VideoPlaybackService._();

  final Map<int, VideoPlayerSession> _sessions = {};
  VideoPlayerSession? _activeSession;
  VideoPlayerSession? get activeSession => _activeSession;

  /// Initializes a hardware-accelerated playback session for [localPath].
  Future<VideoPlayerSession?> createSession(String localPath) async {
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      return null;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('init', {
        'path': localPath,
      });

      if (result != null && result.containsKey('textureId')) {
        final textureId = (result['textureId'] as num).toInt();
        final durationMs = (result['durationMs'] as num?)?.toInt() ?? 0;
        final width = (result['width'] as num?)?.toInt() ?? 1920;
        final height = (result['height'] as num?)?.toInt() ?? 1080;

        final session = VideoPlayerSession(
          textureId: textureId,
          duration: Duration(milliseconds: durationMs),
          width: width,
          height: height,
          path: localPath,
        );

        _sessions[textureId] = session;
        _activeSession = session;
        debugPrint('[VideoPlaybackService] Initialized session textureId: $textureId ($width x $height, ${durationMs}ms) for $localPath');
        return session;
      }
    } catch (e) {
      debugPrint('[VideoPlaybackService] createSession failed for $localPath: $e');
    }
    return null;
  }

  /// Starts playback of video frames and native audio track.
  Future<void> play(int textureId) async {
    try {
      await _channel.invokeMethod('play', {'textureId': textureId});
      final session = _sessions[textureId];
      if (session != null) {
        session.isPlaying = true;
      }
    } catch (e) {
      debugPrint('[VideoPlaybackService] play failed: $e');
    }
  }

  /// Pauses playback of video frames and audio track.
  Future<void> pause(int textureId) async {
    try {
      await _channel.invokeMethod('pause', {'textureId': textureId});
      final session = _sessions[textureId];
      if (session != null) {
        session.isPlaying = false;
      }
    } catch (e) {
      debugPrint('[VideoPlaybackService] pause failed: $e');
    }
  }

  /// Seeks the native decoder to [position].
  Future<void> seekTo(int textureId, Duration position) async {
    try {
      await _channel.invokeMethod('seekTo', {
        'textureId': textureId,
        'positionMs': position.inMilliseconds,
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] seekTo failed: $e');
    }
  }

  /// Sets audio playback volume (0.0 to 1.0).
  Future<void> setVolume(int textureId, double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {
        'textureId': textureId,
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] setVolume failed: $e');
    }
  }

  /// Sets hardware-accelerated video & audio playback speed (0.25x to 4.0x).
  Future<void> setSpeed(int textureId, double speed) async {
    try {
      await _channel.invokeMethod('setSpeed', {
        'textureId': textureId,
        'speed': speed.clamp(0.25, 4.0),
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] setSpeed failed: $e');
    }
  }

  /// Sets playback looping mode.
  Future<void> setLooping(int textureId, bool looping) async {
    try {
      await _channel.invokeMethod('setLooping', {
        'textureId': textureId,
        'looping': looping,
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] setLooping failed: $e');
    }
  }

  /// Disposes the native player and releases the texture entry.
  Future<void> disposeSession(int textureId) async {
    try {
      await _channel.invokeMethod('dispose', {'textureId': textureId});
      final session = _sessions.remove(textureId);
      if (session != null) {
        session.isDisposed = true;
      }
      if (_activeSession?.textureId == textureId) {
        _activeSession = null;
      }
      debugPrint('[VideoPlaybackService] Disposed session textureId: $textureId');
    } catch (e) {
      debugPrint('[VideoPlaybackService] dispose failed: $e');
    }
  }

  /// Disposes all active playback sessions.
  Future<void> disposeAll() async {
    for (final textureId in _sessions.keys.toList()) {
      await disposeSession(textureId);
    }
  }
}
