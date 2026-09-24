import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/audio_waveform_service.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';

/// Interactive CapCut timeline video clip widget with filmstrip preview,
/// yellow selection border, and draggable left/right trim handles.
class TimelineClipItem extends StatefulWidget {
  final VideoClip clip;
  final String? localPath;
  final String? thumbnailPath;
  final bool isPhoto;
  final int index;
  final bool isSelected;
  final double pixelsPerSecond;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails>? onTapDown;
  final Function(Duration newTrimStart, Duration newTrimEnd) onTrimChanged;
  final double? clipStartTime;
  final double? currentPlayheadTime;
  final ValueChanged<Keyframe>? onKeyframeTap;

  const TimelineClipItem({
    super.key,
    required this.clip,
    this.localPath,
    this.thumbnailPath,
    this.isPhoto = false,
    required this.index,
    required this.isSelected,
    required this.pixelsPerSecond,
    required this.onTap,
    this.onTapDown,
    required this.onTrimChanged,
    this.clipStartTime,
    this.currentPlayheadTime,
    this.onKeyframeTap,
  });

  @override
  State<TimelineClipItem> createState() => _TimelineClipItemState();
}

class _TimelineClipItemState extends State<TimelineClipItem> {
  String? _generatedThumbnail;
  bool _thumbGenerated = false;

  @override
  void initState() {
    super.initState();
    _tryGenerateThumbnail();
  }

