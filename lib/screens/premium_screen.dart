import 'dart:async';
import 'dart:ui';

import 'package:ai_photo_studio/screens/studio_shell.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/account_profile_service.dart';
import '../services/iap_purchase_service.dart';
import '../widgets/premium_background.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final IapPurchaseService _purchases = IapPurchaseService.instance;
  StreamSubscription<PurchaseUiEvent>? _purchaseSubscription;

  List<ProductDetails> _products = [];
  int? _credits;
  bool _available = false;
  bool _loading = true;
  bool _loadingBalance = true;
  bool _purchaseBusy = false;
  bool _verificationPending = false;
  String? _storeError;

  static const bg = Color(0xFF070711);
  static const text = Color(0xFFF8F5FF);
  static const muted = Color(0xFFA9A4BA);
  static const violet = Color(0xFF9B6CFF);
  static const pink = Color(0xFFFF78D8);

  @override
  void initState() {
    super.initState();
    _purchases.initialize();
    _purchaseSubscription = _purchases.events.listen(_onPurchaseEvent);
    _loadProducts();
    _loadBalance();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  void _onPurchaseEvent(PurchaseUiEvent event) {
    if (!mounted) return;
    setState(() {
      _purchaseBusy = event.kind == PurchaseEventKind.pending;
      if (event.kind == PurchaseEventKind.cancelled ||
          event.kind == PurchaseEventKind.failed) {
        _verificationPending = false;
      }
      if (event.kind == PurchaseEventKind.verificationPending) {
        _verificationPending = true;
      } else if (event.kind == PurchaseEventKind.verified) {
        _verificationPending = false;
        if (event.balance != null) _credits = event.balance;
      }
    });
    final String? message = switch (event.kind) {
      PurchaseEventKind.pending => 'Waiting for ${_purchases.storeName}…',
      PurchaseEventKind.cancelled => 'Purchase cancelled.',
      PurchaseEventKind.failed =>
        event.message ?? 'Purchase failed. Please try again.',
      PurchaseEventKind.verificationPending => event.message,
      PurchaseEventKind.verified =>
        event.duplicate
            ? 'This purchase was already synced to your account.'
            : '${event.creditsAdded} credits added to your account.',
      PurchaseEventKind.syncComplete =>
        'Transaction sync finished. Previously consumed credit packs are kept in your VYRO balance; Apple does not restore consumed packs.',
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _loadBalance() async {
    try {
      final profile = await AccountProfileService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _credits = profile.credits;
        _loadingBalance = false;
      });
    } catch (error) {
      debugPrint(
        'Credits screen: balance refresh failedType=${error.runtimeType}',
      );
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await _purchases.loadProducts();

      if (!mounted) return;
      setState(() {
        _available = true;
        _products = response.productDetails;
        _storeError = response.error == null
            ? response.notFoundIDs.isEmpty
                  ? null
                  : 'Some credit packs are not available in this storefront.'
            : 'Could not load store products. Please retry.';
        _loading = false;
      });

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'IAP: unavailable store product IDs: ${response.notFoundIDs}',
        );
      }
    } catch (error) {
      debugPrint('IAP: product query failedType=${error.runtimeType}');
      if (!mounted) return;
      setState(() {
        _available = false;
        _storeError =
            'Could not connect to ${_purchases.storeName}. Please retry.';
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
    if (_purchaseBusy || _verificationPending) return;
    try {
      setState(() => _purchaseBusy = true);
      final started = await _purchases.buy(product);
      if (!started && mounted) {
        setState(() => _purchaseBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_purchases.storeName} could not start the purchase.',
            ),
          ),
        );
      }
      // Entitlements are granted only from purchaseStream after server verification.
    } catch (error) {
      if (!mounted) return;
      setState(() => _purchaseBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_purchases.storeName} could not start this purchase.',
          ),
        ),
      );
    }
  }

  Widget _balanceCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF17131F).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: violet.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.toll_rounded, color: Color(0xFFC19EFF)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Current credit balance',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          Text(
            _loadingBalance ? '…' : (_credits?.toString() ?? '—'),
            style: const TextStyle(
              color: text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          IconButton(
            tooltip: 'Refresh balance',
            onPressed: _loadingBalance
                ? null
                : () {
                    setState(() => _loadingBalance = true);
                    _loadBalance();
                  },
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases() async {
    if (_purchaseBusy) return;
    try {
      setState(() => _purchaseBusy = true);
      await _purchases.recoverTransactions();
      await _loadBalance();
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
    final creator = _find(_purchases.creatorProductId);
    final pro = _find(_purchases.proProductId);

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
            child: _GlowOrb(size: 360, color: violet.withValues(alpha: .24)),
          ),

          Positioned(
            top: 420,
            left: -180,
            child: _GlowOrb(size: 350, color: pink.withValues(alpha: .10)),
          ),

          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 45),
              children: [
                _header(),

                const SizedBox(height: 28),

                _hero(),

                const SizedBox(height: 28),

                _balanceCard(),

                const SizedBox(height: 20),

                const _BenefitRow(),

                const SizedBox(height: 30),

                Text(
                  'Add AI credits',
                  style: TextStyle(
                    color: text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'One-time credit packs billed by ${_purchases.storeName}. '
                  'Credits are added after the store confirms the purchase.',
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.45,
                    decoration: TextDecoration.none,
                  ),
                ),

                const SizedBox(height: 16),

                _PlanCard(
                  name: _purchases.isApple ? 'VYRO Creator' : 'Creator Credits',
                  label: 'ONE-TIME CREDIT PACK',
                  credits: '${_purchases.creatorCredits}',
                  generations: '${_purchases.creatorCredits ~/ 10} generations',
                  price:
                      creator?.price ?? (_loading ? 'Loading…' : 'Unavailable'),
                  icon: Icons.auto_awesome_rounded,
                  features: const [
                    'Added to your VYRO balance',
                    'Use for AI photo generations',
                    'No recurring subscription',
                  ],
                  highlighted: false,
                  enabled:
                      creator != null &&
                      _available &&
                      !_purchaseBusy &&
                      !_verificationPending,
                  buttonText: 'Buy ${_purchases.creatorCredits} credits',
                  onPressed: creator == null ? null : () => _buy(creator),
                ),

                const SizedBox(height: 18),

                _PlanCard(
                  name: _purchases.isApple ? 'VYRO Pro Credits' : 'Pro Credits',
                  label: 'ONE-TIME CREDIT PACK',
                  credits: '${_purchases.proCredits}',
                  generations: '${_purchases.proCredits ~/ 10} generations',
                  price: pro?.price ?? (_loading ? 'Loading…' : 'Unavailable'),
                  icon: Icons.workspace_premium_rounded,
                  features: const [
                    'Added to your VYRO balance',
                    'Use for AI photo generations',
                    'No recurring subscription',
                  ],
                  highlighted: true,
                  enabled:
                      pro != null &&
                      _available &&
                      !_purchaseBusy &&
                      !_verificationPending,
                  buttonText: 'Buy ${_purchases.proCredits} credits',
                  onPressed: pro == null ? null : () => _buy(pro),
                ),

                const SizedBox(height: 22),

                _trustBar(),

                const SizedBox(height: 18),

                Center(
                  child: TextButton.icon(
                    onPressed: _loading || _purchaseBusy
                        ? null
                        : _restorePurchases,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Sync pending store transactions'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC4A1FF),
                    ),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  _loading
                      ? 'Connecting to ${_purchases.storeName}…'
                      : !_available
                      ? (_storeError ??
                            '${_purchases.storeName} is unavailable.')
                      : _verificationPending
                      ? 'A completed purchase is waiting for secure verification. Use sync to retry.'
                      : (_storeError ??
                            'Purchases are verified by VYRO before credits are added.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF777286),
                    fontSize: 10.5,
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),

                if (_storeError != null && !_loading)
                  TextButton.icon(
                    onPressed: _loadProducts,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry store connection'),
                  ),

                const SizedBox(height: 12),

                const Text(
                  'Consumed credit packs are not restored by the store. Your verified balance is saved to your VYRO account.',
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [violet, pink]),
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Text(
            'CREDITS',
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: violet.withValues(alpha: .35)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: pink, size: 15),
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
                    colors: [Color(0xFFBFA0FF), Color(0xFFFF8FD9)],
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
                  'Pick up credits for more AI photo generations. '
                  'Your current balance stays with your account.',
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
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE45AD1), Color(0xFF805AFF)],
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(color: pink.withValues(alpha: .35), blurRadius: 20),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 17),
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .09)),
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
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlighted
                    ? [const Color(0xFF261838), const Color(0xFF110E1C)]
                    : [const Color(0xFF191729), const Color(0xFF0F0E19)],
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
                    _PlanIcon(icon: icon, highlighted: highlighted),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                            colors: [pink, violet],
                          ),
                          borderRadius: BorderRadius.circular(100),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: highlighted
                              ? const [Color(0xFFFFA0DE), Color(0xFFB38AFF)]
                              : const [Colors.white, Color(0xFFD9D0F0)],
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
                        color: highlighted ? const Color(0xFFFFA1DE) : text,
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
                    color: Colors.white.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(100),
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

                Divider(color: Colors.white.withValues(alpha: .08), height: 1),

                const SizedBox(height: 15),

                for (final feature in features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
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
                            color: highlighted ? pink : const Color(0xFFB99BFF),
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
                              colors: [Color(0xFFFF9BDD), Color(0xFFA778FF)],
                            )
                          : LinearGradient(
                              colors: [
                                violet.withValues(alpha: .28),
                                const Color(0xFF5B4C7F).withValues(alpha: .35),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: highlighted
                          ? [
                              BoxShadow(
                                color: pink.withValues(alpha: .22),
                                blurRadius: 24,
                                spreadRadius: -5,
                              ),
                            ]
                          : null,
                    ),
                    child: FilledButton(
                      onPressed: enabled ? onPressed : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            highlighted
                                ? Icons.workspace_premium_rounded
                                : Icons.auto_awesome_rounded,
                            size: 19,
                            color: highlighted
                                ? const Color(0xFF1A1020)
                                : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            enabled ? buttonText : 'Unavailable',
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
                      colors: [Color(0xFF3B2761), Color(0xFF13101D)],
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
                    Colors.white.withValues(alpha: .13 * opacity),
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
                  color: Colors.white.withValues(alpha: .25 * opacity),
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
  const _PlanIcon({required this.icon, required this.highlighted});

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
              ? const [Color(0xFFFF8FDB), Color(0xFF9D75FF)]
              : const [Color(0xFF704E9F), Color(0xFF33274C)],
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted ? pink : violet).withValues(alpha: .23),
            blurRadius: 18,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: highlighted ? const Color(0xFF25132A) : Colors.white,
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
            icon: Icons.add_card_rounded,
            title: 'Credit',
            subtitle: 'Packs',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(
            icon: Icons.verified_user_outlined,
            title: 'Verified',
            subtitle: 'Purchases',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Saved',
            subtitle: 'To account',
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
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withValues(alpha: .075)),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFFC19EFF), size: 21),
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
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFFB993FF), size: 18),
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
  const _CircleButton({required this.icon, required this.onTap});

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
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

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
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
