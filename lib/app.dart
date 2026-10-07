import 'package:flutter/material.dart';

import 'services/interstitial_ad_service.dart';
import 'screens/vyro_splash_screen.dart';

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
      title: 'VYRO',
      debugShowCheckedModeBanner: false,

      // Counts screen-to-screen moves so an interstitial lands on every 3rd
      // transition, subject to the service's own cooldown and entitlement
      // checks.
      navigatorObservers: [InterstitialNavigationObserver()],

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

      home: const VyroSplashScreen(),
    );
  }
}
