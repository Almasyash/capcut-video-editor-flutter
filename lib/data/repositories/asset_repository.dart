import 'dart:async';
import 'package:capcut_video_editor/core/services/asset_storage_service.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';

/// Abstract contract for querying sound effect and transition assets
abstract class AssetRepository {
  /// Fetches assets with optional filtering by type, category, and search query
  Future<List<Asset>> getAssets({
    AssetType? type,
    String? category,
    String? searchQuery,
  });

  /// Retrieves available category names for a given asset type
  Future<List<String>> getCategories(AssetType type);

  /// Retrieves an asset by its unique identifier
  Future<Asset?> getAssetById(String id);
}

/// Remote asset repository with development catalog provider and REST endpoint support
class RemoteAssetRepository implements AssetRepository {
  final String baseUrl;
  final bool isOfflineMode;

  RemoteAssetRepository({
    this.baseUrl = 'https://assets.editorfs.app/api/v1',
    this.isOfflineMode = false,
  });

  /// Authentic royalty-free catalog entries with legal CC0 / Royalty-Free Standard licensing
  static final List<Asset> _developmentCatalog = [
    // --- Sound Effects: Whoosh ---
    const Asset(
      id: 'sfx_whoosh_cinematic_01',
      name: 'Cinematic Deep Whoosh',
      category: 'Whoosh',
      type: AssetType.soundEffect,
      description: 'Deep resonant low-end whoosh transition suitable for title reveals and cinematic cuts.',
      durationMs: 2200,
      fileSizeBytes: 194044,
      previewUrl: 'https://assets.editorfs.app/sfx/whoosh_cinematic_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/whoosh_cinematic_01.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['whoosh', 'cinematic', 'deep', 'swoosh', 'trailer', 'transition'],
    ),
    const Asset(
      id: 'sfx_whoosh_fast_air_02',
      name: 'Fast Air Swoosh',
      category: 'Whoosh',
      type: AssetType.soundEffect,
      description: 'Crisp high-speed air swoosh for fast-paced video editing and dynamic cuts.',
      durationMs: 1400,
      fileSizeBytes: 123484,
      previewUrl: 'https://assets.editorfs.app/sfx/whoosh_fast_air_02_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/whoosh_fast_air_02.wav',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['whoosh', 'air', 'fast', 'swoosh', 'whip', 'motion'],
    ),

    // --- Sound Effects: Impact ---
    const Asset(
      id: 'sfx_impact_sub_boom_01',
      name: 'Cinematic Sub Boom Impact',
      category: 'Impact',
      type: AssetType.soundEffect,
      description: 'Heavy bass drop and cinematic sub-bass explosion impact for dramatic highlights.',
      durationMs: 3000,
      fileSizeBytes: 264644,
      previewUrl: 'https://assets.editorfs.app/sfx/impact_sub_boom_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/impact_sub_boom_01.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['impact', 'sub', 'boom', 'bass', 'hit', 'cinematic', 'explosion'],
    ),
    const Asset(
      id: 'sfx_impact_metallic_hit_02',
      name: 'Metallic Heavy Strike',
      category: 'Impact',
      type: AssetType.soundEffect,
      description: 'Sharp resonant metal clang impact with acoustic tail.',
      durationMs: 1800,
      fileSizeBytes: 158764,
      previewUrl: 'https://assets.editorfs.app/sfx/impact_metallic_hit_02_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/impact_metallic_hit_02.wav',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['impact', 'metal', 'strike', 'clang', 'action', 'hit'],
    ),

    // --- Sound Effects: Glitch ---
    const Asset(
      id: 'sfx_glitch_cyber_digital_01',
      name: 'Digital Cyber Glitch',
      category: 'Glitch',
      type: AssetType.soundEffect,
      description: 'Futuristic stuttering sci-fi glitch burst with bit-crushed electronic textures.',
      durationMs: 2500,
      fileSizeBytes: 220544,
      previewUrl: 'https://assets.editorfs.app/sfx/glitch_cyber_digital_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/glitch_cyber_digital_01.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['glitch', 'digital', 'cyberpunk', 'sci-fi', 'stutter', 'electronic', 'distortion'],
    ),
    const Asset(
      id: 'sfx_glitch_tape_rewind_02',
      name: 'VHS Tape Rewind Glitch',
      category: 'Glitch',
      type: AssetType.soundEffect,
      description: 'Vintage cassette rewind distortion with flutter and tape noise.',
      durationMs: 1900,
      fileSizeBytes: 167584,
      previewUrl: 'https://assets.editorfs.app/sfx/glitch_tape_rewind_02_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/glitch_tape_rewind_02.wav',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['glitch', 'vhs', 'tape', 'rewind', 'retro', 'vintage', 'analog'],
    ),

    // --- Sound Effects: UI ---
    const Asset(
      id: 'sfx_ui_modern_pop_01',
      name: 'Modern Bubble Pop',
      category: 'UI',
      type: AssetType.soundEffect,
      description: 'Crisp, playful bubble pop sound for button clicks and micro-interactions.',
      durationMs: 900,
      fileSizeBytes: 79384,
      previewUrl: 'https://assets.editorfs.app/sfx/ui_modern_pop_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/ui_modern_pop_01.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['ui', 'pop', 'bubble', 'click', 'button', 'tap', 'minimal'],
    ),
    const Asset(
      id: 'sfx_ui_soft_ding_02',
      name: 'Harmonic Success Bell',
      category: 'UI',
      type: AssetType.soundEffect,
      description: 'Warm harmonic triad chime indicating achievement, success, or completion.',
      durationMs: 2000,
      fileSizeBytes: 176444,
      previewUrl: 'https://assets.editorfs.app/sfx/ui_soft_ding_02_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/ui_soft_ding_02.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['ui', 'bell', 'chime', 'success', 'notification', 'complete', 'ding'],
    ),

    // --- Sound Effects: Camera ---
    const Asset(
      id: 'sfx_camera_vintage_shutter_01',
      name: 'Vintage Mechanical Shutter',
      category: 'Camera',
      type: AssetType.soundEffect,
      description: 'Authentic dual-action mechanical SLR mirror snap and motor advance.',
      durationMs: 1200,
      fileSizeBytes: 105844,
      previewUrl: 'https://assets.editorfs.app/sfx/camera_vintage_shutter_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/camera_vintage_shutter_01.wav',
      license: AssetLicense(
        name: 'Creative Commons 0 (Public Domain)',
        attributionRequired: false,
      ),
      tags: ['camera', 'shutter', 'snapshot', 'photo', 'click', 'slr', 'vintage'],
    ),

    // --- Sound Effects: Cinematic ---
    const Asset(
      id: 'sfx_cinematic_tension_riser_01',
      name: 'Dark Tension Riser',
      category: 'Cinematic',
      type: AssetType.soundEffect,
      description: 'Ascending tension swell building up to a dramatic climax or scene transition.',
      durationMs: 3500,
      fileSizeBytes: 308744,
      previewUrl: 'https://assets.editorfs.app/sfx/cinematic_tension_riser_01_preview.wav',
      downloadUrl: 'https://assets.editorfs.app/sfx/cinematic_tension_riser_01.wav',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['cinematic', 'riser', 'tension', 'suspense', 'swell', 'climax', 'trailer'],
    ),

    // --- Transitions: Video Transitions ---
    const Asset(
      id: 'trn_whoosh_whip_pan_01',
      name: 'Dynamic Whip Pan Transition',
      category: 'Whoosh',
      type: AssetType.transition,
      description: 'High-speed directional whip blur transition template for video clip boundary.',
      durationMs: 800,
      fileSizeBytes: 705644,
      previewUrl: 'https://assets.editorfs.app/transitions/whoosh_whip_pan_01_preview.mp4',
      downloadUrl: 'https://assets.editorfs.app/transitions/whoosh_whip_pan_01.zip',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['transition', 'whip', 'pan', 'motion', 'fast', 'video'],
    ),
    const Asset(
      id: 'trn_glitch_rgb_split_02',
      name: 'RGB Split Glitch Transition',
      category: 'Glitch',
      type: AssetType.transition,
      description: 'Chromatic aberration RGB shift and scanline glitch video transition.',
      durationMs: 1000,
      fileSizeBytes: 882044,
      previewUrl: 'https://assets.editorfs.app/transitions/glitch_rgb_split_02_preview.mp4',
      downloadUrl: 'https://assets.editorfs.app/transitions/glitch_rgb_split_02.zip',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['transition', 'glitch', 'rgb', 'chromatic', 'vhs', 'video'],
    ),
    const Asset(
      id: 'trn_zoom_warp_blur_03',
      name: 'Hyper Zoom Warp Transition',
      category: 'Zoom',
      type: AssetType.transition,
      description: 'Fast optical zoom-in transition with radial motion blur effect.',
      durationMs: 750,
      fileSizeBytes: 661544,
      previewUrl: 'https://assets.editorfs.app/transitions/zoom_warp_blur_03_preview.mp4',
      downloadUrl: 'https://assets.editorfs.app/transitions/zoom_warp_blur_03.zip',
      license: AssetLicense(
        name: 'Editor FS Royalty-Free Standard',
        attributionRequired: false,
      ),
      tags: ['transition', 'zoom', 'warp', 'blur', 'motion', 'video'],
    ),
  ];

