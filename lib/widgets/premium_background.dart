import 'package:flutter/material.dart';
import '../models/photo_template.dart';

const _backgrounds = <String, String>{
  'home': 'assets/backgrounds/home_hero.webp',
  'create': 'assets/backgrounds/create_bg.webp',
  'premium': 'assets/backgrounds/premium_bg.webp',
  'enhancer': 'assets/backgrounds/enhancer_bg.webp',
  'profile': 'assets/backgrounds/profile_bg.webp',
  'result': 'assets/backgrounds/result_bg.webp',
};

/// Full-bleed image background. Local files are replaceable; absent files fall
/// back to a cached remote photograph and finally a quiet dark surface.
class PremiumBackground extends StatelessWidget {
  const PremiumBackground({
    super.key,
    required this.child,
    this.kind = 'home',
    this.overlay = .62,
  });
  final Widget child;
  final String kind;
  final double overlay;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        _backgrounds[kind] ?? _backgrounds['home']!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Image.network(
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1200&q=78',
          fit: BoxFit.cover,
          cacheWidth: 1200,
          errorBuilder: (context, error, stack) =>
              const ColoredBox(color: Color(0xFF0D0B12)),
        ),
      ),
      ColoredBox(color: const Color(0xFF0D0B12).withValues(alpha: overlay)),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x330D0B12), Color(0x990D0B12), Color(0xFF0D0B12)],
          ),
        ),
      ),
      child,
    ],
  );
}

/// Displays a standalone template thumbnail. Each template uses its own asset
/// so the card's BoxFit crop cannot reveal a neighboring atlas cell.
class TemplateArtwork extends StatelessWidget {
  const TemplateArtwork({
    super.key,
    required this.template,
    this.fit = BoxFit.cover,
  });
  final PhotoTemplate template;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
    template.imagePath,
    cacheWidth: 1200,
    fit: fit,
    errorBuilder: (context, error, stack) => const ColoredBox(
      color: Color(0xFF191521),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFFAAA2B3),
        ),
      ),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xCC191521),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0x55B69BFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'PREMIUM'});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD9251C30),
      border: Border.all(color: const Color(0x88F3A9D1)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    ),
  );
}
