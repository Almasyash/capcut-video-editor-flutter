/// Export resolution settings and frame rates
enum ExportResolution {
  res720p('720P', '1280 x 720', 1.0),
  res1080p('1080P', '1920 x 1080', 1.5),
  res2k('2K', '2560 x 1440', 2.2),
  res4k('4K', '3840 x 2160', 3.8);

  const ExportResolution(this.label, this.resolutionString, this.sizeMultiplier);

  final String label;
  final String resolutionString;
  final double sizeMultiplier;
}

enum ExportFps {
  fps24('24 fps', 'Cinematic'),
  fps30('30 fps', 'Standard'),
  fps50('50 fps', 'Smooth'),
  fps60('60 fps', 'Ultra Smooth');

  const ExportFps(this.label, this.description);

  final String label;
  final String description;
}
