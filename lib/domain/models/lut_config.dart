import 'package:flutter/foundation.dart';

/// Configuration for 3D / 1D Look-Up Table (LUT)
@immutable
class LutConfig {
  final String id;
  final String name;
  final String? filePath;
  final String title;
  final int size; // e.g., 17, 33, 64
  final double intensity; // 0.0 (neutral / bypass) to 1.0 (full effect)
  final bool is3D;

  const LutConfig({
    required this.id,
    required this.name,
    this.filePath,
    this.title = 'LUT',
    this.size = 33,
    this.intensity = 1.0,
    this.is3D = true,
  });

  bool get is1D => !is3D;

  bool get isValid => id.isNotEmpty && size >= 2 && intensity > 0.0;

  LutConfig copyWith({
    String? id,
    String? name,
    String? filePath,
    String? title,
    int? size,
    double? intensity,
    bool? is3D,
  }) {
    return LutConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      size: size ?? this.size,
      intensity: (intensity ?? this.intensity).clamp(0.0, 1.0),
      is3D: is3D ?? this.is3D,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (filePath != null) 'filePath': filePath,
    'title': title,
    'size': size,
    'intensity': intensity,
    'is3D': is3D,
  };

  factory LutConfig.fromJson(Map<String, dynamic> json) {
    return LutConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Custom LUT',
      filePath: json['filePath'] as String?,
      title: json['title'] as String? ?? 'LUT',
      size: (json['size'] as num?)?.toInt() ?? 33,
      intensity: ((json['intensity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
      is3D: json['is3D'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LutConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          filePath == other.filePath &&
          title == other.title &&
          size == other.size &&
          (intensity - other.intensity).abs() < 1e-4 &&
          is3D == other.is3D;

  @override
  int get hashCode => Object.hash(id, name, filePath, title, size, intensity, is3D);
}

/// Parsed 3D LUT Data in normalized float buffer
class ParsedCubeLut {
  final String title;
  final int size;
  final bool is3D;
  final Float32List table; // [size^3 * 3] for 3D or [size * 3] for 1D
  final double domainMin;
  final double domainMax;

  const ParsedCubeLut({
    required this.title,
    required this.size,
    required this.is3D,
    required this.table,
    this.domainMin = 0.0,
    this.domainMax = 1.0,
  });

  bool get is1D => !is3D;
}

/// Robust parser for industry standard Adobe .cube LUT files
class CubeLutParser {
  static ParsedCubeLut? parse(String content) {
    try {
      final lines = content.split(RegExp(r'\r?\n'));
      String title = 'Untitled LUT';
      int size = 0;
      bool is3D = true;
      double domainMin = 0.0;
      double domainMax = 1.0;

      final dataFloats = <double>[];

      for (var rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        final upper = line.toUpperCase();
        if (upper.startsWith('TITLE ')) {
          var t = line.substring(6).trim();
          if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
            t = t.substring(1, t.length - 1);
          }
          title = t;
          continue;
        }

        if (upper.startsWith('LUT_3D_SIZE ')) {
          final s = int.tryParse(line.substring(12).trim());
          if (s != null && s > 1 && s <= 256) {
            size = s;
            is3D = true;
          }
          continue;
        }

        if (upper.startsWith('LUT_1D_SIZE ')) {
          final s = int.tryParse(line.substring(12).trim());
          if (s != null && s > 1 && s <= 4096) {
            size = s;
            is3D = false;
          }
          continue;
        }

        if (upper.startsWith('DOMAIN_MIN ')) {
          final parts = line.substring(11).trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) domainMin = double.tryParse(parts[0]) ?? 0.0;
          continue;
        }

        if (upper.startsWith('DOMAIN_MAX ')) {
          final parts = line.substring(11).trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) domainMax = double.tryParse(parts[0]) ?? 1.0;
          continue;
        }

        // Triplet RGB numbers: "0.123 0.456 0.789"
        final tokens = line.split(RegExp(r'\s+'));
        if (tokens.length >= 3) {
          final r = double.tryParse(tokens[0]);
          final g = double.tryParse(tokens[1]);
          final b = double.tryParse(tokens[2]);
          if (r != null && g != null && b != null) {
            dataFloats.add(r);
            dataFloats.add(g);
            dataFloats.add(b);
          }
        }
      }

      if (size <= 0) return null;
      final expectedFloats = (is3D ? size * size * size : size) * 3;
      if (dataFloats.length != expectedFloats) {
        debugPrint('[CubeLutParser] Warning: expected $expectedFloats floats but found ${dataFloats.length}');
        if (dataFloats.length < expectedFloats) return null;
      }

      final floatList = Float32List.fromList(dataFloats.sublist(0, expectedFloats));
      return ParsedCubeLut(
        title: title,
        size: size,
        is3D: is3D,
        table: floatList,
        domainMin: domainMin,
        domainMax: domainMax,
      );
    } catch (e) {
      debugPrint('[CubeLutParser] Failed to parse .cube: $e');
      return null;
    }
  }
}