  @override
  void didUpdateWidget(covariant TimelineClipItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localPath != widget.localPath ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _generatedThumbnail = null;
      _thumbGenerated = false;
      _tryGenerateThumbnail();
    }
  }

  /// For Windows video clips with no thumbnail, auto-extract one via inline PowerShell.
  void _tryGenerateThumbnail() {
    if (_thumbGenerated) return;
    if (widget.isPhoto) return;
    if (kIsWeb) return;
    if (!Platform.isWindows) return;

    // If a valid thumbnailPath is already provided, use it directly
    if (widget.thumbnailPath != null &&
        !widget.thumbnailPath!.startsWith('content://') &&
        File(widget.thumbnailPath!).existsSync()) {
      _generatedThumbnail = widget.thumbnailPath;
      _thumbGenerated = true;
      return;
    }

    final path = widget.localPath;
    if (path == null || path.startsWith('content://') || !File(path).existsSync()) return;

    _thumbGenerated = true; // prevent duplicate runs

    Future.microtask(() async {
      try {
        final tempBase = Platform.environment['TEMP'] ??
            Platform.environment['TMP'] ??
            'C:\\Windows\\Temp';
        final cacheDir = Directory('$tempBase\\capcut_thumbs');
        if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

        final safeId = path.hashCode.abs();
        final thumbPath = '${cacheDir.path}\\thumb_$safeId.jpg';

        if (File(thumbPath).existsSync()) {
          if (mounted) setState(() => _generatedThumbnail = thumbPath);
          return;
        }

        // Inline PowerShell: IShellItemImageFactory via COM interop
        final ps = '''
\$c=@"
using System;using System.Drawing;using System.Drawing.Imaging;using System.Runtime.InteropServices;
public class T2{
  [ComImport][Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IIF{[PreserveSig]int G([In,MarshalAs(UnmanagedType.Struct)]S s,[In]int f,[Out]out IntPtr h);}
  [StructLayout(LayoutKind.Sequential)]public struct S{public int x;public int y;public S(int x,int y){this.x=x;this.y=y;}}
  [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=false)]
  public static extern void SHC([In,MarshalAs(UnmanagedType.LPWStr)]string p,[In]IntPtr b,[In,MarshalAs(UnmanagedType.LPStruct)]Guid r,[Out,MarshalAs(UnmanagedType.Interface)]out IIF f);
  [DllImport("gdi32.dll")]public static extern bool D(IntPtr h);
  public static bool E(string v,string o,int w,int h){
    try{Guid g=new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");IIF f;SHC(v,IntPtr.Zero,g,out f);
    if(f==null)return false;IntPtr hb;int r=f.G(new S(w,h),1,out hb);
    if(r!=0||hb==IntPtr.Zero)return false;
    using(var b=Bitmap.FromHbitmap(hb)){b.Save(o,ImageFormat.Jpeg);}D(hb);return true;}catch{return false;}}}
"@
Add-Type -TypeDefinition \$c -ReferencedAssemblies System.Drawing -EA SilentlyContinue
\$dir="${cacheDir.path.replaceAll(r'\', r'\\')}";if(!(Test-Path \$dir)){New-Item -ItemType Directory \$dir -Force|Out-Null}
if([T2]::E("${path.replaceAll(r'\', r'\\')}","${thumbPath.replaceAll(r'\', r'\\')}",320,180)){Write-Host "OK";exit 0}else{exit 1}
''';
        final scriptPath = '${cacheDir.path}\\ts_$safeId.ps1';
        File(scriptPath).writeAsStringSync(ps, flush: true);

        final res = await Process.run(
          'powershell',
          ['-ExecutionPolicy', 'Bypass', '-NonInteractive', '-File', scriptPath],
          runInShell: true,
        );
        try { File(scriptPath).deleteSync(); } catch (_) {}

        if (res.exitCode == 0 && File(thumbPath).existsSync()) {
          if (mounted) setState(() => _generatedThumbnail = thumbPath);
        }
      } catch (e) {
        debugPrint('[TimelineClipItem] thumb gen error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final clipWidth = widget.clip.durationInSeconds * widget.pixelsPerSecond;
    // Prefer parent-supplied path, then locally generated path, then localPath for photos
    final displayImagePath = widget.isPhoto
        ? widget.localPath
        : (_generatedThumbnail ?? widget.thumbnailPath);
    final hasDisplayImage = displayImagePath != null &&
        !displayImagePath.startsWith('content://') &&
        !kIsWeb &&
        File(displayImagePath).existsSync();
    final currentLocalPath = widget.localPath;
    final isMissingMedia = currentLocalPath != null &&
        !currentLocalPath.startsWith('content://') &&
        !kIsWeb &&
        !File(currentLocalPath).existsSync();

    return GestureDetector(
      onTapDown: widget.onTapDown,
      onTap: widget.onTap,
      child: Container(
        width: math.max(clipWidth, 24.0),
        height: AppDimensions.videoTrackHeight,
        margin: const EdgeInsets.symmetric(horizontal: 1.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Filmstrip Body Container
            Positioned.fill(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(
                    color: widget.isSelected ? AppColors.selectionBorder : AppColors.videoTrackBorder,
                    width: widget.isSelected ? 2.5 : 1.0,
                  ),
                  gradient: LinearGradient(
                    colors: widget.clip.previewGradient,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Repeating Filmstrip Video Frames
                    Positioned.fill(
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // Single Frame Concept:
                            // When zoomed in (pixelsPerSecond >= 200), each cell is exactly 1 single frame (fps = 30)
                            // At standard zoom, filmstrip uses 56px overview cards
                            final isSingleFrameMode = widget.pixelsPerSecond >= 200.0;
                            final frameWidth = isSingleFrameMode
                                ? (widget.pixelsPerSecond / 30.0).clamp(6.0, 56.0)
                                : 56.0;
                            final frameCount = (constraints.maxWidth / frameWidth).ceil().clamp(1, 1500);

                            return OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 0,
                              maxWidth: double.infinity,
                              minHeight: constraints.maxHeight,
                              maxHeight: constraints.maxHeight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(frameCount, (frameIdx) {
                                  return Container(
                                    width: frameWidth,
                                    height: constraints.maxHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: isSingleFrameMode
                                              ? AppColors.primary.withOpacity(0.35)
                                              : Colors.white.withOpacity(0.15),
                                          width: isSingleFrameMode ? 1.0 : 0.8,
                                        ),
                                      ),
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (hasDisplayImage)
                                          Opacity(
                                            opacity: 0.75,
                                            child: Image.file(
                                              File(displayImagePath),
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, err, stack) =>
                                                  _buildFramePlaceholder(widget.clip, frameIdx),
                                            ),
                                          )
                                        else
                                          _buildFramePlaceholder(widget.clip, frameIdx),

                                        // Frame number marker in single-frame precision mode
                                        if (isSingleFrameMode && frameWidth >= 14)
                                          Positioned(
                                            bottom: 2,
                                            left: 1,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.7),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                              child: Text(
                                                '${(frameIdx % 30) + 1}',
                                                style: const TextStyle(
                                                  fontSize: 7.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Embedded Audio Waveform Graph at bottom of video clip
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 24,
                      child: CustomPaint(
                        painter: _EmbeddedAudioWaveformPainter(
                          assetId: widget.clip.assetId,
                          localPath: widget.localPath,
                          trimStart: widget.clip.trimStart,
                          trimEnd: widget.clip.trimEnd,
                          totalDuration: widget.clip.originalDuration,
                          volume: widget.clip.volume,
                          isMuted: widget.clip.isMuted,
                        ),
                      ),
                    ),

                    // Top-Left: Clip Title & Duration Pill
                    Positioned(
                      top: 4,
                      left: widget.isSelected ? AppDimensions.trimHandleWidth + 2 : 6,
                      right: widget.isSelected ? AppDimensions.trimHandleWidth + 2 : 6,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 30) {
                            return const SizedBox.shrink();
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.clip.previewIcon, size: 10, color: Colors.white70),
                              if (constraints.maxWidth > 70) ...[
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    widget.clip.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                                    ),
                                  ),
                                ),
                              ],
                              if (constraints.maxWidth > 50)
                                Container(
                                  margin: const EdgeInsets.only(left: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    TimeFormatter.formatSeconds(widget.clip.durationInSeconds, showMilliseconds: false),
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Bottom-Right: Speed Badge if != 1.0 or SpeedCurve is active
                    if (widget.clip.speedCurve != null || (widget.clip.speed - 1.0).abs() > 0.05)
                      Positioned(
                        bottom: 4,
                        right: widget.isSelected ? AppDimensions.trimHandleWidth + 4 : 6,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (clipWidth < 40) return const SizedBox.shrink();
                            final isCurve = widget.clip.speedCurve != null;
                            final badgeText = isCurve
                                ? (clipWidth < 70
                                    ? 'Curve'
                                    : '~${widget.clip.speedCurve!.averageSpeed.toStringAsFixed(1)}x Curve')
                                : '${widget.clip.speed.toStringAsFixed(1)}x';
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isCurve ? const Color(0xFF6C5CE7) : AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCurve) ...[
                                    const Icon(Icons.show_chart_rounded, size: 9, color: Colors.white),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: isCurve ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    // Media Offline indicator
                    if (isMissingMedia)
                      Positioned(
                        bottom: 4,
                        left: widget.isSelected ? AppDimensions.trimHandleWidth + 4 : 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image_rounded, size: 9, color: Colors.white),
                              SizedBox(width: 2),
                              Text(
                                'OFFLINE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 2. Left Draggable Trim Handle (Visible when selected)
            if (widget.isSelected)
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: AppDimensions.trimHandleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final deltaSeconds = details.delta.dx / widget.pixelsPerSecond;
                    final effectiveSpeed = widget.clip.speedCurve?.averageSpeed ?? widget.clip.speed;
                    final deltaMs = (deltaSeconds * effectiveSpeed * 1000).round();
                    final proposedTrimStartMs = widget.clip.trimStart.inMilliseconds + deltaMs;

                    if (proposedTrimStartMs >= 0 &&
                        (widget.clip.trimEnd.inMilliseconds - proposedTrimStartMs) >= 300) {
                      widget.onTrimChanged(
                        Duration(milliseconds: proposedTrimStartMs),
                        widget.clip.trimEnd,
                      );
                    }
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.trimHandle,
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(AppDimensions.radiusSm)),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 3. Right Draggable Trim Handle (Visible when selected)
            if (widget.isSelected)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: AppDimensions.trimHandleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final deltaSeconds = details.delta.dx / widget.pixelsPerSecond;
                    final effectiveSpeed = widget.clip.speedCurve?.averageSpeed ?? widget.clip.speed;
                    final deltaMs = (deltaSeconds * effectiveSpeed * 1000).round();
                    final proposedTrimEndMs = widget.clip.trimEnd.inMilliseconds + deltaMs;

                    if (proposedTrimEndMs <= widget.clip.originalDuration.inMilliseconds &&
                        (proposedTrimEndMs - widget.clip.trimStart.inMilliseconds) >= 300) {
                      widget.onTrimChanged(
                        widget.clip.trimStart,
                        Duration(milliseconds: proposedTrimEndMs),
                      );
                    }
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.trimHandle,
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(AppDimensions.radiusSm)),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 4. Keyframe Diamond Markers (CapCut Golden Diamonds with active playhead glow & tap-to-seek)
            ...widget.clip.keyframes.map((kf) {
              final kfRatio = widget.clip.durationInSeconds > 0 ? (kf.timeInSeconds / widget.clip.durationInSeconds) : 0.0;
              final kfX = (kfRatio * clipWidth).clamp(0.0, math.max(0.0, clipWidth - 10)).toDouble();
              final isKeyframeActive = widget.currentPlayheadTime != null && widget.clipStartTime != null
                  ? ((widget.clipStartTime! + kf.timeInSeconds) - widget.currentPlayheadTime!).abs() < 0.08
                  : false;

              return Positioned(
                left: (kfX - 7).clamp(0.0, math.max(0.0, clipWidth - 14)),
                top: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (widget.onKeyframeTap != null) {
                      widget.onKeyframeTap!(kf);
                    }
                  },
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: Container(
                        width: isKeyframeActive ? 11 : 8.5,
                        height: isKeyframeActive ? 11 : 8.5,
                        decoration: BoxDecoration(
                          color: isKeyframeActive ? const Color(0xFFFFEA00) : const Color(0xFFFFD600),
                          border: Border.all(
                            color: isKeyframeActive ? Colors.white : Colors.black87,
                            width: isKeyframeActive ? 1.5 : 1.0,
                          ),
                          boxShadow: isKeyframeActive
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFFFD600).withOpacity(0.85),
                                    blurRadius: 6,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [
                                  const BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                        ),
                        transform: Matrix4.rotationZ(0.785398),
                        transformAlignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFramePlaceholder(VideoClip clip, int index) {
    return Container(
      color: Colors.black.withOpacity(0.25),
      child: Center(
        child: Icon(
          Icons.movie_filter_outlined,
          size: 14,
          color: Colors.white.withOpacity(0.18),
        ),
      ),
    );
  }
}

class _EmbeddedAudioWaveformPainter extends CustomPainter {
  final String assetId;
  final String? localPath;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration totalDuration;
  final double volume;
  final bool isMuted;

  _EmbeddedAudioWaveformPainter({
    required this.assetId,
    this.localPath,
    required this.trimStart,
    required this.trimEnd,
    required this.totalDuration,
    required this.volume,
    this.isMuted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (isMuted || volume <= 0.001) {
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, size.height - 2), Offset(size.width, size.height - 2), linePaint);
      return;
    }

    const barWidth = 2.0;
    const barGap = 1.5;
    const barSpacing = barWidth + barGap;
    final barCount = (size.width / barSpacing).floor();
    if (barCount <= 0) return;

    final fullWaveform = AudioWaveformService.instance.getWaveformSync(
      cacheKey: '${assetId}_${totalDuration.inMilliseconds}',
      localPath: localPath,
      duration: totalDuration,
    );

    final resampled = AudioWaveformService.instance.resampleSlicedWaveform(
      fullWaveform: fullWaveform,
      trimStart: trimStart,
      trimEnd: trimEnd,
      totalDuration: totalDuration,
      barCount: barCount,
    );

    final barPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final effectiveVolume = volume.clamp(0.0, 1.0);
    final availableHeight = size.height - 3.0;

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing + (barWidth / 2) + 1.0;
      final amp = resampled[i] * effectiveVolume;
      final height = (amp * availableHeight).clamp(2.0, availableHeight);
      final yTop = size.height - height;
      final yBottom = size.height - 1.0;

      canvas.drawLine(Offset(x, yBottom), Offset(x, yTop), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmbeddedAudioWaveformPainter oldDelegate) =>
      oldDelegate.assetId != assetId ||
      oldDelegate.localPath != localPath ||
      oldDelegate.trimStart != trimStart ||
      oldDelegate.trimEnd != trimEnd ||
      oldDelegate.totalDuration != totalDuration ||
      oldDelegate.volume != volume ||
      oldDelegate.isMuted != isMuted;
}
