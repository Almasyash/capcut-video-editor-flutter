import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';

/// Centralized persistent storage and metadata registry for downloaded online assets
class AssetStorageService {
  AssetStorageService._();
  static final AssetStorageService instance = AssetStorageService._();

  static const MethodChannel _platform = MethodChannel('com.mahmas.studio/file_picker');

  String? _cachedAssetDir;
  final Map<String, Asset> _registry = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Retrieves the root directory for permanent asset storage
  Future<String> getAssetStorageDirectory() async {
    if (_cachedAssetDir != null) return _cachedAssetDir!;

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

    final assetDir = Directory('$basePath/asset_library');
    if (!assetDir.existsSync()) {
      try {
        assetDir.createSync(recursive: true);
      } catch (e) {
        debugPrint('[AssetStorageService] Error creating asset directory: $e');
      }
    }

    _cachedAssetDir = assetDir.path;
    return _cachedAssetDir!;
  }

  /// Initializes the local asset registry from the persistent manifest file
  Future<void> initialize() async {
    if (_isInitialized) return;

    _registry.clear();
    try {
      final dirPath = await getAssetStorageDirectory();
      final manifestFile = File('$dirPath/downloaded_assets.json');

      if (manifestFile.existsSync()) {
        final content = await manifestFile.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          for (final item in jsonList) {
            try {
              final asset = Asset.fromJson(item as Map<String, dynamic>);
              if (asset.localPath != null && File(asset.localPath!).existsSync()) {
                _registry[asset.id] = asset.copyWith(isDownloaded: true);
              }
            } catch (e) {
              debugPrint('[AssetStorageService] Corrupt asset record in manifest: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AssetStorageService] Initialize error: $e');
    }

    _isInitialized = true;
    debugPrint('[AssetStorageService] Initialized with ${_registry.length} downloaded assets');
  }

  /// Persists the current registry to the manifest file on disk
  Future<void> _saveManifest() async {
    try {
      final dirPath = await getAssetStorageDirectory();
      final manifestFile = File('$dirPath/downloaded_assets.json');
      final data = _registry.values.map((a) => a.toJson()).toList();
      await manifestFile.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[AssetStorageService] Failed to save manifest: $e');
    }
  }

  /// Returns all registered downloaded assets, optionally filtered by type
  Future<List<Asset>> getAllDownloadedAssets({AssetType? type}) async {
    if (!_isInitialized) await initialize();

    // Verify files still exist on disk
    final List<String> missing = [];
    final List<Asset> result = [];

    for (final entry in _registry.entries) {
      final asset = entry.value;
      if (asset.localPath != null && File(asset.localPath!).existsSync()) {
        if (type == null || asset.type == type) {
          result.add(asset);
        }
      } else {
        missing.add(entry.key);
      }
    }

    if (missing.isNotEmpty) {
      for (final id in missing) {
        _registry.remove(id);
      }
      await _saveManifest();
    }

    return result;
  }

  /// Checks if an asset is downloaded and physically present on disk
  Future<bool> isAssetDownloaded(String assetId) async {
    if (!_isInitialized) await initialize();
    return isAssetDownloadedSync(assetId);
  }

  /// Synchronous check if an asset is in memory registry and physically present
  bool isAssetDownloadedSync(String assetId) {
    final asset = _registry[assetId];
    if (asset == null || asset.localPath == null) return false;
    return File(asset.localPath!).existsSync();
  }

  /// Retrieves local file path for a downloaded asset
  Future<String?> getLocalPath(String assetId) async {
    if (!_isInitialized) await initialize();
    return getLocalPathSync(assetId);
  }

  /// Synchronous retrieval of local file path
  String? getLocalPathSync(String assetId) {
    final asset = _registry[assetId];
    if (asset != null && asset.localPath != null && File(asset.localPath!).existsSync()) {
      return asset.localPath;
    }
    return null;
  }

  /// Retrieves full metadata for a downloaded asset
  Future<Asset?> getDownloadedAsset(String assetId) async {
    if (!_isInitialized) await initialize();
    return getDownloadedAssetSync(assetId);
  }

  /// Synchronous retrieval of downloaded asset metadata
  Asset? getDownloadedAssetSync(String assetId) {
    final asset = _registry[assetId];
    if (asset != null && asset.localPath != null && File(asset.localPath!).existsSync()) {
      return asset;
    }
    return null;
  }

  /// Registers a newly downloaded asset
  Future<void> saveDownloadedAsset(Asset asset, String localPath) async {
    if (!_isInitialized) await initialize();

    final downloadedAsset = asset.copyWith(
      isDownloaded: true,
      localPath: localPath,
      downloadedAt: DateTime.now(),
    );

    _registry[asset.id] = downloadedAsset;
    await _saveManifest();
    debugPrint('[AssetStorageService] Registered asset ${asset.id} at $localPath');
  }

  /// Deletes a downloaded asset from disk and unregisters it from the manifest
  Future<bool> deleteDownloadedAsset(String assetId) async {
    if (!_isInitialized) await initialize();

    final asset = _registry[assetId];
    if (asset == null) return false;

    try {
      if (asset.localPath != null) {
        final file = File(asset.localPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[AssetStorageService] Error deleting file for $assetId: $e');
    }

    _registry.remove(assetId);
    await _saveManifest();
    debugPrint('[AssetStorageService] Deleted asset $assetId');
    return true;
  }

  /// Clears all downloaded assets and manifests (e.g. for testing/reset)
  Future<void> clearAll() async {
    if (!_isInitialized) await initialize();

    for (final asset in _registry.values) {
      if (asset.localPath != null) {
        try {
          final file = File(asset.localPath!);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }

    _registry.clear();
    await _saveManifest();
  }
}
