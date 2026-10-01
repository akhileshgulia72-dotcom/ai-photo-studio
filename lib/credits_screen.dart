import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/rewarded_ad_service.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'GENERATION_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

const _bg = Color(0xFF0D0B12);
const _panel = Color(0xFF191521);
const _line = Color(0xFF30283A);
const _violet = Color(0xFFB69BFF);
const _pink = Color(0xFFF3A9D1);
const _muted = Color(0xFFAAA2B3);

class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  int credits = 0;
  String plan = 'free';
  bool loadingCredits = true;
  bool watchingAd = false;

  static const int rewardAmount = 5;

  @override
  void initState() {
    super.initState();
    RewardedAdService.preloadRewardedAd();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    if (mounted) setState(() => loadingCredits = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
        user = FirebaseAuth.instance.currentUser;
      }
      if (user == null) throw StateError('Firebase authentication is not ready.');

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw StateError('Firebase ID token is unavailable.');
      }

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/v1/profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      debugPrint('CreditsScreen: profile ${response.statusCode} ${response.body}');

      if (response.statusCode != 200) {
        throw StateError('Profile API returned HTTP ${response.statusCode}.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        credits = (data['credits'] as num?)?.toInt() ?? 0;
        plan = (data['plan'] as String?) ?? 'free';
        loadingCredits = false;
      });
    } catch (error) {
      debugPrint('CreditsScreen: failed to fetch credits: $error');
      if (mounted) setState(() => loadingCredits = false);
    }
  }

  Future<void> _watchAd() async {
    if (watchingAd) return;

    setState(() => watchingAd = true);
    try {
      final granted = await RewardedAdService.showRewardedAd(
        onAdPreparing: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Preparing your rewarded ad…'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onAdNotReady: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ad is not ready yet. Please try again in a moment.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onRewardGranted: (amount) {
          debugPrint('CreditsScreen: backend confirmed +$amount credits');
        },
        onRewardFailed: (error) {
          debugPrint('CreditsScreen: reward confirmation failed: $error');
        },
      );

      if (!granted) return;

      // Always re-read Firestore through the backend. Never increment locally.
      await _loadCredits();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+$rewardAmount credits added'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('CreditsScreen: rewarded ad error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not confirm the reward. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => watchingAd = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (credits / 50).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text(
          'AI Credits',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh credits',
            onPressed: loadingCredits ? null : _loadCredits,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF392B54),
                    Color(0xFF21182E),
                    _panel,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _violet.withValues(alpha: .30),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: _violet.withValues(alpha: .13),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: _violet,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 17),
                  const Text(
                    'Your AI Credits',
                    style: TextStyle(
                      fontSize: 16,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    loadingCredits ? '...' : '$credits',
                    style: const TextStyle(
                      fontSize: 48,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'credits available',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.play_circle_fill_rounded, color: _pink),
                      SizedBox(width: 10),
                      Text(
                        'Earn free credits',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Watch a short rewarded ad and get 5 AI credits.',
                    style: TextStyle(
                      color: _muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 17),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: watchingAd ? null : _watchAd,
                      icon: watchingAd
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.ondemand_video_rounded),
                      label: Text(
                        watchingAd
                            ? 'Waiting for reward...'
                            : 'Watch Ad  •  +5 Credits',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _violet,
                        foregroundColor: const Color(0xFF1A1424),
                        disabledBackgroundColor:
                            _violet.withValues(alpha: .35),
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const _HowItWorksCard(),

            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .025),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: _line),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: _muted,
                    size: 19,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Credits are used to create AI photos. One generation currently costs 10 credits.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How credits work',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 15),
          _CreditRow(
            icon: Icons.auto_awesome,
            title: 'AI photo generation',
            subtitle: '10 credits per generation',
          ),
          SizedBox(height: 13),
          _CreditRow(
            icon: Icons.play_circle_outline_rounded,
            title: 'Rewarded ad',
            subtitle: '+5 credits per completed ad',
          ),
          SizedBox(height: 13),
          _CreditRow(
            icon: Icons.card_giftcard_rounded,
            title: 'New creator',
            subtitle: '10 starting credits',
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _violet.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _violet, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