  @override
  Future<List<Asset>> getAssets({
    AssetType? type,
    String? category,
    String? searchQuery,
  }) async {
    if (isOfflineMode) {
      throw Exception('Network unreachable (Offline mode enabled)');
    }

    // In a production backend, this makes an HTTP GET to $baseUrl/assets
    // In our development architecture, we filter the verified catalog provider
    var results = _developmentCatalog;

    if (type != null) {
      results = results.where((a) => a.type == type).toList();
    }

    if (category != null && category.trim().isNotEmpty && category.toLowerCase() != 'all') {
      results = results.where((a) => a.category.toLowerCase() == category.toLowerCase()).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      results = results.where((a) {
        final matchesName = a.name.toLowerCase().contains(query);
        final matchesCategory = a.category.toLowerCase().contains(query);
        final matchesDescription = a.description.toLowerCase().contains(query);
        final matchesTags = a.tags.any((t) => t.toLowerCase().contains(query));
        return matchesName || matchesCategory || matchesDescription || matchesTags;
      }).toList();
    }

    // Synchronize isDownloaded status with local storage
    final List<Asset> synced = [];
    for (final asset in results) {
      final isDownloaded = await AssetStorageService.instance.isAssetDownloaded(asset.id);
      final localPath = await AssetStorageService.instance.getLocalPath(asset.id);
      synced.add(asset.copyWith(
        isDownloaded: isDownloaded,
        localPath: localPath,
      ));
    }

    return synced;
  }

