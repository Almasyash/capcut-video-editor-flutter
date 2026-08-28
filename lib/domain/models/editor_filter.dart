import 'package:flutter/material.dart';

/// Color grading and filter presets
enum FilterType {
  none,
  moody,
  cyberpunk,
  cinematic,
  blackAndWhite,
  vintage,
  tealAndOrange,
  warmSunset,
}

class EditorFilter {
  final FilterType type;
  final String name;
  final IconData icon;
  final List<Color> previewColors;
  final double intensity; // 0.0 to 1.0

  const EditorFilter({
    required this.type,
    required this.name,
    required this.icon,
    required this.previewColors,
    this.intensity = 0.8,
  });

  EditorFilter copyWith({
    FilterType? type,
    String? name,
    IconData? icon,
    List<Color>? previewColors,
    double? intensity,
  }) {
    return EditorFilter(
      type: type ?? this.type,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      previewColors: previewColors ?? this.previewColors,
      intensity: intensity ?? this.intensity,
    );
  }

  static const List<EditorFilter> presets = [
    EditorFilter(
      type: FilterType.none,
      name: 'Normal',
      icon: Icons.filter_none_rounded,
      previewColors: [Colors.grey, Colors.blueGrey],
      intensity: 0.0,
    ),
    EditorFilter(
      type: FilterType.cinematic,
      name: 'Cinematic',
      icon: Icons.movie_filter_rounded,
      previewColors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.moody,
      name: 'Moody Dark',
      icon: Icons.dark_mode_rounded,
      previewColors: [Color(0xFF232526), Color(0xFF414345)],
      intensity: 0.85,
    ),
    EditorFilter(
      type: FilterType.cyberpunk,
      name: 'Cyberpunk',
      icon: Icons.electric_bolt_rounded,
      previewColors: [Color(0xFFFF007F), Color(0xFF00F0FF)],
      intensity: 0.9,
    ),
    EditorFilter(
      type: FilterType.tealAndOrange,
      name: 'Teal & Orange',
      icon: Icons.wb_sunny_rounded,
      previewColors: [Color(0xFF0083B0), Color(0xFF00B4DB), Color(0xFFFF8008)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.vintage,
      name: 'Vintage Film',
      icon: Icons.camera_roll_rounded,
      previewColors: [Color(0xFFD38312), Color(0xFFA83279)],
      intensity: 0.75,
    ),
    EditorFilter(
      type: FilterType.warmSunset,
      name: 'Warm Sunset',
      icon: Icons.flare_rounded,
      previewColors: [Color(0xFFFF512F), Color(0xFFDD2476)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.blackAndWhite,
      name: 'B&W Classic',
      icon: Icons.monochrome_photos_rounded,
      previewColors: [Colors.black, Colors.white],
      intensity: 1.0,
    ),
  ];

  ColorFilter? getColorFilter() {
    if (type == FilterType.none || intensity <= 0.0) return null;

    switch (type) {
      case FilterType.blackAndWhite:
        const lumR = 0.2126;
        const lumG = 0.7152;
        const lumB = 0.0722;
        final invI = 1.0 - intensity;
        return ColorFilter.matrix(<double>[
          invI + intensity * lumR, intensity * lumG, intensity * lumB, 0, 0,
          intensity * lumR, invI + intensity * lumG, intensity * lumB, 0, 0,
          intensity * lumR, intensity * lumG, invI + intensity * lumB, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.cyberpunk:
        return ColorFilter.matrix(<double>[
          1.2 * intensity + (1 - intensity), 0, 0.4 * intensity, 0, 10 * intensity,
          0, 1.0, 0.3 * intensity, 0, 0,
          0.3 * intensity, 0, 1.4 * intensity + (1 - intensity), 0, 20 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.tealAndOrange:
        return ColorFilter.matrix(<double>[
          1.2 * intensity + (1 - intensity), 0, 0, 0, 20 * intensity,
          0, 1.0, 0, 0, 5 * intensity,
          0, 0, 0.8 * intensity + (1 - intensity), 0, -15 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.warmSunset:
        return ColorFilter.matrix(<double>[
          1.25 * intensity + (1 - intensity), 0, 0, 0, 15 * intensity,
          0, 1.1 * intensity + (1 - intensity), 0, 0, 5 * intensity,
          0, 0, 0.75 * intensity + (1 - intensity), 0, -10 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.moody:
        return ColorFilter.matrix(<double>[
          0.9, 0, 0, 0, -10 * intensity,
          0, 0.9, 0, 0, -10 * intensity,
          0, 0, 0.95, 0, 5 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.vintage:
        return ColorFilter.matrix(<double>[
          1.1 * intensity + (1 - intensity), 0, 0, 0, 10 * intensity,
          0, 1.0, 0, 0, 10 * intensity,
          0, 0, 0.8 * intensity + (1 - intensity), 0, 20 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.cinematic:
        return ColorFilter.matrix(<double>[
          1.1 * intensity + (1 - intensity), 0, 0, 0, -5 * intensity,
          0, 1.15 * intensity + (1 - intensity), 0, 0, 0,
          0, 0, 1.25 * intensity + (1 - intensity), 0, 10 * intensity,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.none:
        return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'intensity': intensity,
    };
  }

  factory EditorFilter.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'none';
    final type = FilterType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => FilterType.none,
    );
    final intensity = (json['intensity'] as num?)?.toDouble() ?? 0.8;
    final preset = presets.firstWhere(
      (p) => p.type == type,
      orElse: () => presets.first,
    );
    return preset.copyWith(intensity: intensity);
  }
}
