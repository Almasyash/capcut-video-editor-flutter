# Changelog

All notable changes to **Editor FS** are documented in this file.

## [1.6.0] - 2026-10-08

### 🌟 Professional Masking & Compositing Engine Suite
- **Comprehensive Masking Geometries (`VideoMask`)**: Full support for 5 standard shapes (Rectangle, Ellipse, Polygon, Linear, Radial) plus legacy presets (Split, Filmstrip, Circle, Heart, Star).
- **GPU-Accelerated Soft Feathering & Expansion**: High-performance analytical Signed Distance Fields (SDF) and smoothstep edge falloff ($0.0 - 100.0$) with inward/outward boundary dilation and erosion ($-100.0 - 100.0$).
- **Multi-Mask Compositing & Boolean Modes**: Support for up to 4 concurrent masks per clip with Boolean combination operations (`Add`, `Intersect`, `Subtract`, `Difference/XOR`), per-mask opacity, and inversion toggle.
- **Dynamic Keyframing Integration**: Direct integration with the keyframe animation engine for dynamic animated mask transitions across position ($X, Y$), scale, rotation, opacity, feather, and expansion.
- **Picture-in-Picture (PIP) Mask Parity**: Complete masking support for secondary PIP overlay layers (`OverlayClip`), enabling creative PIP cutouts, split-screen reveals, and animated shapes.
- **Production UI Suite (`MaskAdjustmentSheet`)**: Intuitive bottom sheet featuring multi-mask tabs, preset selector, precision sliders, interactive invert toggle, Boolean mode selector, and real-time keyframe indicator.
- **Native Android Hardware Export Engine (`VideoExportEngine.kt`)**: Hardware-accelerated OpenGL ES 2.0 fragment shaders (`oesFS` and `tex2DFS`) with uniform arrays, analytical SDF evaluations, dynamic blending, and MediaCodec MP4 encoding.
- **Quality & Assurance**: 726/726 passing unit, widget, and integration tests, 0 analyzer issues, verified across both canonical repositories.

---

## [1.5.0] - 2026-10-08

### 🌟 Professional Speed Ramping & Time Remapping Engine Suite
- **Deterministic Time Remapping Engine (`TimeRemapper`)**: Frame-accurate, monotonic timeline-to-source time mapping supporting continuous constant speeds ($0.1\times$ to $100.0\times$), freeze frame holding with playhead rebasing, and inverted reverse playback ($[\text{trimEnd} \to \text{trimStart}]$).
- **8 Non-Linear Speed Ramping Curve Presets**: Montage, Hero, Bullet, Jump Cut, Flash In, Flash Out, Smooth, and Custom curves with multi-point piecewise interpolation (`linear`, `easeIn`, `easeOut`, `easeInOut`, `hold`).
- **Interactive Speed Curve Splitting & Normalization**: Continuous, rebased split-at-playhead (`SpeedCurve.splitAt()`) generating normalized $[0.0, 1.0]$ time domains for Part A and Part B with velocity continuity across the split cut.
- **Dynamic Transition Overlap Preservation**: Seamless head and tail handle evaluation ($[0, \text{trimStart}]$ and $[\text{trimEnd}, \text{originalDuration}]$) under variable speed ramps and freeze frames, preserving crossfade, dissolve, wipe, slide, and zoom transitions without edge clamping distortion.
- **Picture-in-Picture (PIP) Video Overlay Remapping**: Full parity for video PIP layers, including independent speed multiplier controls ($0.1\times - 100\times$), speed ramping curves, freeze frames, and reverse playback.
- **Hardware-Accelerated Android Native Export (`VideoExportEngine.kt`)**: Monotonic output PTS generation, per-frame source time remapping (`ExportTimeRemapper`), transition overlap decoding, and hardware-accelerated MediaCodec + EGL14 + OpenGL ES 2.0 rendering without frame drops.
- **Undo/Redo & State Persistence**: Non-destructive speed history snapshots, deep duplication, backward-compatible project JSON serialization, and TTS announcements.
- **Quality & Release Assurance**: 711/711 passing unit and widget tests, 0 analyzer issues, verified on both canonical repositories.

