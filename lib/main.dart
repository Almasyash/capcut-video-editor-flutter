import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:capcut_video_editor/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    WindowsVideoPlayer.registerWith();
  }

  // Set system navigation & status bar styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F0F12),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const EditorFSApp());
}
