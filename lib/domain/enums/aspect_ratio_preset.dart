/// Supported video aspect ratio presets (TikTok 9:16, YouTube 16:9, IG 1:1, etc.)
enum AspectRatioPreset {
  ratio9x16('9:16', 9 / 16, 'TikTok / Shorts / Reels'),
  ratio16x9('16:9', 16 / 9, 'YouTube / Landscape'),
  ratio1x1('1:1', 1 / 1, 'Instagram / Square'),
  ratio4x5('4:5', 4 / 5, 'Portrait Feed'),
  ratioOriginal('Original', null, 'Source Fit');

  const AspectRatioPreset(this.label, this.ratio, this.description);

  final String label;
  final double? ratio;
  final String description;
}