---

## [1.4.0] - 2026-10-08

### 🌟 Professional Keyframe Animation & Motion Graph Engine Suite
- **Deterministic Keyframe Domain Models**: Reusable multi-track keyframe engine with `Linear`, `Hold`, and custom cubic Bézier easing curves solved via high-precision Newton-Raphson approximation ($\varepsilon = 10^{-6}$, 12 iterations max) with analytical boundary clamping.
- **Multi-Track Spatial & Parameter Keyframing**: Fine-grained keyframing across 2D transform ($X, Y$, scale, continuous multi-turn rotation beyond $\pm 360^\circ$), visual opacity, audio track volume, and 12 color grading adjustments.
- **Interactive Motion Graph Visualizer (`MotionGraphSheet`)**: 2D interactive cubic Bézier curve visualizer bottom sheet with draggable tangent control handles, curve interpolation presets (`Linear`, `Ease In`, `Ease Out`, `Ease In Out`, `Bounce`, `Elastic`), and dynamic parameter selection.
- **Timeline Diamond Keyframe Indicators**: Zoom-aligned diamond markers on video, overlay, and text tracks with playhead snapping, active indicator highlighting, and tap-to-seek navigation.
- **Preview & Hardware Export Parity**: Bit-for-bit mathematical alignment between Flutter Canvas rendering and Android native OpenGL ES 2.0 / MediaCodec hardware MP4 export compositing.
- **Audio Precedence Modulation**: Frame-accurate keyframe volume modulation (`effectiveGain = baseVolume * keyframeGain * fadeEnvelope`) applied across Flutter audio preview and native 16-bit 44.1 kHz PCM audio mixing export.
- **Non-Destructive Layer Lifecycle**: Complete keyframe preservation across split-at-playhead (segment retiming with boundary keyframes), clip duplication (deep copying with unique IDs), ripple delete, and universal undo/redo state restoration.
- **Quality & Release Assurance**: 685/685 passing unit and widget tests, 0 analyzer issues, verified on physical hardware (Realme RMX5003).

---

## [1.3.0] - 2026-10-08

### 🌟 Professional Color Grading, RGB Curves, 3D LUTs & 60fps Video Effects Suite
- **12 Comprehensive Color Grading Adjustments**: Exposure, Brightness, Contrast, Saturation, Temperature, Tint, Highlights, Shadows, Blacks, Whites, Vignette, and Sharpness.
- **Interactive RGB Curves**: 4 spline channels (Master/Red/Green/Blue), interactive 2D canvas control point editing, and piecewise-linear spline evaluation.
- **3D & 1D Adobe .cube LUT Parser**: Built-in production LUT presets (`Teal & Orange`, `Cyberpunk Glow`, `Warm Film 35mm`, `Bleach Bypass`, `Monochrome Noir`, `Vintage 70s`) with trilinear interpolation.
- **12 Professional Filter Presets**: 0% – 100% matrix intensity blending with hardware-synchronized OpenGL ES fragment shader uniforms.
- **60fps Animated Video Effects Engine**: Dedicated GPU-accelerated painters for `Glitch Art`, `VHS Camcorder` (retro OSD timecode & tracking), `RGB Split`, `Zoom Blur`, `Sparkles`, `Camera Shake`, and `35mm Film Grain`.
- **Hardware-Accelerated Export Engine**: Native Android OpenGL ES 2.0 fragment shader color grading and MediaCodec hardware MP4 export pipeline with zero external FFmpeg dependencies.
- **Neutral Safeguard & Performance**: Guaranteed zero-allocation pass-through on default parameters; isolated overlay rendering without text/UI distortion; debounced auto-save and `PopScope` navigation protection.
- **Quality & Assurance**: 656/656 passing tests, 0 analyzer issues, verified on physical hardware (Realme RMX5003).

---

## [1.2.0] - 2026-10-07

