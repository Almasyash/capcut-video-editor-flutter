# Mahmas Studio - Mobile & Web Video Editor (Flutter)

A modern, high-performance video editor application built with Flutter, branded as **Mahmas Studio**.

## 🚀 Key Features

- **🎬 Video Preview Canvas**:
  - Multi-aspect ratio canvas supporting **9:16** (TikTok, Reels, Shorts), **16:9** (YouTube), **1:1** (Instagram Square), and **4:5** (Portrait Feed).
  - High-precision timecode indicator (`00:04.12 / 00:20.00`).
  - Active subtitle / text overlay rendering on top of the live video.
  - Picture-in-Picture (PIP) secondary layers preview.
  - Interactive tap-to-play / pause toggle with smooth looping.

- **📁 Device Media & Audio Importing**:
  - Direct device storage upload for **Videos**, **Photos**, and **Audio Tracks**.
  - Dynamic duration, thumbnail gradient, and waveform generation for imported files.

- **✂️ Universal Multi-Track Timeline Trimming & Dragging**:
  - Interactive amber/cyan trim handles on all timeline tracks:
    - **Main Video Clips**: Draggable filmstrips and trim handles.
    - **Audio Tracks**: Draggable position and dual-handle duration trimming.
    - **PIP Overlay Layers**: Drag repositioning and edge resizing.
    - **Text / Subtitles**: Drag repositioning and edge resizing.
    - **Stickers & Badges**: Drag repositioning and edge resizing.
  - Scrollable time ruler with millisecond tick marks.
  - Fixed center playhead needle with cyan marker and white line.

- **🗂️ 8 Fully Functional Category Drawers**:
  - **Edit**: Split, Speed (0.5x–3.0x), Volume, Rotate 90°, Flip H/V, Opacity, Replace, Reverse, Freeze, Delete.
  - **Audio**: Music library (Lofi, Pop, Cinematic, EDM), Sound Effects, Voiceover Recording, and Device Audio Import.
  - **Text**: Subtitles with customizable styling, swatches, and Auto-Captions.
  - **Stickers**: Emojis, Vlog badges, Neon arrows, and Subscribe overlays.
  - **Effects**: Glitch Art, VHS Cam, RGB Split, Zoom Blur, Sparkles, Shake, Film Grain.
  - **Filters**: Color LUTs (Cinematic, Moody, Cyberpunk, Teal & Orange, Vintage, Sunset, B&W) with Intensity Slider.
  - **Canvas**: Background colors, Blur sigma (Soft, Med, High), and Aspect Ratio presets.
  - **Adjust**: Brightness, Contrast, Saturation, Exposure, Temperature, and Vignette color grading.

- **📤 Export & Rendering Engine**:
  - Resolution presets (720P, 1080P, 2K, 4K).
  - Frame rate presets (24 FPS, 30 FPS, 60 FPS).
  - Live export modal with progress percentage indicator and Mahmas Studio Render Engine.

---

## 🛠️ Running the Project

```bash
cd C:\Users\almas\.gemini\antigravity\scratch\capcut_video_editor
flutter run -d edge
```
Or run on Web:
```bash
flutter run -d web-server --web-port 8080
```

---

## 🧪 Testing

```bash
flutter test
```
