import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:capcut_video_editor/core/services/asset_download_service.dart';
import 'package:capcut_video_editor/core/services/asset_storage_service.dart';
import 'package:capcut_video_editor/core/services/audio_playback_service.dart';
import 'package:capcut_video_editor/data/repositories/asset_repository.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';

/// Orchestrator service coordinating asset browsing, searching, previewing, and downloads
class AssetLibraryService with ChangeNotifier {
  static final AssetLibraryService instance = AssetLibraryService._();
  AssetLibraryService._();

  final RemoteAssetRepository _remoteRepo = RemoteAssetRepository();
  final LocalAssetRepository _localRepo = LocalAssetRepository();
  final AssetDownloadService _downloadService = AssetDownloadService.instance;
  final AssetStorageService _storageService = AssetStorageService.instance;

  AssetType _selectedType = AssetType.soundEffect;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _onlyDownloaded = false;
  bool _isOffline = false;
  bool _isLoading = false;
  String? _errorMessage;

  List<Asset> _assets = [];
  List<String> _categories = ['All'];
  String? _previewingAssetId;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  AssetType get selectedType => _selectedType;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get onlyDownloaded => _onlyDownloaded;
  bool get isOffline => _isOffline;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Asset> get assets => List.unmodifiable(_assets);
  List<String> get categories => List.unmodifiable(_categories);
  String? get previewingAssetId => _previewingAssetId;

  Future<void> initialize() async {
    await _storageService.initialize();

    _downloadSubscription?.cancel();
    _downloadSubscription = _downloadService.progressStream.listen((progress) {
      // Update download status in the asset list
      final index = _assets.indexWhere((a) => a.id == progress.assetId);
      if (index != -1) {
        if (progress.state == DownloadState.downloaded) {
          _storageService.getLocalPath(progress.assetId).then((path) {
            if (index < _assets.length && _assets[index].id == progress.assetId) {
              _assets[index] = _assets[index].copyWith(
                isDownloaded: true,
                localPath: path,
              );
              notifyListeners();
            }
          });
        } else {
          notifyListeners();
        }
      }
    });

    await refresh();
  }

  void setAssetType(AssetType type) {
    if (_selectedType != type) {
      _selectedType = type;
      _selectedCategory = 'All';
      refresh();
    }
  }

  void setCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      refresh();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    refresh();
  }

  void setOnlyDownloaded(bool value) {
    if (_onlyDownloaded != value) {
      _onlyDownloaded = value;
      refresh();
    }
  }

  void setOfflineMode(bool offline) {
    _isOffline = offline;
    refresh();
  }

  /// Reloads categories and assets according to current filters
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_onlyDownloaded || _isOffline) {
        _categories = await _localRepo.getCategories(_selectedType);
        _assets = await _localRepo.getAssets(
          type: _selectedType,
          category: _selectedCategory,
          searchQuery: _searchQuery,
        );
      } else {
        try {
          _categories = await _remoteRepo.getCategories(_selectedType);
          _assets = await _remoteRepo.getAssets(
            type: _selectedType,
            category: _selectedCategory,
            searchQuery: _searchQuery,
          );
        } catch (netErr) {
          debugPrint('[AssetLibraryService] Remote fetch failed, falling back to local: $netErr');
          _isOffline = true;
          _categories = await _localRepo.getCategories(_selectedType);
          _assets = await _localRepo.getAssets(
            type: _selectedType,
            category: _selectedCategory,
            searchQuery: _searchQuery,
          );
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[AssetLibraryService] Refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Triggers downloading of the specified asset
  Future<String> downloadAsset(Asset asset) async {
    try {
      final path = await _downloadService.downloadAsset(asset);
      await refresh();
      return path;
    } catch (e) {
      debugPrint('[AssetLibraryService] Download failed for ${asset.id}: $e');
      rethrow;
    }
  }

  /// Cancels an in-progress download
  void cancelDownload(String assetId) {
    _downloadService.cancelDownload(assetId);
    notifyListeners();
  }

  /// Deletes a downloaded asset from local storage
  Future<bool> deleteAsset(String assetId) async {
    if (_previewingAssetId == assetId) {
      await stopPreview();
    }
    final success = await _storageService.deleteDownloadedAsset(assetId);
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Plays an audio preview of the sound effect
  Future<void> playPreview(Asset asset) async {
    if (_previewingAssetId == asset.id) {
      await stopPreview();
      return;
    }

    await stopPreview();

    try {
      String? localPath = asset.localPath;
      if (localPath == null || !File(localPath).existsSync()) {
        // If not yet downloaded, obtain temporary preview file
        localPath = await _downloadService.downloadAsset(asset);
      }

      _previewingAssetId = asset.id;
      notifyListeners();

      await AudioPlaybackService.instance.initialize(localPath);
      await AudioPlaybackService.instance.setVolume(1.0);
      await AudioPlaybackService.instance.play();

      // Automatically reset preview state after duration
      Future.delayed(asset.duration, () {
        if (_previewingAssetId == asset.id) {
          _previewingAssetId = null;
          AudioPlaybackService.instance.pause();
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[AssetLibraryService] Preview playback error: $e');
      _previewingAssetId = null;
      notifyListeners();
    }
  }

  /// Stops current preview playback
  Future<void> stopPreview() async {
    if (_previewingAssetId != null) {
      _previewingAssetId = null;
      try {
        await AudioPlaybackService.instance.pause();
      } catch (_) {}
      notifyListeners();
    }
  }

  bool isPreviewing(String assetId) => _previewingAssetId == assetId;

  DownloadProgress? getDownloadProgress(String assetId) => _downloadService.getProgress(assetId);

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }
}
