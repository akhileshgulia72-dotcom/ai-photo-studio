import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'email_auth_screen.dart';
import '../screens/studio_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoading();
        }
        final user = snapshot.data;
        if (user != null) return const StudioShell();
        return const SignInScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('canceled') || text.contains('cancelled')) {
      return 'Google Sign-In was cancelled.';
    }
    if (text.contains('network')) {
      return 'Check your internet connection and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/vyro_splash_3d.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -.24),
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF100B19)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x5509070E),
                  Color(0xAA09070E),
                  Color(0xEE09070E),
                  Color(0xFF09070E),
                ],
                stops: [0, .34, .72, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB69BFF), Color(0xFFF3A9D1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 42,
                          color: Color(0xFF191521),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Welcome to VYRO',
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Create, enhance and transform your photos.\nSign in to keep your creations safe.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFAAA2B3),
                          height: 1.5,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await AuthService.instance.signInWithGoogle();
                                }),
                          icon: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.account_circle_rounded),
                          label: Text(
                            _busy ? 'Signing in…' : 'Continue with Google',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF17131F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const EmailAuthScreen(),
                                  ),
                                ),
                          icon: const Icon(Icons.email_outlined),
                          label: const Text('Sign in with Email'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF3A3145)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await AuthService.instance.continueAsGuest();
                                }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF3A3145)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: const Text('Continue as Guest'),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFA6B8)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text(
                        'Guest accounts can be upgraded to Google later.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF77707F),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF0D0B12),
    body: Center(child: CircularProgressIndicator(color: Color(0xFFB69BFF))),
  );
}
