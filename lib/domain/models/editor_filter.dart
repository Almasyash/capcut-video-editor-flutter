import 'package:flutter/material.dart';

/// Professional color grading and filter presets
enum FilterType {
  none,
  vivid,
  warm,
  cool,
  vintage,
  cinematic,
  fade,
  mono,
  blackAndWhite,
  sepia,
  dramatic,
  portrait,
  // Backward compatibility presets
  moody,
  cyberpunk,
  tealAndOrange,
  warmSunset,
}

class EditorFilter {
  final FilterType type;
  final String name;
  final IconData icon;
  final List<Color> previewColors;
  final double intensity; // 0.0 to 1.0 (default 0.8)

  String get id {
    switch (type) {
      case FilterType.none: return 'none';
      case FilterType.vivid: return 'vivid';
      case FilterType.warm: return 'warm';
      case FilterType.cool: return 'cool';
      case FilterType.vintage: return 'vintage';
      case FilterType.cinematic: return 'cinema';
      case FilterType.fade: return 'fade';
      case FilterType.mono: return 'mono';
      case FilterType.blackAndWhite: return 'black_white';
      case FilterType.sepia: return 'sepia';
      case FilterType.dramatic: return 'dramatic';
      case FilterType.portrait: return 'portrait';
      case FilterType.moody: return 'moody';
      case FilterType.cyberpunk: return 'cyberpunk';
      case FilterType.tealAndOrange: return 'teal_orange';
      case FilterType.warmSunset: return 'warm_sunset';
    }
  }

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
      intensity: (intensity ?? this.intensity).clamp(0.0, 1.0),
    );
  }

  static const List<EditorFilter> presets = [
    EditorFilter(
      type: FilterType.none,
      name: 'None',
      icon: Icons.filter_none_rounded,
      previewColors: [Colors.grey, Colors.blueGrey],
      intensity: 0.0,
    ),
    EditorFilter(
      type: FilterType.vivid,
      name: 'Vivid',
      icon: Icons.auto_awesome_rounded,
      previewColors: [Color(0xFFFF0844), Color(0xFFFFB199)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.warm,
      name: 'Warm',
      icon: Icons.wb_sunny_rounded,
      previewColors: [Color(0xFFF6D365), Color(0xFFFDA085)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.cool,
      name: 'Cool',
      icon: Icons.ac_unit_rounded,
      previewColors: [Color(0xFF89F7FE), Color(0xFF66A6FF)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.vintage,
      name: 'Vintage',
      icon: Icons.camera_roll_rounded,
      previewColors: [Color(0xFFD38312), Color(0xFFA83279)],
      intensity: 0.75,
    ),
    EditorFilter(
      type: FilterType.cinematic,
      name: 'Cinema',
      icon: Icons.movie_filter_rounded,
      previewColors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
      intensity: 0.8,
    ),
    EditorFilter(
      type: FilterType.fade,
      name: 'Fade',
      icon: Icons.gradient_rounded,
      previewColors: [Color(0xFFBDC3C7), Color(0xFF2C3E50)],
      intensity: 0.7,
    ),
    EditorFilter(
      type: FilterType.mono,
      name: 'Mono',
      icon: Icons.filter_b_and_w_rounded,
      previewColors: [Color(0xFF434343), Color(0xFF000000)],
      intensity: 0.9,
    ),
    EditorFilter(
      type: FilterType.blackAndWhite,
      name: 'B&W',
      icon: Icons.monochrome_photos_rounded,
      previewColors: [Colors.black, Colors.white],
      intensity: 1.0,
    ),
    EditorFilter(
      type: FilterType.sepia,
      name: 'Sepia',
      icon: Icons.photo_filter_rounded,
      previewColors: [Color(0xFF704214), Color(0xFFC39B77)],
      intensity: 0.85,
    ),
    EditorFilter(
      type: FilterType.dramatic,
      name: 'Dramatic',
      icon: Icons.flash_on_rounded,
      previewColors: [Color(0xFF141E30), Color(0xFF243B55)],
      intensity: 0.85,
    ),
    EditorFilter(
      type: FilterType.portrait,
      name: 'Portrait',
      icon: Icons.face_rounded,
      previewColors: [Color(0xFFFF9A9E), Color(0xFFFECFEF)],
      intensity: 0.75,
    ),
    // Additional backward compatibility presets
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
      type: FilterType.warmSunset,
      name: 'Warm Sunset',
      icon: Icons.flare_rounded,
      previewColors: [Color(0xFFFF512F), Color(0xFFDD2476)],
      intensity: 0.8,
    ),
  ];

  ColorFilter? getColorFilter([double? customIntensity]) {
    final effIntensity = customIntensity ?? intensity;
    if (type == FilterType.none || effIntensity <= 0.0) return null;

    final i = effIntensity.clamp(0.0, 1.0);
    final inv = 1.0 - i;

    switch (type) {
      case FilterType.none:
        return null;

      case FilterType.vivid:
        return ColorFilter.matrix(<double>[
          inv + i * 1.3, 0, 0, 0, 5 * i,
          0, inv + i * 1.3, 0, 0, 5 * i,
          0, 0, inv + i * 1.3, 0, 5 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.warm:
        return ColorFilter.matrix(<double>[
          inv + i * 1.15, 0, 0, 0, 20 * i,
          0, inv + i * 1.05, 0, 0, 5 * i,
          0, 0, inv + i * 0.85, 0, -15 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.cool:
        return ColorFilter.matrix(<double>[
          inv + i * 0.85, 0, 0, 0, -15 * i,
          0, inv + i * 1.0, 0, 0, 0,
          0, 0, inv + i * 1.25, 0, 25 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.vintage:
        return ColorFilter.matrix(<double>[
          inv + i * 1.1, 0, 0, 0, 15 * i,
          0, inv + i * 1.0, 0, 0, 10 * i,
          0, 0, inv + i * 0.8, 0, -10 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.cinematic:
        return ColorFilter.matrix(<double>[
          inv + i * 1.15, 0, 0, 0, 5 * i,
          0, inv + i * 1.1, 0, 0, -5 * i,
          0, 0, inv + i * 1.25, 0, 15 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.fade:
        return ColorFilter.matrix(<double>[
          inv + i * 0.85, 0, 0, 0, 30 * i,
          0, inv + i * 0.85, 0, 0, 30 * i,
          0, 0, inv + i * 0.85, 0, 30 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.mono:
      case FilterType.blackAndWhite:
        const lumR = 0.2126;
        const lumG = 0.7152;
        const lumB = 0.0722;
        return ColorFilter.matrix(<double>[
          inv + i * lumR, i * lumG, i * lumB, 0, 0,
          i * lumR, inv + i * lumG, i * lumB, 0, 0,
          i * lumR, i * lumG, inv + i * lumB, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.sepia:
        return ColorFilter.matrix(<double>[
          inv + i * 0.393, i * 0.769, i * 0.189, 0, 10 * i,
          i * 0.349, inv + i * 0.686, i * 0.168, 0, 5 * i,
          i * 0.272, i * 0.534, inv + i * 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.dramatic:
        return ColorFilter.matrix(<double>[
          inv + i * 1.35, 0, 0, 0, -15 * i,
          0, inv + i * 1.35, 0, 0, -15 * i,
          0, 0, inv + i * 1.35, 0, -15 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.portrait:
        return ColorFilter.matrix(<double>[
          inv + i * 1.1, 0, 0, 0, 10 * i,
          0, inv + i * 1.05, 0, 0, 5 * i,
          0, 0, inv + i * 0.95, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.moody:
        return ColorFilter.matrix(<double>[
          inv + i * 0.9, 0, 0, 0, -10 * i,
          0, inv + i * 0.9, 0, 0, -10 * i,
          0, 0, inv + i * 0.95, 0, 5 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.cyberpunk:
        return ColorFilter.matrix(<double>[
          inv + i * 1.2, 0, i * 0.4, 0, 10 * i,
          0, 1.0, i * 0.3, 0, 0,
          i * 0.3, 0, inv + i * 1.4, 0, 20 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.tealAndOrange:
        return ColorFilter.matrix(<double>[
          inv + i * 1.2, 0, 0, 0, 20 * i,
          0, 1.0, 0, 0, 5 * i,
          0, 0, inv + i * 0.8, 0, -15 * i,
          0, 0, 0, 1, 0,
        ]);

      case FilterType.warmSunset:
        return ColorFilter.matrix(<double>[
          inv + i * 1.25, 0, 0, 0, 15 * i,
          0, inv + i * 1.1, 0, 0, 5 * i,
          0, 0, inv + i * 0.75, 0, -10 * i,
          0, 0, 0, 1, 0,
        ]);
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
