import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../services/auth_service.dart';
import '../services/ump_consent_service.dart';
import 'auth_gate.dart';

class VyroSplashScreen extends StatefulWidget {
  const VyroSplashScreen({super.key});

  @override
  State<VyroSplashScreen> createState() => _VyroSplashScreenState();
}

class _VyroSplashScreenState extends State<VyroSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();
  bool _failed = false;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    setState(() {
      _initializing = true;
      _failed = false;
      _error = null;
    });
    final minimumDuration = Future<void>.delayed(
      const Duration(milliseconds: 2600),
    );
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // UMP refreshes the region-specific consent decision before any ad
      // service is allowed to initialize or load an ad.
      unawaited(UmpConsentService.instance.initialize());
      try {
        await AuthService.instance.initialize();
      } catch (_) {
        // Google Sign-In retries initialization when the user taps its button.
      }
      await minimumDuration;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const AuthGate(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } catch (_) {
      await minimumDuration;
      if (mounted) {
        setState(() {
          _failed = true;
          _error =
              'We couldn’t connect securely. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF09070E),
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/vyro_splash_3d.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF100B19)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x2209070E),
                Color(0x1109070E),
                Color(0x7709070E),
                Color(0xFF09070E),
              ],
              stops: [0, .35, .65, 1],
            ),
          ),
        ),
        SafeArea(
          child: AnimatedBuilder(
            animation: _entry,
            builder: (context, child) => Opacity(
              opacity: Curves.easeOut.transform(_entry.value),
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - _entry.value)),
                child: child,
              ),
            ),
            child: Column(
              children: [
                const Spacer(flex: 6),
                const Text(
                  'VYRO',
                  style: TextStyle(
                    fontSize: 44,
                    letterSpacing: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: [Shadow(color: Color(0x887D49FF), blurRadius: 24)],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'IMAGINE IT. BECOME IT.',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 3.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD5C9E8),
                  ),
                ),
                const SizedBox(height: 26),
                if (!_failed)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFE2C9FF),
                    ),
                  ),
                if (_failed) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error ?? 'Startup failed. Please try again.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE3D8EF)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _initializing ? null : _initialize,
                    child: const Text('Try again'),
                  ),
                ],
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
