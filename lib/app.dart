import 'package:flutter/material.dart';
import 'screens/studio_shell.dart';

class AiPhotoStudioApp extends StatelessWidget {
  const AiPhotoStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    const scheme = ColorScheme.dark(
      primary: Color(0xFFA78BFA),
      secondary: Color(0xFFF9A8D8),
      surface: Color(0xFF17131F),
    );
    return MaterialApp(
      title: 'AI Photo Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0D0B12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const StudioShell(),
    );
  }
}
