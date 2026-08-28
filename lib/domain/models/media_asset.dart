/// Unified Media Asset Type
enum MediaAssetType {
  video,
  photo,
  audio,
}

/// Unified Immutable Model for media assets (Device imports and library assets)
class MediaAsset {
  final String id;
  final MediaAssetType type;
  final String name;

  /// Original Android content URI (content://...) if available
  final String? uri;

  /// Actual local cached filesystem path on device storage (/data/user/0/.../cache/...)
  /// This must be used by File(), image renderers, and media players.
  final String? localPath;

  /// Null for media types where duration does not apply (e.g. photos)
  final Duration? duration;

  /// File size in bytes
  final int? sizeBytes;

  /// File path for video thumbnail or photo preview
  final String? thumbnailPath;

  final DateTime createdAt;

  /// Original display name
  String get displayName => name;

  const MediaAsset({
    required this.id,
    required this.type,
    required this.name,
    this.uri,
    this.localPath,
    this.duration,
    this.sizeBytes,
    this.thumbnailPath,
    required this.createdAt,
  });

  bool get isVideo => type == MediaAssetType.video;
  bool get isPhoto => type == MediaAssetType.photo;
  bool get isAudio => type == MediaAssetType.audio;

  MediaAsset copyWith({
    String? id,
    MediaAssetType? type,
    String? name,
    String? uri,
    String? localPath,
    Duration? duration,
    int? sizeBytes,
    String? thumbnailPath,
    DateTime? createdAt,
  }) {
    return MediaAsset(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      localPath: localPath ?? this.localPath,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'uri': uri,
      'localPath': localPath,
      'durationMs': duration?.inMilliseconds,
      'sizeBytes': sizeBytes,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      id: json['id'] as String,
      type: MediaAssetType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MediaAssetType.video,
      ),
      name: json['name'] as String? ?? 'Media Asset',
      uri: json['uri'] as String?,
      localPath: json['localPath'] as String?,
      duration: json['durationMs'] != null
          ? Duration(milliseconds: json['durationMs'] as int)
          : null,
      sizeBytes: json['sizeBytes'] as int?,
      thumbnailPath: json['thumbnailPath'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAsset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          name == other.name &&
          uri == other.uri &&
          localPath == other.localPath &&
          duration == other.duration &&
          sizeBytes == other.sizeBytes &&
          thumbnailPath == other.thumbnailPath &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      type.hashCode ^
      name.hashCode ^
      uri.hashCode ^
      localPath.hashCode ^
      duration.hashCode ^
      sizeBytes.hashCode ^
      thumbnailPath.hashCode ^
      createdAt.hashCode;
}
