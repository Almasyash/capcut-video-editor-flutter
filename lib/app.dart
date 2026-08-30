import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/theme/app_theme.dart';
import 'package:capcut_video_editor/ui/features/home/views/home_screen.dart';

/// Root application widget
class MahmasStudioApp extends StatelessWidget {
  const MahmasStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Editor FS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}

// Backward compatibility alias for existing test runners
typedef CapCutVideoEditorApp = MahmasStudioApp;
