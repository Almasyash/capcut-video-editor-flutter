import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Represents a position and lifecycle event emitted from the authoritative native video decoder.
class VideoPositionEvent {
  final int textureId;
  final Duration position;
  final Duration duration;
  final bool isCompleted;

  const VideoPositionEvent({
    required this.textureId,
    required this.position,
    required this.duration,
    this.isCompleted = false,
  });

  @override
  String toString() =>
      'VideoPositionEvent(textureId: $textureId, pos: ${position.inMilliseconds}ms, dur: ${duration.inMilliseconds}ms, isCompleted: $isCompleted)';
}

/// Represents an active native video playback session attached to a Flutter texture.
class VideoPlayerSession {
  final int textureId;
  final Duration duration;
  final int width;
  final int height;
  final String path;
  bool isPlaying;
  bool isDisposed;
  Duration currentPosition;

  VideoPlayerSession({
    required this.textureId,
    required this.duration,
    required this.width,
    required this.height,
    required this.path,
    this.isPlaying = false,
    this.isDisposed = false,
    this.currentPosition = Duration.zero,
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

  final _positionEventController = StreamController<VideoPositionEvent>.broadcast(sync: true);
  Stream<VideoPositionEvent> get onPositionChanged => _positionEventController.stream;

  final _completionEventController = StreamController<VideoPositionEvent>.broadcast(sync: true);
  Stream<VideoPositionEvent> get onCompletion => _completionEventController.stream;

  VideoPlaybackService._() {
    _initChannelHandler();
  }

  void _initChannelHandler() {
    try {
      _channel.setMethodCallHandler(_handlePlatformCall);
    } catch (_) {
      // Ignored in headless unit test environments where BinaryMessenger is not yet initialized
    }
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPositionUpdate':
        final textureId = (call.arguments['textureId'] as num).toInt();
        final positionMs = (call.arguments['positionMs'] as num).toInt();
        final durationMs = (call.arguments['durationMs'] as num).toInt();
        final session = _sessions[textureId];
        if (session != null) {
          session.currentPosition = Duration(milliseconds: positionMs);
        }
        final event = VideoPositionEvent(
          textureId: textureId,
          position: Duration(milliseconds: positionMs),
          duration: Duration(milliseconds: durationMs),
          isCompleted: false,
        );
        _positionEventController.add(event);
        break;
      case 'onCompletion':
        final textureId = (call.arguments['textureId'] as num).toInt();
        final positionMs = (call.arguments['positionMs'] as num).toInt();
        final durationMs = (call.arguments['durationMs'] as num).toInt();
        final session = _sessions[textureId];
        if (session != null) {
          session.isPlaying = false;
          session.currentPosition = Duration(milliseconds: positionMs);
        }
        final event = VideoPositionEvent(
          textureId: textureId,
          position: Duration(milliseconds: positionMs),
          duration: Duration(milliseconds: durationMs),
          isCompleted: true,
        );
        _completionEventController.add(event);
        _positionEventController.add(event);
        break;
    }
  }

  final Map<int, VideoPlayerSession> _sessions = {};
  final Map<int, VideoPlayerController> _windowsControllers = {};
  VideoPlayerController? getWindowsController(int textureId) => _windowsControllers[textureId];
  VideoPlayerSession? _activeSession;
  VideoPlayerSession? get activeSession => _activeSession;

  /// Manually emit a simulated position event (used for headless test environments)
  void emitSimulatedPosition(
    int textureId,
    Duration position, [
    Duration? duration,
    bool isCompleted = false,
  ]) {
    final dur = duration ?? _sessions[textureId]?.duration ?? position;
    final event = VideoPositionEvent(
      textureId: textureId,
      position: position,
      duration: dur,
      isCompleted: isCompleted,
    );
    final session = _sessions[textureId];
    if (session != null) {
      session.currentPosition = position;
      if (isCompleted) {
        session.isPlaying = false;
      }
    }
    if (isCompleted) {
      _completionEventController.add(event);
    }
    _positionEventController.add(event);
  }

  /// Emits a simulated completion event (used for headless test environments)
  void emitSimulatedCompletion(int textureId, Duration position, [Duration? duration]) {
    emitSimulatedPosition(textureId, position, duration, true);
  }

  /// Registers a simulated session (for headless widget and unit tests)
  VideoPlayerSession registerSimulatedSession(
    int textureId,
    String path,
    Duration duration, {
    int width = 1920,
    int height = 1080,
  }) {
    final session = VideoPlayerSession(
      textureId: textureId,
      duration: duration,
      width: width,
      height: height,
      path: path,
    );
    _sessions[textureId] = session;
    _activeSession = session;
    return session;
  }

  /// Initializes a hardware-accelerated playback session for [localPath].
  Future<VideoPlayerSession?> createSession(String localPath) async {
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      return null;
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        final controller = VideoPlayerController.file(File(localPath));
        await controller.initialize();

        // Windows warm-up: trigger Media Foundation grabber to paint frame 0
        // into the texture so the viewport is not black while paused at start.
        try {
          await controller.play();
          await Future.delayed(const Duration(milliseconds: 80));
          await controller.pause();
          await controller.seekTo(Duration.zero);
        } catch (_) {
          // Ignore warm-up failures; playback will still work
        }

        // ignore: invalid_use_of_visible_for_testing_member
        final textureId = controller.textureId;
        final duration = controller.value.duration;
        final width = controller.value.size.width.toInt();
        final height = controller.value.size.height.toInt();

        final session = VideoPlayerSession(
          textureId: textureId,
          duration: duration,
          width: width > 0 ? width : 1920,
          height: height > 0 ? height : 1080,
          path: localPath,
        );

        _windowsControllers[textureId] = controller;
        _sessions[textureId] = session;
        _activeSession = session;

        controller.addListener(() {
          if (!_sessions.containsKey(textureId)) return;
          final currentPos = controller.value.position;
          session.currentPosition = currentPos;
          session.isPlaying = controller.value.isPlaying;

          final isCompleted = controller.value.isCompleted ||
              (duration > Duration.zero && currentPos >= duration);

          final event = VideoPositionEvent(
            textureId: textureId,
            position: currentPos,
            duration: duration,
            isCompleted: isCompleted,
          );

          if (isCompleted) {
            session.isPlaying = false;
            _completionEventController.add(event);
          }
          _positionEventController.add(event);
        });

        debugPrint('[VideoPlaybackService] Windows initialized session textureId: $textureId ($width x $height, ${duration.inMilliseconds}ms) for $localPath');
        return session;
      } catch (e, st) {
        debugPrint('[VideoPlaybackService] Windows createSession failed for $localPath: $e\n$st');
        return null;
      }
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

  /// Queries the authoritative native player position
  Future<Duration?> getPosition(int textureId) async {
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        final pos = controller.value.position;
        final session = _sessions[textureId];
        if (session != null) {
          session.currentPosition = pos;
        }
        return pos;
      }
      return _sessions[textureId]?.currentPosition;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getPosition', {
        'textureId': textureId,
      });
      if (result != null && result.containsKey('positionMs')) {
        final posMs = (result['positionMs'] as num).toInt();
        final pos = Duration(milliseconds: posMs);
        final session = _sessions[textureId];
        if (session != null) {
          session.currentPosition = pos;
        }
        return pos;
      }
    } catch (e) {
      debugPrint('[VideoPlaybackService] getPosition failed: $e');
    }
    return _sessions[textureId]?.currentPosition;
  }

  /// Starts playback of video frames and native audio track at optional [position].
  Future<void> play(int textureId, {Duration? position}) async {
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        debugPrint('[AUTO_PLAY_TRACE] Windows VideoPlaybackService.play($textureId, pos=${position?.inMilliseconds}ms)');
        if (position != null) {
          await controller.seekTo(position);
        }
        await controller.play();
        final session = _sessions[textureId];
        if (session != null) {
          session.isPlaying = true;
        }
        return;
      }
    }

    try {
      debugPrint('[AUTO_PLAY_TRACE] VIDEO START CALLED: VideoPlaybackService.play($textureId, pos=${position?.inMilliseconds}ms)');
      await _channel.invokeMethod('play', {
        'textureId': textureId,
        if (position != null) 'positionMs': position.inMilliseconds,
      });
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
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        debugPrint('[AUTO_PLAY_TRACE] Windows VideoPlaybackService.pause($textureId)');
        await controller.pause();
        final session = _sessions[textureId];
        if (session != null) {
          session.isPlaying = false;
        }
        return;
      }
    }

    try {
      debugPrint('[AUTO_PLAY_TRACE] VideoPlaybackService.pause($textureId)');
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
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        await controller.seekTo(position);
        final session = _sessions[textureId];
        if (session != null) {
          session.currentPosition = position;
        }
        return;
      }
    }

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
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        await controller.setVolume(volume.clamp(0.0, 1.0));
        return;
      }
    }

    try {
      await _channel.invokeMethod('setVolume', {
        'textureId': textureId,
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] setVolume failed: $e');
    }
  }

  /// Sets hardware-accelerated video & audio playback speed (0.1x to 100.0x).
  Future<void> setSpeed(int textureId, double speed) async {
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        await controller.setPlaybackSpeed(speed.clamp(0.1, 100.0));
        return;
      }
    }

    try {
      await _channel.invokeMethod('setSpeed', {
        'textureId': textureId,
        'speed': speed.clamp(0.1, 100.0),
      });
    } catch (e) {
      debugPrint('[VideoPlaybackService] setSpeed failed: $e');
    }
  }

  /// Sets playback looping mode.
  Future<void> setLooping(int textureId, bool looping) async {
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers[textureId];
      if (controller != null) {
        await controller.setLooping(looping);
        return;
      }
    }

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
    if (!kIsWeb && Platform.isWindows) {
      final controller = _windowsControllers.remove(textureId);
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (e) {
          debugPrint('[VideoPlaybackService] controller.dispose failed: $e');
        }
      }
      final session = _sessions.remove(textureId);
      if (session != null) {
        session.isDisposed = true;
      }
      if (_activeSession?.textureId == textureId) {
        _activeSession = null;
      }
      debugPrint('[VideoPlaybackService] Windows Disposed session textureId: $textureId');
      return;
    }

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
