import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/services/transition_registry.dart';

/// Manages loading, caching, and serving compiled Flutter [FragmentProgram]s
/// for GPU video transition shaders.
class TransitionShaderManager {
  static final TransitionShaderManager _instance = TransitionShaderManager._internal();
  factory TransitionShaderManager() => _instance;
  TransitionShaderManager._internal();

  final Map<String, FragmentProgram> _cache = {};
  bool _isPreloading = false;
  bool _isPreloaded = false;

  bool get isPreloaded => _isPreloaded;

  /// Preloads all GLSL transition shaders declared in [TransitionRegistry].
  Future<void> preloadAll() async {
    if (_isPreloading || _isPreloaded) return;
    _isPreloading = true;

    for (final def in TransitionRegistry.allDefinitions) {
      final path = def.shaderPath;
      if (path != null && !_cache.containsKey(path)) {
        try {
          final program = await FragmentProgram.fromAsset(path);
          _cache[path] = program;
        } catch (e) {
          debugPrint('[TransitionShaderManager] Could not load shader $path: $e');
        }
      }
    }

    _isPreloading = false;
    _isPreloaded = true;
  }

  /// Returns the cached [FragmentProgram] for a [type], or null if not yet loaded
  /// or if shaders are not supported in the current runtime environment.
  FragmentProgram? getProgram(TransitionType type) {
    final path = type.shaderAssetPath;
    if (path == null) return null;
    return _cache[path];
  }

  /// Manually registers a compiled program (useful for testing or custom assets).
  void registerProgram(String assetPath, FragmentProgram program) {
    _cache[assetPath] = program;
  }

  /// Clears the shader cache.
  void clear() {
    _cache.clear();
    _isPreloaded = false;
  }
}
