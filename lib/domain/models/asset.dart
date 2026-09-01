/// Represents the type of asset in the online library
enum AssetType {
  soundEffect,
  transition;

  String get displayName {
    switch (this) {
      case AssetType.soundEffect:
        return 'Sound Effect';
      case AssetType.transition:
        return 'Transition';
    }
  }
}

/// Represents download lifecycle state
enum DownloadState {
  notDownloaded,
  downloading,
  downloaded,
  failed,
  cancelled;

  bool get isDownloaded => this == DownloadState.downloaded;
  bool get isDownloading => this == DownloadState.downloading;
}

/// Real-time download progress model
class DownloadProgress {
  final String assetId;
  final DownloadState state;
  final double progress; // 0.0 to 1.0
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;

  const DownloadProgress({
    required this.assetId,
    required this.state,
    this.progress = 0.0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  DownloadProgress copyWith({
    DownloadState? state,
    double? progress,
    int? bytesDownloaded,
    int? totalBytes,
    String? errorMessage,
  }) {
    return DownloadProgress(
      assetId: assetId,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Licensing and attribution metadata
class AssetLicense {
  final String name;
  final bool attributionRequired;
  final String? attributionText;

  const AssetLicense({
    required this.name,
    this.attributionRequired = false,
    this.attributionText,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'attributionRequired': attributionRequired,
    if (attributionText != null) 'attributionText': attributionText,
  };

  factory AssetLicense.fromJson(Map<String, dynamic> json) => AssetLicense(
    name: json['name'] as String? ?? 'Royalty-Free Standard',
    attributionRequired: json['attributionRequired'] as bool? ?? false,
    attributionText: json['attributionText'] as String?,
  );
}

/// Core domain entity for downloadable online sound effects and transitions
class Asset {
  final String id;
  final String name;
  final String category;
  final AssetType type;
  final String description;
  final int durationMs;
  final int fileSizeBytes;
  final String previewUrl;
  final String downloadUrl;
  final String? thumbnailUrl;
  final String version;
  final AssetLicense license;
  final List<String> tags;
  final bool isDownloaded;
  final String? localPath;
  final DateTime? downloadedAt;

  const Asset({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.description,
    required this.durationMs,
    required this.fileSizeBytes,
    required this.previewUrl,
    required this.downloadUrl,
    this.thumbnailUrl,
    this.version = '1.0.0',
    required this.license,
    this.tags = const [],
    this.isDownloaded = false,
    this.localPath,
    this.downloadedAt,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  double get durationInSeconds => durationMs / 1000.0;

  String get formattedDuration {
    final seconds = (durationMs / 1000.0).toStringAsFixed(1);
    return '${seconds}s';
  }

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Asset copyWith({
    String? id,
    String? name,
    String? category,
    AssetType? type,
    String? description,
    int? durationMs,
    int? fileSizeBytes,
    String? previewUrl,
    String? downloadUrl,
    String? thumbnailUrl,
    String? version,
    AssetLicense? license,
    List<String>? tags,
    bool? isDownloaded,
    String? localPath,
    DateTime? downloadedAt,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      type: type ?? this.type,
      description: description ?? this.description,
      durationMs: durationMs ?? this.durationMs,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      previewUrl: previewUrl ?? this.previewUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      version: version ?? this.version,
      license: license ?? this.license,
      tags: tags ?? this.tags,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localPath: localPath ?? this.localPath,
      downloadedAt: downloadedAt ?? this.downloadedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'type': type.name,
    'description': description,
    'durationMs': durationMs,
    'fileSizeBytes': fileSizeBytes,
    'previewUrl': previewUrl,
    'downloadUrl': downloadUrl,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    'version': version,
    'license': license.toJson(),
    'tags': tags,
    'isDownloaded': isDownloaded,
    if (localPath != null) 'localPath': localPath,
    if (downloadedAt != null) 'downloadedAt': downloadedAt!.toIso8601String(),
  };

  factory Asset.fromJson(Map<String, dynamic> json) => Asset(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    type: AssetType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => AssetType.soundEffect,
    ),
    description: json['description'] as String? ?? '',
    durationMs: json['durationMs'] as int? ?? 1000,
    fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
    previewUrl: json['previewUrl'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String? ?? '',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    version: json['version'] as String? ?? '1.0.0',
    license: json['license'] != null
        ? AssetLicense.fromJson(json['license'] as Map<String, dynamic>)
        : const AssetLicense(name: 'Creative Commons 0'),
    tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    isDownloaded: json['isDownloaded'] as bool? ?? false,
    localPath: json['localPath'] as String?,
    downloadedAt: json['downloadedAt'] != null
        ? DateTime.tryParse(json['downloadedAt'] as String)
        : null,
  );
}