### 🌟 Professional Multi-Track Audio Editing & Sound Production Suite
- **Multi-Track PCM Audio Mixer**: Native Android `MediaExtractor` + `MediaCodec` + `MediaMuxer` pipeline decoding and mixing multi-layer audio into 16-bit 44.1 kHz stereo PCM.
- **Volume & Boost Engine**: Non-destructive volume scaling from 0% to 200% across primary video clips, audio tracks, and PIP video overlays with TTS accessibility announcements.
- **Non-Destructive Mute & Solo**: Instant muting without timeline disruption.
- **Fade In & Fade Out Envelopes**: Proportional linear volume ramps with waveform visual shading and dynamic duration clamping against trimmed clip bounds.
- **Playhead Audio Split & Extract**: Frame-accurate split-at-playhead and one-tap video-to-audio extraction with automatic source video muting.
- **RAM-Safe Waveform Generation**: Chunked 512 KB streaming analysis preventing Android heap exhaustion on large audio files.
- **Quality & Assurance**: 638/638 passing tests, 0 analyzer issues.

---

## [1.1.0] - 2026-09-24

### 🌟 Speed Curves, Keyframes, PIP, Chroma Key, Audio Beats & Captions Suite
- **Speed Curve Velocity Ramping**: Non-linear speed curves (`Montage`, `Hero`, `Bullet`, `Jump Cut`, `Flash In`, `Flash Out`, `Custom`) with pitch preservation and smooth slow-mo interpolation.
- **Keyframe Animation System**: CapCut Diamond Control Group UI, 4D property keyframing (Position, Scale, Rotation, Opacity), and easing curve interpolations.
- **PIP Layering & GPU Chroma Key**: Multi-layer Picture-in-Picture overlay video/photos with green/blue screen removal, color similarity, smoothness, and 12 blend modes.
- **Auto-Captions & Typography Suite**: Kinetic auto-captions, word-level timestamps, karaoke scale bounce, and glowing stroke outlines.
- **Audio Intelligence**: Audio beat detection (BPM), 100-bar waveform visualization, and Match Cut snap-to-beat timeline alignment.
- **Interactive Transform Canvas**: 2D free transform with magnetic guideline snapping, angular locking, and haptic feedback.
- **Quality & Performance**: 511/511 passing tests, 0 analyzer issues, Flutter 3.24+ compatibility refactoring.

---

## [1.0.0] - 2026-09-12

### 🌟 Fresh Public Release Baseline
- **Official Public Version**: Established fresh public release numbering baseline at **v1.0.0+1** (`versionName: 1.0.0`, `versionCode: 1`) for **Editor FS**.
- **Complete Feature Set Preserved**:
  - Full multi-track timeline editing engine (Video, Audio, Text, Stickers, Overlays).
  - High-performance native Android media playback pipeline with SurfaceTexture preview.
  - Interactive spatial transform canvas with pan, pinch-to-zoom, rotate, and horizontal/vertical flip.
  - Smart multi-layer alignment guides and magnetic center/edge auto-snapping.
  - Hardware-accelerated GPU shader transitions (12 styles) and 1080P MP4 export engine.
  - Non-destructive split-cut, ripple delete, clip duplicate, and universal multi-level undo/redo history.
  - Text-To-Speech (TTS) integration, sound effects library, and local draft persistence.
- **Architectural Stability**: 100% preservation of application ID, native bridges, MethodChannels, and security configurations.

---

## [2.4.11] - 2026-09-11

### 🏷️ Global App Branding Fix
- **Official App Name**: Renamed user-facing Android application display name to **Editor FS** across launcher, App Info, settings, and task switcher.
- **Android Manifest & Resources**: Added `@string/app_name` resource (`Editor FS`) and explicitly declared `android:label="@string/app_name"` on both `<application>` and `<activity android:name=".MainActivity">`.
- **Release Automation**: Updated GitHub Actions release workflow title and artifacts to reflect Editor FS.
- **Preserved Internal Compatibility**: Preserved all internal package IDs (`com.example.capcut_video_editor`), MethodChannels (`com.mahmas.studio/*`), backward compatibility typedefs, and keystore configurations.

---