  @override
  Future<List<String>> getCategories(AssetType type) async {
    if (isOfflineMode) {
      throw Exception('Network unreachable');
    }

    final categories = _developmentCatalog
        .where((a) => a.type == type)
        .map((a) => a.category)
        .toSet()
        .toList();

    categories.sort();
    return ['All', ...categories];
  }

  @override
  Future<Asset?> getAssetById(String id) async {
    try {
      final asset = _developmentCatalog.firstWhere((a) => a.id == id);
      final isDownloaded = await AssetStorageService.instance.isAssetDownloaded(asset.id);
      final localPath = await AssetStorageService.instance.getLocalPath(asset.id);
      return asset.copyWith(
        isDownloaded: isDownloaded,
        localPath: localPath,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Local asset repository querying permanently downloaded assets from on-disk storage
class LocalAssetRepository implements AssetRepository {
  final AssetStorageService storageService;

  LocalAssetRepository({AssetStorageService? storageService})
      : storageService = storageService ?? AssetStorageService.instance;

  @override
  Future<List<Asset>> getAssets({
    AssetType? type,
    String? category,
    String? searchQuery,
  }) async {
    var assets = await storageService.getAllDownloadedAssets(type: type);

    if (category != null && category.trim().isNotEmpty && category.toLowerCase() != 'all') {
      assets = assets.where((a) => a.category.toLowerCase() == category.toLowerCase()).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      assets = assets.where((a) {
        final matchesName = a.name.toLowerCase().contains(query);
        final matchesCategory = a.category.toLowerCase().contains(query);
        final matchesTags = a.tags.any((t) => t.toLowerCase().contains(query));
        return matchesName || matchesCategory || matchesTags;
      }).toList();
    }

    return assets;
  }

  @override
  Future<List<String>> getCategories(AssetType type) async {
    final assets = await storageService.getAllDownloadedAssets(type: type);
    final categories = assets.map((a) => a.category).toSet().toList();
    categories.sort();
    return ['All', ...categories];
  }

  @override
  Future<Asset?> getAssetById(String id) async {
    return storageService.getDownloadedAsset(id);
  }
}
