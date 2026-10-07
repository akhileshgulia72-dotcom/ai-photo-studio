import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:ai_photo_studio/screens/studio_shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/account_profile_service.dart';
import '../services/api_config.dart';
import '../widgets/premium_background.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  static const creatorProductId = 'vyro_creator_150';
  static const proProductId = 'vyro_pro_500';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  List<ProductDetails> _products = [];
  bool _available = false;
  bool _loading = true;
  bool _purchaseBusy = false;

  static const bg = Color(0xFF070711);
  static const text = Color(0xFFF8F5FF);
  static const muted = Color(0xFFA9A4BA);
  static const violet = Color(0xFF9B6CFF);
  static const pink = Color(0xFFFF78D8);

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error, StackTrace stack) {
        debugPrint('VYRO IAP stream error: $error');
        if (mounted) {
          setState(() => _purchaseBusy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchase status could not be read. Try again.')),
          );
        }
      },
    );
    _loadProducts();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!mounted) return;

      if (purchase.status == PurchaseStatus.pending) {
        setState(() => _purchaseBusy = true);
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        if (!mounted) return;
        setState(() => _purchaseBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(purchase.error?.message ?? 'Purchase failed.')),
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        setState(() => _purchaseBusy = true);
        try {
          await _verifyAndDeliver(purchase);
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          await AccountProfileService.instance.refresh(forceTokenRefresh: true);
          if (!mounted) return;
          setState(() => _purchaseBusy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchase verified and credits added.')),
          );
        } catch (error) {
          // Never complete an unverified purchase. The store can redeliver it.
          if (!mounted) return;
          setState(() => _purchaseBusy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Purchase verification pending: $error')),
          );
        }
      }
    }
  }

  Future<void> _verifyAndDeliver(PurchaseDetails purchase) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw StateError(
        'Apple purchase verification is not configured on the backend yet.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in before purchasing.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Your secure session expired.');
    }

    final purchaseToken = purchase.verificationData.serverVerificationData;
    if (purchaseToken.isEmpty) {
      throw StateError('Google Play purchase token is missing.');
    }

    final response = await http
        .post(
          Uri.parse('$generationApiBaseUrl/v1/iap/google/verify'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'productId': purchase.productID,
            'purchaseToken': purchaseToken,
          },
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      var message = 'The store could not verify this purchase.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw StateError(message);
    }
  }

  Future<void> _loadProducts() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        if (!mounted) return;
        setState(() {
          _available = false;
          _loading = false;
        });
        return;
      }

      final response = await _iap.queryProductDetails({
        creatorProductId,
        proProductId,
      });

      if (!mounted) return;
      setState(() {
        _available = true;
        _products = response.productDetails;
        _loading = false;
      });

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('VYRO IAP products not found: ${response.notFoundIDs}');
      }
    } catch (error) {
      debugPrint('VYRO IAP product load failed: $error');
      if (!mounted) return;
      setState(() {
        _available = false;
        _loading = false;
      });
    }
  }

  ProductDetails? _find(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Future<void> _buy(ProductDetails product) async {
    if (_purchaseBusy) return;
    try {
      setState(() => _purchaseBusy = true);
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started && mounted) {
        setState(() => _purchaseBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Play could not start the purchase.')),
        );
      }
      // Entitlements are granted only from purchaseStream after server verification.
    } catch (error) {
      if (!mounted) return;
      setState(() => _purchaseBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase could not start: $error')),
      );
    }
  }

  Future<void> _restorePurchases() async {
    if (_purchaseBusy) return;
    try {
      setState(() => _purchaseBusy = true);
      await _iap.restorePurchases();
    } catch (error) {
      if (!mounted) return;
      setState(() => _purchaseBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not restore purchases: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final creator = _find(creatorProductId);
    final pro = _find(proProductId);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: PremiumBackground(
              kind: 'premium',
              overlay: .84,
              child: const SizedBox.expand(),
            ),
          ),

          // Purple ambient light.
          Positioned(
            top: -150,
            right: -120,
            child: _GlowOrb(
              size: 360,
              color: violet.withValues(alpha: .24),
            ),
          ),

          Positioned(
            top: 420,
            left: -180,
            child: _GlowOrb(
              size: 350,
              color: pink.withValues(alpha: .10),
            ),
          ),

          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                45,
              ),
              children: [
                _header(),

                const SizedBox(height: 28),

                _hero(),

                const SizedBox(height: 28),

                const _BenefitRow(),

                const SizedBox(height: 30),

                const Text(
                  'Choose your creative power',
                  style: TextStyle(
                    color: text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'One-time purchases. No subscription. '
                  'Your credits stay in your VYRO account.',
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.45,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 16),

                _PlanCard(
                  name: 'Creator',
                  label: 'FOR EVERYDAY CREATORS',
                  credits: '250',
                  generations: '25 generations',
                  price: creator?.price ?? '₹149',
                  icon: Icons.auto_awesome_rounded,
                  features: const [
                    'Medium AI quality',
                    'No watermark',
                    'Premium templates',
                    'No forced ads',
                  ],
                  highlighted: false,
                  enabled: creator != null && _available && !_purchaseBusy,
                  buttonText: 'Get Creator',
                  onPressed:
                      creator == null ? null : () => _buy(creator),
                ),

                const SizedBox(height: 18),

                _PlanCard(
                  name: 'Pro',
                  label: 'FOR SERIOUS CREATORS',
                  credits: '800',
                  generations: '80 generations',
                  price: pro?.price ?? '₹399',
                  icon: Icons.workspace_premium_rounded,
                  features: const [
                    'High AI quality',
                    'No watermark',
                    'High-quality generation',
                    'Completely ad-free',
                    'Priority generation',
                  ],
                  highlighted: true,
                  enabled: pro != null && _available && !_purchaseBusy,
                  buttonText: 'Get Pro',
                  onPressed: pro == null ? null : () => _buy(pro),
                ),

                const SizedBox(height: 22),

                _trustBar(),

                const SizedBox(height: 18),

                Center(
                  child: TextButton.icon(
                    onPressed: _loading || _purchaseBusy ? null : _restorePurchases,
                    icon: const Icon(
                      Icons.restore_rounded,
                      size: 18,
                    ),
                    label: const Text(
                      'Recover a previous purchase',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC4A1FF),
                    ),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  _loading
                      ? 'Connecting to Google Play…'
                      : !_available
                          ? 'Google Play billing is unavailable on this device.'
                          : 'Purchases are securely verified before credits are added.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF777286),
                    fontSize: 10.5,
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Each generation costs 10 credits.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF625D70),
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        _CircleButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.maybePop(context),
        ),

        const SizedBox(width: 13),

        const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xFFFFA7E5),
          size: 20,
        ),

        const SizedBox(width: 7),

        const Text(
          'VYRO',
          style: TextStyle(
            color: text,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
            decoration: TextDecoration.none,
          ),
        ),

        const SizedBox(width: 8),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                violet,
                pink,
              ],
            ),
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Text(
            'PRO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
              decoration: TextDecoration.none,
            ),
          ),
        ),

        const Spacer(),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: violet.withValues(alpha: .35),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: pink,
                size: 15,
              ),
              SizedBox(width: 6),
              Text(
                'ONE-TIME',
                style: TextStyle(
                  color: Color(0xFFE8E1F3),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    return SizedBox(
      height: 235,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              const Text(
                'Create',
                style: TextStyle(
                  color: text,
                  fontSize: 45,
                  height: .94,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.3,
                  decoration: TextDecoration.none,
                ),
              ),

              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    colors: [
                      Color(0xFFBFA0FF),
                      Color(0xFFFF8FD9),
                    ],
                  ).createShader(bounds);
                },
                child: const Text(
                  'at your best.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 45,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),

              const SizedBox(height: 13),

              const SizedBox(
                width: 290,
                child: Text(
                  'Unlock more credits, cleaner exports '
                  'and a more powerful VYRO experience.',
                  style: TextStyle(
                    color: Color(0xFFBDB7CC),
                    fontSize: 14,
                    height: 1.45,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),

          // Rear artwork.
          Positioned(
            right: -22,
            top: -8,
            child: Transform.rotate(
              angle: .10,
              child: _ArtworkCard(
                asset: 'assets/templates/luxury_black_suit.jpg',
                width: 128,
                height: 170,
                opacity: .42,
              ),
            ),
          ),

          // Front artwork.
          Positioned(
            right: 27,
            top: 28,
            child: Transform.rotate(
              angle: -.055,
              child: _ArtworkCard(
                asset: 'assets/templates/ceo_portrait.jpg',
                width: 145,
                height: 190,
                opacity: 1,
              ),
            ),
          ),

          // Floating AI badge.
          Positioned(
            right: 15,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE45AD1),
                    Color(0xFF805AFF),
                  ],
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: pink.withValues(alpha: .35),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'AI POWERED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 17,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: .09),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: _TrustItem(
                  icon: Icons.lock_outline_rounded,
                  label: 'Secure',
                ),
              ),
              _Divider(),
              Expanded(
                child: _TrustItem(
                  icon: Icons.payments_outlined,
                  label: 'One-time',
                ),
              ),
              _Divider(),
              Expanded(
                child: _TrustItem(
                  icon: Icons.all_inclusive_rounded,
                  label: 'No renewal',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.label,
    required this.credits,
    required this.generations,
    required this.price,
    required this.icon,
    required this.features,
    required this.highlighted,
    required this.enabled,
    required this.buttonText,
    required this.onPressed,
  });

  final String name;
  final String label;
  final String credits;
  final String generations;
  final String price;
  final IconData icon;
  final List<String> features;
  final bool highlighted;
  final bool enabled;
  final String buttonText;
  final VoidCallback? onPressed;

  static const text = Color(0xFFF8F5FF);
  static const muted = Color(0xFFA9A4BA);
  static const violet = Color(0xFF9B6CFF);
  static const pink = Color(0xFFFF78D8);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: pink.withValues(alpha: .18),
                  blurRadius: 35,
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 20,
            sigmaY: 20,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              18,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlighted
                    ? [
                        const Color(0xFF261838),
                        const Color(0xFF110E1C),
                      ]
                    : [
                        const Color(0xFF191729),
                        const Color(0xFF0F0E19),
                      ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                width: highlighted ? 1.4 : 1,
                color: highlighted
                    ? pink.withValues(alpha: .72)
                    : Colors.white.withValues(alpha: .10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PlanIcon(
                      icon: icon,
                      highlighted: highlighted,
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: highlighted
                                  ? const Color(0xFFFFB4E7)
                                  : const Color(0xFFB9AFD2),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            name,
                            style: const TextStyle(
                              color: text,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (highlighted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              pink,
                              violet,
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'BEST VALUE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .7,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: highlighted
                              ? const [
                                  Color(0xFFFFA0DE),
                                  Color(0xFFB38AFF),
                                ]
                              : const [
                                  Colors.white,
                                  Color(0xFFD9D0F0),
                                ],
                        ).createShader(bounds);
                      },
                      child: Text(
                        credits,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          height: .9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    const Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text(
                        'CREDITS',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                    const Spacer(),

                    Text(
                      price,
                      style: TextStyle(
                        color: highlighted
                            ? const Color(0xFFFFA1DE)
                            : text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.6,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 7),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: .055,
                    ),
                    borderRadius:
                        BorderRadius.circular(100),
                  ),
                  child: Text(
                    generations,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),

                const SizedBox(height: 17),

                Divider(
                  color: Colors.white.withValues(alpha: .08),
                  height: 1,
                ),

                const SizedBox(height: 15),

                for (final feature in features)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 11,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: highlighted
                                ? pink.withValues(alpha: .15)
                                : violet.withValues(alpha: .15),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: highlighted
                                ? pink
                                : const Color(0xFFB99BFF),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: Color(0xFFD3CEDF),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 5),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: highlighted
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFFF9BDD),
                                Color(0xFFA778FF),
                              ],
                            )
                          : LinearGradient(
                              colors: [
                                violet.withValues(alpha: .28),
                                const Color(0xFF5B4C7F)
                                    .withValues(alpha: .35),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: highlighted
                          ? [
                              BoxShadow(
                                color: pink.withValues(
                                  alpha: .22,
                                ),
                                blurRadius: 24,
                                spreadRadius: -5,
                              ),
                            ]
                          : null,
                    ),
                    child: FilledButton(
                      onPressed: enabled ? onPressed : null,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Colors.transparent,
                        disabledBackgroundColor:
                            Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(18),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                            highlighted
                                ? Icons
                                    .workspace_premium_rounded
                                : Icons
                                    .auto_awesome_rounded,
                            size: 19,
                            color: highlighted
                                ? const Color(0xFF1A1020)
                                : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            enabled
                                ? buttonText
                                : 'Unavailable',
                            style: TextStyle(
                              color: highlighted
                                  ? const Color(0xFF1A1020)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: highlighted
                                ? const Color(0xFF1A1020)
                                : Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkCard extends StatelessWidget {
  const _ArtworkCard({
    required this.asset,
    required this.width,
    required this.height,
    required this.opacity,
  });

  final String asset;
  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: violet.withValues(alpha: .30),
            blurRadius: 32,
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF3B2761),
                        Color(0xFF13101D),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFE0C6FF),
                    size: 40,
                  ),
                );
              },
            ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(
                      alpha: .13 * opacity,
                    ),
                    Colors.transparent,
                    Colors.black.withValues(alpha: .45),
                  ],
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: .25 * opacity,
                  ),
                  width: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanIcon extends StatelessWidget {
  const _PlanIcon({
    required this.icon,
    required this.highlighted,
  });

  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 49,
      height: 49,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: highlighted
              ? const [
                  Color(0xFFFF8FDB),
                  Color(0xFF9D75FF),
                ]
              : const [
                  Color(0xFF704E9F),
                  Color(0xFF33274C),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted ? pink : violet)
                .withValues(alpha: .23),
            blurRadius: 18,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: highlighted
            ? const Color(0xFF25132A)
            : Colors.white,
        size: 24,
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _Benefit(
            icon: Icons.image_outlined,
            title: 'Premium',
            subtitle: 'Templates',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(
            icon: Icons.no_photography_outlined,
            title: 'No',
            subtitle: 'Watermark',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(
            icon: Icons.bolt_rounded,
            title: 'Fast',
            subtitle: 'Creation',
          ),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 14,
          sigmaY: 14,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 7,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: Colors.white.withValues(alpha: .075),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: const Color(0xFFC19EFF),
                size: 21,
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF9D98AD),
                  fontSize: 9.5,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: const Color(0xFFB993FF),
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFD0CADF),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 23,
      color: Colors.white.withValues(alpha: .08),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .055),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}