### 🚀 Highlights & Major Features
- **Real-Time Visual Transition Rendering Engine**: Full multi-layer dual-video preview compositing with 12 distinct GPU-accelerated transition shaders (Fade, Dissolve, Slide Left/Right/Up/Down, Wipe Left/Right, Zoom In/Out, Flash Black/White).
- **Hardware-Accelerated Transition Export Pipeline**: Video compositing during gallery export embedding transition effects directly into exported MP4 media using Android MediaCodec & OpenGL ES.
- **Timeline Playhead Synchronization Engine**: Fixed playhead drift during playback by binding the timeline scrubber clock directly to native ExoPlayer position updates, with hard boundary clamping and zero end-of-clip drift.
- **CapCut-Like Split & Ripple Delete Engines**: Non-destructive split-cut trimming with adjacent transition validation and automatic ripple cleanup.
- **Full Test Suite & Quality Assurance**: 263/263 unit and widget tests passing with 0 static analysis issues. Verified on physical hardware (Realme RMX5003).

---

## [1.0.0] - 2026-08-28

### 🚀 Major Milestones & Architectural Redesign

#### Centralized MediaAsset Architecture
- Introduced canonical `MediaAsset` repository pattern across all timeline layers (`VideoClip`, `AudioTrack`, `OverlayClip`, `TextOverlay`).
- Decoupled timeline UI from raw file URIs and filesystem paths.
- Streamed Android Photo Picker `content://` URIs via native `ContentResolver` into private app storage (`context.filesDir/media/`).
- Automated native metadata extraction (precise duration probing and video frame thumbnail generation) via `MediaMetadataRetriever`.

#### Hardware-Accelerated Video Layer Controls
- **Playback**: Integrated Android `MediaPlayer` with `SurfaceTexture` / `Flutter Texture` for smooth zero-lag preview.
- **Speed Control**: Implemented dynamic variable speed scaling (0.25x – 4.0x) modifying native `MediaPlayer.playbackParams.speed` and recalculating active clip duration.
- **Volume Control**: Added per-clip volume slider (0% – 100%) mapped directly to native `MediaPlayer.setVolume()`, isolated per video clip.
- **Trimming**: Implemented non-destructive start/end trimming via draggable timeline handles and Toolbar quick-actions.
- **Split & Duplicate**: Implemented split at playhead (Part 1 & Part 2) and clip duplication to main timeline or PIP overlay.
- **Deletion**: Safe clip removal and automatic timeline duration recalculation.

#### Audio Layer Controls & Multi-Track Engine
- Supported direct local audio file import (`.mp3`, `.wav`, `.m4a`, `.aac`, `.ogg`).
- Multi-track timeline synchronization allowing external audio tracks to coexist with embedded video sound.
- Full audio editing: Split, Trim Left/Right, Speed (0.5x – 2.0x), Volume slider (0% – 100%), Mute toggle, Duplicate, and Delete.
- Auto-play prevention on track import to preserve user timeline positioning.

#### Text & Subtitle System
- Canvas text overlay rendering with real-time scaling, font sizing, and color swatches.
- Timeline integration supporting Text Split, Duplicate, Speed, and Delete.
- Integrated Android native `TextToSpeech` service for voice synthesis.

#### Project Persistence & Drafts Dashboard
- Automatic JSON project serialization (`ProjectStorageService`) on every timeline action.
- HomeScreen dashboard displaying recent drafts with real video thumbnails, durations, and clip counts.
- Seamless project reopening and state restoration.

#### UI & Clean-up
- Cleaned Add Clip media picker to display **only genuine user-imported media** (`Videos` and `Photos`).
- Removed all mock demo lists, sample assets, and fake dummy file generators.
- Removed legacy "Canvases" drawer and tab to streamline editing workflows.
- Fixed layout constraints in timeline clips preventing text and badge overflows on small clips.

---

### 🧪 Quality Assurance
- **Static Analysis**: `flutter analyze` completed with `0` issues.
- **Automated Tests**: `86/86` unit and widget tests passing.
- **Hardware Verification**: Verified live on physical Realme RMX5003 (Android 16 / API 36).
