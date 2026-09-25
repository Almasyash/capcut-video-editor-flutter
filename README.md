# Editor FS

<div align="center">

![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)
![Flutter](https://img.shields.io/badge/flutter-3.24+-02569B.svg?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-3.5+-0175C2.svg?logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Mobile%20(Android%2FiOS)%20%7C%20Laptop%20(Linux%2FWin%2FMac)-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-purple.svg)
![Organization](https://img.shields.io/badge/FS%20Groupz-FS--Groupz-orange.svg)

**A high-performance modern non-linear video editor for Mobile & Desktop built with Flutter, media_kit, and Riverpod.**  
*Developed for FS Groupz (`FS-Groupz`) and Almas CS (`Almasyash`).*

<br>

[![Download Android APK](https://img.shields.io/badge/Download-Android%20APK%20(v1.1.0)-success?style=for-the-badge&logo=android&logoColor=white)](https://github.com/FS-Groupz/Editor-FS/releases/download/v1.1.0/app-debug.apk)
[![Download Windows](https://img.shields.io/badge/Download-Windows%20Package-blue?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/FS-Groupz/Editor-FS/releases)
[![All Releases](https://img.shields.io/badge/All-Releases-orange?style=for-the-badge&logo=github&logoColor=white)](https://github.com/FS-Groupz/Editor-FS/releases)

</div>

---

## ⚡ Highlights (v1.1.0)

- 📱 **Mobile & Laptop Dual Support**:
  - **Laptops/Desktops**: Full professional 3-panel Non-Linear Editor (NLE) desktop application featuring responsive Media Library, Timeline Canvas, Preview Monitor, and Inspector panels (auto-activates when viewport width $\ge$ 850px).
  - **Mobile Phones (Android & iOS)**: Ultra-sleek CapCut-inspired mobile interface with touch-optimized gesture trimming, filmstrip scrubbing, responsive category tool drawers, and circular brand iconography.
  - **Android APK**: Native high-performance packaging targeting Android 14–16 (API 34–36) with zero-lag hardware video decoding and low memory footprint.
- 🎬 **Multi-Track Non-Linear Video Editor**:
  - Compose primary video tracks, secondary Picture-in-Picture (PIP) video overlays, text tracks, sticker layers, and audio waveforms with frame-accurate precision.
  - Features split-at-playhead, ripple delete, duplicate layers, and non-destructive trim handles.
  - Variable speed scaling (0.25x – 4.0x) with Bezier speed curve presets (Flash In, Flash Out, Montage, Hero).
- ⚡ **High-Performance Hardware Acceleration (`media_kit`)**:
  - Zero-lag video decoding and hardware-accelerated playback powered by `media_kit` (libmpv backend) and native GPU `Texture` streaming for smooth 60fps playback without memory leaks.
- 🌊 **Predictable Reactive State Architecture (`Riverpod`)**:
  - Unidirectional state management powered by `Riverpod` and MVVM architecture, ensuring deterministic timeline updates and command history (Undo/Redo with snapshot stack).
- 🎨 **GLSL Shader Transitions & Creative Filters**:
  - 17 GPU-accelerated GLSL fragment shader transitions (Crossfade, Fade to Black, Fade to White, Wipe, Slide, Radial, Circle, Zoom, Blur, Pixelate) with interactive timeline duration badges.
  - Real-time video filters (Cinematic, Vintage, Cyberpunk, Film, B&W) and color grading (Brightness, Contrast, Saturation, Temperature, Vignette).
- 🎵 **Multi-Track Audio & Waveform Extraction**:
  - Real-time background audio waveform peak extraction, volume automation (0% – 200%), beat detection snapping, and multi-track audio layering.
- 💾 **Robust File-Based Project Persistence & Auto-Save**:
  - Automatic background draft saving and recovery serializing project state atomically to JSON with temporary file swapping and crash fault tolerance.

---

## 🏗️ Architecture

```
editor-fs/
├── android/                    # Android native host (Gradle, Kotlin bridges)
├── ios/                        # iOS native host (Runner, Podfile)
├── windows/                    # Windows native C++ host (CMake, Runner)
├── macos/                      # macOS native host
├── linux/                      # Linux native host
├── test/                       # 512+ automated unit, widget & regression tests
├── assets/                     # App branding, sample media, and GLSL shaders
│   ├── images/                 # App logos & vector icons
│   └── shaders/transitions/    # 17 GLSL hardware-accelerated fragment shaders
├── lib/
│   ├── main.dart               # App entry point & Riverpod ProviderScope
│   ├── core/                   # Shared infrastructure & utilities
│   │   ├── constants/          # AppColors, AppDimensions, AppTypography
│   │   ├── services/           # media_kit player, audio extraction, project storage
│   │   └── utils/              # Time formatters, file helpers, math
│   ├── data/                   # Data sources & repositories
│   │   └── repositories/       # Asset repository & media library
│   ├── domain/                 # Core models & business entities
│   │   ├── enums/              # AspectRatio, TransitionType, VideoEffectType
│   │   └── models/             # Project, VideoClip, AudioTrack, TextOverlay
│   └── ui/                     # Presentation layer (Riverpod & MVVM)
│       ├── common/             # Reusable UI widgets, buttons & sliders
│       └── features/
│           ├── home/           # Project dashboard & draft management
│           └── editor/         # NLE editor workspace
│               ├── view_models/# EditorViewModel (Riverpod state notifier)
│               └── views/      # Preview monitor, multi-track timeline, drawers
```

---

## 🚀 Quick Start

### 1. Launch on Mobile (Android / iOS)
```bash
# Run on connected Android or iOS physical device / emulator
flutter run -d <device-id>
```

### 2. Launch on Laptop / Desktop (Windows, macOS, Linux)
```bash
# Run native desktop build
flutter run -d windows
```

### 3. Run Quality Assurance & Test Suite
```bash
# Run all 512+ unit, widget, and regression tests
flutter test

# Run static code analysis
flutter analyze
```

### 4. Build Production Packages
```bash
# Android APK
flutter build apk --release --android-skip-build-dependency-validation

# Windows Desktop Package
flutter build windows --release
```

---

## 📦 Dual-Repository Synchronization & GitHub Release Workflow

This project is actively maintained across two synchronized Git remotes:
- **Primary Repository (`FS-Groupz`)**: [https://github.com/FS-Groupz/Editor-FS.git](https://github.com/FS-Groupz/Editor-FS.git)
- **Mirror Repository (`Almas CS`)**: [https://github.com/Almasyash/capcut-video-editor-flutter.git](https://github.com/Almasyash/capcut-video-editor-flutter.git)

### Simultaneous Dual-Remote Git Setup

To keep both repositories in 100% parity with a single Git command:

```bash
# 1. Add primary and mirror remotes
git remote set-url origin https://github.com/FS-Groupz/Editor-FS.git
git remote add mirror https://github.com/Almasyash/capcut-video-editor-flutter.git

# 2. Configure 'all' remote to push to both GitHub remotes simultaneously
git remote add all https://github.com/FS-Groupz/Editor-FS.git
git remote set-url --add --push all https://github.com/FS-Groupz/Editor-FS.git
git remote set-url --add --push all https://github.com/Almasyash/capcut-video-editor-flutter.git

# 3. Push commits and release tags to both repositories at once
git push all main --tags
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.  
Developed by **FS Groupz** (`FS-Groupz`) & **Almas CS** (`Almasyash`).
