import 'package:flutter/services.dart';

/// Centralized, Reusable Text-To-Speech (TTS) Service for Mahmas Studio
///
/// Features:
/// - Application-wide centralized voice feedback and accessibility announcements
/// - User toggleable (Default: ON, can be set to OFF in settings)
/// - Safe platform abstraction (works across Android, Desktop, Web, and Unit tests)
class TtsService {
  TtsService._();

  static const MethodChannel _channel = MethodChannel('com.mahmas.studio/tts');

  /// Global TTS toggle (Default: ON as per requirement)
  static bool _isEnabled = true;

  /// Returns true if TTS voice announcements are active
  static bool get isEnabled => _isEnabled;

  /// Updates TTS enabled state
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Toggles TTS state between ON and OFF
  static bool toggle() {
    _isEnabled = !_isEnabled;
    if (_isEnabled) {
      speak('Voice feedback enabled');
    }
    return _isEnabled;
  }

  /// Speaks text aloud if TTS is enabled
  static Future<void> speak(String text) async {
    if (!_isEnabled || text.trim().isEmpty) return;

    try {
      await _channel.invokeMethod('speak', {'text': text});
    } catch (_) {
      // Graceful fallback on Desktop / Web / Unit test environments without engine bindings
    }
  }

  /// Speaks an important user action confirmation (e.g. import, trim, split, delete)
  static Future<void> announce(String action) async {
    await speak(action);
  }

  /// Speaks an error notification
  static Future<void> announceError(String errorMessage) async {
    await speak('Notice: $errorMessage');
  }

  /// Stops any currently speaking TTS utterance
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
