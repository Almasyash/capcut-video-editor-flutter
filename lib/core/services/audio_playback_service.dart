import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized service managing native audio playback of separate imported audio tracks.
class AudioPlaybackService {
  static const MethodChannel _channel = MethodChannel('com.mahmas.studio/audio_player');
  static AudioPlaybackService? _instance;
  static AudioPlaybackService get instance => _instance ??= AudioPlaybackService._();

  AudioPlaybackService._();

  String? _loadedPath;
  Duration _duration = Duration.zero;
  bool _isInitialized = false;
  bool _isPlaying = false;

  String? get loadedPath => _loadedPath;
  Duration get duration => _duration;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;

  /// Initializes the audio player for [localPath].
  Future<bool> initialize(String localPath) async {
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      return false;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('init', {
        'path': localPath,
      });

      if (result != null) {
        final durationMs = (result['durationMs'] as num?)?.toInt() ?? 0;
        _duration = Duration(milliseconds: durationMs);
        _loadedPath = localPath;
        _isInitialized = true;
        _isPlaying = false;
        debugPrint('[AudioPlaybackService] Initialized audio (${durationMs}ms) for $localPath');
        return true;
      }
    } catch (e) {
      debugPrint('[AudioPlaybackService] initialize failed for $localPath: $e');
    }
    return false;
  }

  /// Starts playback of the separate audio track.
  Future<void> play() async {
    if (!_isInitialized) return;
    try {
      debugPrint('[AUTO_PLAY_TRACE] AUDIO START CALLED: AudioPlaybackService.play()');
      await _channel.invokeMethod('play');
      _isPlaying = true;
    } catch (e) {
      debugPrint('[AudioPlaybackService] play failed: $e');
    }
  }

  /// Pauses playback of the separate audio track.
  Future<void> pause() async {
    if (!_isInitialized) return;
    try {
      debugPrint('[AUTO_PLAY_TRACE] AudioPlaybackService.pause()');
      await _channel.invokeMethod('pause');
      _isPlaying = false;
    } catch (e) {
      debugPrint('[AudioPlaybackService] pause failed: $e');
    }
  }

  /// Seeks to [position] in the audio track.
  Future<void> seekTo(Duration position) async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('seekTo', {
        'positionMs': position.inMilliseconds,
      });
    } catch (e) {
      debugPrint('[AudioPlaybackService] seekTo failed: $e');
    }
  }

  /// Sets playback volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('setVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      debugPrint('[AudioPlaybackService] setVolume failed: $e');
    }
  }

  /// Sets playback speed (0.25 to 4.0).
  Future<void> setSpeed(double speed) async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('setSpeed', {
        'speed': speed.clamp(0.25, 4.0),
      });
    } catch (e) {
      debugPrint('[AudioPlaybackService] setSpeed failed: $e');
    }
  }

  /// Disposes the native audio player.
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
      _isInitialized = false;
      _isPlaying = false;
      _loadedPath = null;
      debugPrint('[AudioPlaybackService] Disposed audio session');
    } catch (e) {
      debugPrint('[AudioPlaybackService] dispose failed: $e');
    }
  }
}
