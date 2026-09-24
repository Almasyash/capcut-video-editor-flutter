import 'package:flutter/material.dart';

/// Preset color options for Chroma Keying
class ChromaKeyPreset {
  final String name;
  final Color color;
  final IconData icon;

  const ChromaKeyPreset({
    required this.name,
    required this.color,
    required this.icon,
  });
}

/// Helper utility for GPU-accelerated Chroma Key (Green / Blue Screen) compositing
/// using Skia / Impeller 4x5 ColorFilter matrices.
class ChromaKeyHelper {
  /// Standard presets used in video production
  static const List<ChromaKeyPreset> presets = [
    ChromaKeyPreset(
      name: 'Neon Green',
      color: Color(0xFF00FF00),
      icon: Icons.circle,
    ),
    ChromaKeyPreset(
      name: 'Studio Green',
      color: Color(0xFF00B140),
      icon: Icons.circle,
    ),
    ChromaKeyPreset(
      name: 'Chroma Blue',
      color: Color(0xFF0047BB),
      icon: Icons.circle,
    ),
    ChromaKeyPreset(
      name: 'Classic Blue',
      color: Color(0xFF0000FF),
      icon: Icons.circle,
    ),
    ChromaKeyPreset(
      name: 'Studio Cyan',
      color: Color(0xFF00E5FF),
      icon: Icons.circle,
    ),
    ChromaKeyPreset(
      name: 'Studio Magenta',
      color: Color(0xFFFF007F),
      icon: Icons.circle,
    ),
  ];

  /// Builds a 20-element row-major 4x5 ColorFilter matrix for hardware keying.
  ///
  /// [keyColor]: Target color to remove (usually green or blue).
  /// [similarity]: How broad the color threshold is (0.0 to 1.0, default 0.4).
  /// [smoothness]: Edge feathering factor (0.0 to 1.0, default 0.1).
  /// [spill]: Spill neutralization intensity (0.0 to 1.0, default 0.15).
  static List<double> buildMatrix({
    required Color keyColor,
    double similarity = 0.40,
    double smoothness = 0.10,
    double spill = 0.15,
  }) {
    final r = keyColor.red / 255.0;
    final g = keyColor.green / 255.0;
    final b = keyColor.blue / 255.0;

    // Determine primary keying channel
    final isGreen = g >= r && g >= b;
    final isBlue = b > g && b >= r;

    // Sensitivity factor
    final k = (1.2 + similarity * 4.2) * (1.0 + smoothness * 0.8);
    final s = spill.clamp(0.0, 0.85);

    if (isGreen) {
      // Green Screen Removal & Spill Suppression
      return <double>[
        // R' = R
        1.0, 0.0, 0.0, 0.0, 0.0,
        // G' = (1 - s)*G + 0.5*s*R + 0.5*s*B (Neutralize green fringe spill)
        0.5 * s, 1.0 - s, 0.5 * s, 0.0, 0.0,
        // B' = B
        0.0, 0.0, 1.0, 0.0, 0.0,
        // A' = A - k*(G - 0.5*(R + B))
        0.5 * k, -k, 0.5 * k, 1.0, 0.0,
      ];
    } else if (isBlue) {
      // Blue Screen Removal & Spill Suppression
      return <double>[
        // R' = R
        1.0, 0.0, 0.0, 0.0, 0.0,
        // G' = G
        0.0, 1.0, 0.0, 0.0, 0.0,
        // B' = (1 - s)*B + 0.5*s*R + 0.5*s*G (Neutralize blue fringe spill)
        0.5 * s, 0.5 * s, 1.0 - s, 0.0, 0.0,
        // A' = A - k*(B - 0.5*(R + G))
        0.5 * k, 0.5 * k, -k, 1.0, 0.0,
      ];
    } else {
      // Custom / Red / Magenta Key
      return <double>[
        // R' = (1 - s)*R + 0.5*s*G + 0.5*s*B
        1.0 - s, 0.5 * s, 0.5 * s, 0.0, 0.0,
        // G' = G
        0.0, 1.0, 0.0, 0.0, 0.0,
        // B' = B
        0.0, 0.0, 1.0, 0.0, 0.0,
        // A' = A - k*(R - 0.5*(G + B))
        -k, 0.5 * k, 0.5 * k, 1.0, 0.0,
      ];
    }
  }

  /// Creates a ready-to-use Flutter ColorFilter
  static ColorFilter createColorFilter({
    required Color keyColor,
    double similarity = 0.40,
    double smoothness = 0.10,
    double spill = 0.15,
  }) {
    return ColorFilter.matrix(
      buildMatrix(
        keyColor: keyColor,
        similarity: similarity,
        smoothness: smoothness,
        spill: spill,
      ),
    );
  }
}
