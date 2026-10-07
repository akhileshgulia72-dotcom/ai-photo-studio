import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:ai_photo_studio/credits_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/photo_template.dart';
import '../services/image_generation_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/ump_consent_service.dart';
import '../services/creation_service.dart';
import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../services/account_profile_service.dart';
import '../services/gallery_save_service.dart';

import 'premium_screen.dart';
import '../widgets/premium_background.dart';
import 'photo_tools_screen.dart';

const bg = Color(0xFF0D0B12);
const panel = Color(0xFF191521);
const line = Color(0xFF30283A);
const violet = Color(0xFFB69BFF);
const pink = Color(0xFFF3A9D1);
const muted = Color(0xFFAAA2B3);

class Creation {
  const Creation({
    required this.template,
    this.image,
    this.id,
    this.generationId,
    this.storagePath,
    this.createdAt,
    this.creditsUsed = 10,
    this.watermark = true,
  });
  final PhotoTemplate template;
  final Uri? image;
  final String? id;
  final String? generationId;
  final String? storagePath;
  final DateTime? createdAt;
  final int creditsUsed;
  final bool watermark;
}

class _PendingPhotoPickStore {
  static Future<File> get _record async {
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/vyro_pending_photo.json');
  }

  static Future<void> save({
    required String templateId,
    String? sourcePath,
    String stage = 'picker',
  }) async {
    try {
      final file = await _record;
      await file.writeAsString(
        jsonEncode({
          'templateId': templateId,
          'sourcePath': sourcePath,
          'stage': stage,
          if (stage == 'cropping')
            'cropStartedAt': DateTime.now().millisecondsSinceEpoch,
        }),
        flush: true,
      );
    } catch (_) {
      // Photo selection remains usable if temporary storage is unavailable.
    }
  }

  static Future<Map<String, dynamic>?> read() async {
    try {
      final file = await _record;
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _record;
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale marker is harmless; recovery validates all referenced files.
    }
  }
}

Future<File> _copyPhotoToAppCache(File source) async {
  try {
    if (!await source.exists() || await source.length() == 0) return source;
    final directory = await getTemporaryDirectory();
    final destination = File(
      '${directory.path}/vyro-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    return await source.copy(destination.path);
  } catch (_) {
    return source;
  }
}

class StudioShell extends StatefulWidget {
  const StudioShell({super.key});
  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int tab = 0;
  final creations = <Creation>[];
  final _creationService = CreationService();
  bool _loadingCreations = false;
  String? _creationsError;

  @override
  void initState() {
    super.initState();
    InterstitialAdService.preload();
    RewardedAdService.preloadRewardedAd();
    _loadSavedCreations();
    unawaited(_restoreInterruptedPhotoPick());
  }

  Future<void> _restoreInterruptedPhotoPick() async {
    try {
      final pending = await _PendingPhotoPickStore.read();
      if (pending == null) return;
      final templateId = pending['templateId']?.toString();
      PhotoTemplate? template;
      for (final candidate in TemplateCatalog.all) {
        if (candidate.id == templateId) {
          template = candidate;
          break;
        }
      }

      File? recoveredPhoto;
      final savedSourcePath = pending['sourcePath']?.toString();
      if (savedSourcePath != null && savedSourcePath.isNotEmpty) {
        try {
          final recoveredCrop = pending['stage'] == 'cropping'
              ? await ImageCropper().recoverImage()
              : null;
          if (recoveredCrop != null) {
            final cropFile = File(recoveredCrop.path);
            final startedAt = (pending['cropStartedAt'] as num?)?.toInt() ?? 0;
            if (await cropFile.exists() && await cropFile.length() > 0) {
              final changedAt = await cropFile.lastModified();
              if (changedAt.millisecondsSinceEpoch >= startedAt) {
                recoveredPhoto = cropFile;
              }
            }
          }
        } catch (_) {
          // Fall back to the durable source copy saved before opening UCrop.
        }
        if (recoveredPhoto == null) {
          final source = File(savedSourcePath);
          if (await source.exists() && await source.length() > 0) {
            recoveredPhoto = source;
          }
        }
      } else {
        try {
          final lost = await ImagePicker().retrieveLostData();
          final picked =
              lost.file ??
              ((lost.files?.isNotEmpty ?? false) ? lost.files!.first : null);
          if (picked != null) {
            recoveredPhoto = await _copyPhotoToAppCache(File(picked.path));
          }
        } catch (_) {
          // The system photo picker may not have returned a recoverable file.
        }
      }

      await _PendingPhotoPickStore.clear();
      if (!mounted) return;
      if (template == null || recoveredPhoto == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your photo selection was interrupted. Please choose the photo again.',
                ),
              ),
            );
          }
        });
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          _pushPhotoSelection(template!, initialPhoto: recoveredPhoto);
      });
    } catch (_) {
      await _PendingPhotoPickStore.clear();
    }
  }

  Future<void> _loadSavedCreations() async {
    if (_loadingCreations) return;
    setState(() => _loadingCreations = true);
    try {
      final saved = await _creationService.fetchMine();
      final loaded = <Creation>[];
      for (final item in saved) {
        PhotoTemplate? template;
        for (final candidate in TemplateCatalog.all) {
          if (candidate.id == item.templateId) {
            template = candidate;
            break;
          }
        }
        if (template == null) continue;
        loaded.add(
          Creation(
            id: item.id,
            generationId: item.id,
            template: template,
            image: item.imageUrl,
            storagePath: item.storagePath,
            createdAt: item.createdAt,
            creditsUsed: item.creditsUsed,
            watermark: item.watermark,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _creationsError = null;
          creations
            ..clear()
            ..addAll(loaded);
        });
      }
    } catch (error) {
      debugPrint('VYRO creations: failed to load: $error');
      if (mounted)
        setState(() => _creationsError = "Couldn't load your creations");
    } finally {
      if (mounted) setState(() => _loadingCreations = false);
    }
  }

  void openTemplate(PhotoTemplate template) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TemplateDetailsScreen(
          template: template,
          onUse: () => openPhoto(template),
        ),
      ),
    );
  }

  Future<void> openTemplateCard(PhotoTemplate template) async {
    await InterstitialAdService.showForTemplateCardClick(context);
    if (mounted) openTemplate(template);
  }

  void openPhoto(PhotoTemplate template) {
    _pushPhotoSelection(template);
  }

  void _pushPhotoSelection(PhotoTemplate template, {File? initialPhoto}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PhotoSelectionScreen(
          template: template,
          initialPhoto: initialPhoto,
          onGenerated: _showGeneratedResult,
        ),
      ),
    );
  }

  void _showGeneratedResult(Creation creation) {
    setState(() => creations.insert(0, creation));
    unawaited(_loadSavedCreations());
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ResultScreen(creation: creation, onTemplate: openTemplateCard),
      ),
    );
  }

  Future<void> _changeTab(int value) async {
    if (value == tab) return;
    setState(() => tab = value);
    if (value == 2) unawaited(_loadSavedCreations());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onTemplate: openTemplate, onTemplateCard: openTemplateCard),
      CreateScreen(onTemplate: openTemplateCard),
      CreationsScreen(
        creations: creations,
        loading: _loadingCreations,
        error: _creationsError,
        onRetry: _loadSavedCreations,
      ),
      const PremiumScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: bg,
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF15121B),
        indicatorColor: violet.withValues(alpha: .17),
        selectedIndex: tab,
        onDestinationSelected: _changeTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Creations',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium_rounded),
            label: 'Premium',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onTemplate,
    required this.onTemplateCard,
  });
  final ValueChanged<PhotoTemplate> onTemplate;
  final ValueChanged<PhotoTemplate> onTemplateCard;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final search = TextEditingController();
  String category = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.toLowerCase();
    final matches = TemplateCatalog.all
        .where(
          (t) =>
              (category == 'All' ||
                  t.categoryLabel == category ||
                  (category == 'Trending' && t.isTrending)) &&
              (query.isEmpty ||
                  t.title.toLowerCase().contains(query) ||
                  t.categoryLabel.toLowerCase().contains(query)),
        )
        .toList();
    return PremiumBackground(
      kind: 'home',
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI PHOTO STUDIO',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                                color: pink,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'Create Your Best Look',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _HomeCreditBalance(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Transform your photos with AI.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF392B54),
                          Color(0xFF20182D),
                          Color(0xFF17131F),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: violet.withValues(alpha: .28)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'YOUR NEXT LOOK AWAITS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: pink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Your next\nportrait starts here.',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Pick a style. Weâ€™ll take it from here.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFD5CCDF),
                                ),
                              ),
                              const SizedBox(height: 15),
                              FilledButton.icon(
                                onPressed: () => widget.onTemplate(
                                  TemplateCatalog.all.first,
                                ),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                ),
                                label: const Text('Create Photo'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: violet,
                                  foregroundColor: const Color(0xFF1A1424),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const _HeroArt(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 21),
                  const _SectionTitle(
                    'Featured templates',
                    'Editorial picks for your next portrait',
                  ),
                  const SizedBox(height: 11),
                  SizedBox(
                    height: 198,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final template in TemplateCatalog.all.take(4))
                          _FeaturedTemplateCard(
                            template: template,
                            onTap: () => widget.onTemplateCard(template),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search templates',
                      hintStyle: const TextStyle(color: muted),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: muted,
                      ),
                      filled: true,
                      fillColor: panel,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: line),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle(
                    'Explore categories',
                    'Find your kind of extraordinary',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children:
                          [
                                'All',
                                'Trending',
                                'Professional',
                                'Luxury',
                                'Cinematic',
                                'Indian & Festivals',
                                'Couple',
                                'Social Media',
                                'Travel',
                                'Creative',
                              ]
                              .map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(c),
                                    selected: category == c,
                                    onSelected: (_) =>
                                        setState(() => category = c),
                                    selectedColor: violet.withValues(
                                      alpha: .22,
                                    ),
                                    backgroundColor: panel,
                                    side: BorderSide(
                                      color: category == c
                                          ? violet.withValues(alpha: .5)
                                          : line,
                                    ),
                                    labelStyle: TextStyle(
                                      color: category == c
                                          ? Colors.white
                                          : muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    query.isNotEmpty || category != 'All'
                        ? 'Matching styles'
                        : 'Trending now',
                    '${matches.length} looks to try',
                  ),
                  const SizedBox(height: 13),
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          'No styles found. Try another search.',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    )
                  else
                    _TemplateGrid(
                      templates: matches,
                      onTap: widget.onTemplateCard,
                      showNativeAds: true,
                    ),
                  const SizedBox(height: 24),
                  if (query.isEmpty && category == 'All') ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'Popular templates',
                      'Looks creators love',
                    ),
                    const SizedBox(height: 13),
                    _TemplateGrid(
                      templates: TemplateCatalog.all.skip(1).take(4).toList(),
                      onTap: widget.onTemplateCard,
                      showNativeAds: true,
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle(
                      'Premium looks',
                      'A little extra magic',
                    ),
                    const SizedBox(height: 12),
                    _TemplateGrid(
                      templates: TemplateCatalog.all
                          .where((t) => t.isPremium)
                          .toList(),
                      onTap: widget.onTemplateCard,
                      showNativeAds: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: line),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, color: pink),
                        SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'For best results, use a clear front-facing photo in soft light.',
                            style: TextStyle(
                              color: Color(0xFFD5CCDF),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(25),
    child: SizedBox(
      width: 88,
      height: 134,
      child: TemplateArtwork(template: TemplateCatalog.all.first),
    ),
  );
}

class _FeaturedTemplateCard extends StatelessWidget {
  const _FeaturedTemplateCard({required this.template, required this.onTap});
  final PhotoTemplate template;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 11),
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 145,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              TemplateArtwork(template: template),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD0D0B12)],
                  ),
                ),
              ),
              Positioned(
                left: 11,
                right: 8,
                bottom: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (template.isPremium)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: PremiumBadge(),
                      ),
                    Text(
                      template.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeCreditBalance extends StatefulWidget {
  const _HomeCreditBalance();
  @override
  State<_HomeCreditBalance> createState() => _HomeCreditBalanceState();
}

class _HomeCreditBalanceState extends State<_HomeCreditBalance> {
  int? credits;
  int? generations;
  String plan = 'free';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final profile = await AccountProfileService.instance.refresh();
        if (!mounted) return;
        setState(() {
          credits = profile.credits;
          generations = profile.totalGenerations;
          plan = profile.plan;
        });
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: pink),
              const SizedBox(width: 4),
              Text(
                credits?.toString() ?? 'Â·Â·Â·',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            plan.toUpperCase(),
            style: const TextStyle(
              fontSize: 8,
              letterSpacing: .7,
              color: muted,
            ),
          ),
          if (generations != null) ...[
            const SizedBox(height: 2),
            Text(
              '${generations!} creations',
              style: const TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
    ],
  );
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({
    required this.templates,
    required this.onTap,
    this.showNativeAds = false,
    this.adInterval = 4,
    this.compactNativeAds = false,
    this.trailingNativeAds = 0,
  });
  final List<PhotoTemplate> templates;
  final ValueChanged<PhotoTemplate> onTap;
  final bool showNativeAds;
  final bool compactNativeAds;
  final int adInterval;

  /// Extra native ads appended after the final group, used to stack ad slots
  /// below a result image.
  final int trailingNativeAds;

  @override
  Widget build(BuildContext context) {
    final interval = adInterval < 1 ? 1 : adInterval;
    final chunks = <List<PhotoTemplate>>[];
    for (var i = 0; i < templates.length; i += interval) {
      chunks.add(
        templates.sublist(i, (i + interval).clamp(0, templates.length)),
      );
    }
    return Column(
      children: [
        for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: chunks[chunkIndex].length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .72,
            ),
            itemBuilder: (context, i) => _TemplateCard(
              template: chunks[chunkIndex][i],
              onTap: () => onTap(chunks[chunkIndex][i]),
            ),
          ),
          // A native ad follows every group, including the final one, so all
          // four templates are always followed by an ad slot.
          if (showNativeAds && chunkIndex < 5)
            _NativeAdBlock(compact: compactNativeAds),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < trailingNativeAds; i++) ...[
          _NativeAdBlock(compact: compactNativeAds),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _NativeAdBlock extends StatefulWidget {
  const _NativeAdBlock({this.compact = false});
  final bool compact;
  @override
  State<_NativeAdBlock> createState() => _NativeAdBlockState();
}

class _NativeAdBlockState extends State<_NativeAdBlock> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _adFree = false;
  bool _loading = false;

  // Production Native Advanced ad units, one per platform.
  // This app intentionally uses the production unit in all builds.
  static const _androidUnitId = 'ca-app-pub-7694497723149363/6374835026';
  static const _iosUnitId = 'ca-app-pub-7694497723149363/7462595539';
  static String get _unitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _iosUnitId
          : _androidUnitId;

  @override
  void initState() {
    super.initState();
    UmpConsentService.instance.addListener(_onConsentChanged);
    _loadIfAllowed();
  }

  void _onConsentChanged() {
    if (!UmpConsentService.instance.adsAllowed) {
      _ad?.dispose();
      _ad = null;
      if (mounted) {
        setState(() {
          _loaded = false;
          _adFree = true;
        });
      }
      return;
    }
    if (mounted) setState(() => _adFree = false);
    unawaited(_loadIfAllowed());
  }

  Future<void> _loadIfAllowed() async {
    if (_loading || _ad != null) return;
    _loading = true;
    try {
      if (!await UmpConsentService.instance.canRequestAds()) {
        _adFree = true;
        return;
      }
      final profile = await AccountProfileService.instance.refresh();
      if (!mounted || profile.isAdFree) {
        _adFree = true;
        return;
      }
    } catch (_) {
      // Hide ads unless entitlement can be verified.
      _adFree = true;
      return;
    } finally {
      _loading = false;
    }
    if (!mounted || _unitId.isEmpty || !UmpConsentService.instance.adsAllowed) {
      return;
    }
    _ad = NativeAd(
      adUnitId: _unitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.compact ? TemplateType.small : TemplateType.medium,
        mainBackgroundColor: Color(0xFF191521),
        cornerRadius: widget.compact ? 14 : 18,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!UmpConsentService.instance.adsAllowed) {
            ad.dispose();
            return;
          }
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    UmpConsentService.instance.removeListener(_onConsentChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_adFree || !_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        height: widget.compact ? 132 : 300,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
          border: Border.all(color: line),
        ),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final PhotoTemplate template;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TemplateArtwork(template: template),
                Positioned(
                  left: 9,
                  top: 9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      template.categoryLabel.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (template.isPremium)
                  const Positioned(right: 9, top: 9, child: PremiumBadge()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_outward_rounded, color: pink, size: 15),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

List<Color> _palette(PhotoTemplate t) {
  final i = TemplateCatalog.all.indexOf(t) % 5;
  const palettes = [
    [Color(0xFF28283D), Color(0xFF78608D)],
    [Color(0xFF352033), Color(0xFFAD6F79)],
    [Color(0xFF1D3440), Color(0xFF5E8490)],
    [Color(0xFF443225), Color(0xFFB68B61)],
    [Color(0xFF342849), Color(0xFF8A73B7)],
  ];
  return palettes[i];
}

class TemplateDetailsScreen extends StatelessWidget {
  const TemplateDetailsScreen({
    super.key,
    required this.template,
    required this.onUse,
  });
  final PhotoTemplate template;
  final VoidCallback onUse;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Template details')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 360,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _palette(template),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        TemplateArtwork(
                          template: template,
                          fit: template.id == 'luxury_car'
                              ? BoxFit.contain
                              : BoxFit.cover,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  template.categoryLabel.toUpperCase(),
                  style: const TextStyle(
                    color: pink,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  template.title,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  template.description,
                  style: const TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.ad_units_rounded, size: 14, color: muted),
                    SizedBox(width: 6),
                    Text(
                      'SPONSORED',
                      style: TextStyle(
                        color: muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const _NativeAdBlock(compact: true),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  children: [
                    _InfoPill(
                      Icons.auto_awesome,
                      '${template.creditsRequired} credit${template.creditsRequired == 1 ? '' : 's'}',
                    ),
                    _InfoPill(
                      template.isPremium
                          ? Icons.workspace_premium
                          : Icons.check_circle_outline,
                      template.isPremium ? 'Premium' : 'Free to try',
                    ),
                    _InfoPill(
                      Icons.crop_portrait_outlined,
                      template.aspectRatio,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Your photo, reimagined',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                const Text(
                  'AI uses this look as inspiration while keeping your face, expression, skin and hair unchanged.',
                  style: TextStyle(color: muted, height: 1.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 53,
              child: FilledButton.icon(
                onPressed: onUse,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Use this template'),
                style: FilledButton.styleFrom(
                  backgroundColor: violet,
                  foregroundColor: const Color(0xFF1A1424),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 15, color: pink),
    label: Text(text, style: const TextStyle(fontSize: 11)),
    backgroundColor: panel,
    side: const BorderSide(color: line),
    visualDensity: VisualDensity.compact,
  );
}

class PhotoSelectionScreen extends StatefulWidget {
  const PhotoSelectionScreen({
    super.key,
    required this.template,
    required this.onGenerated,
    this.initialPhoto,
  });
  final PhotoTemplate template;
  final ValueChanged<Creation> onGenerated;
  final File? initialPhoto;
  @override
  State<PhotoSelectionScreen> createState() => _PhotoSelectionScreenState();
}

class _PhotoSelectionScreenState extends State<PhotoSelectionScreen> {
  final picker = ImagePicker();
  final cropper = ImageCropper();
  final service = BackendImageGenerationService();
  File? originalPhoto;
  File? photo;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    originalPhoto = widget.initialPhoto;
    photo = widget.initialPhoto;
  }

  Future<void> pick(ImageSource source) async {
    XFile? picked;
    try {
      await _PendingPhotoPickStore.save(templateId: widget.template.id);
      picked = await picker.pickImage(
        source: source,
        // Downsample in the platform picker before the image reaches Dart or
        // the cropper. Large 12–48 MP camera files can otherwise exhaust RAM.
        maxWidth: 1536,
        maxHeight: 2048,
        imageQuality: 86,
        requestFullMetadata: false,
      );
    } catch (_) {
      await _PendingPhotoPickStore.clear();
      if (mounted) {
        setState(
          () => error = 'Could not open that photo source. Please try again.',
        );
      }
      return;
    }
    if (picked == null || !mounted) {
      await _PendingPhotoPickStore.clear();
      return;
    }

    await _PendingPhotoPickStore.save(
      templateId: widget.template.id,
      sourcePath: picked.path,
      stage: 'ready',
    );
    final sourceFile = await _copyPhotoToAppCache(File(picked.path));
    if (!await sourceFile.exists() || await sourceFile.length() == 0) {
      await _PendingPhotoPickStore.clear();
      if (mounted)
        setState(
          () => error = 'That photo could not be read. Please choose another.',
        );
      return;
    }
    await _PendingPhotoPickStore.save(
      templateId: widget.template.id,
      sourcePath: sourceFile.path,
      stage: 'ready',
    );
    // Keep the source available immediately. If Android closes the activity
    // while UCrop is open, the user still has a valid image to continue with.
    setState(() {
      originalPhoto = sourceFile;
      photo = sourceFile;
      error = null;
    });
    try {
      await _PendingPhotoPickStore.save(
        templateId: widget.template.id,
        sourcePath: sourceFile.path,
        stage: 'cropping',
      );
      final cropped = await _crop(sourceFile);
      if (cropped != null && mounted) setState(() => photo = cropped);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Crop could not be applied, so the original photo is ready. Tap Adjust crop to try again.',
        );
      }
    } finally {
      await _PendingPhotoPickStore.clear();
    }
  }

  Future<File?> _crop(File source) async {
    final output = await cropper.cropImage(
      sourcePath: source.path,
      maxWidth: 2048,
      maxHeight: 2048,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust your photo',
          toolbarColor: bg,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: violet,
          dimmedLayerColor: Colors.black54,
          cropFrameColor: violet,
          cropGridColor: Colors.white54,
          showCropGrid: true,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
            const _TemplateCropPreset(),
          ],
        ),
        IOSUiSettings(
          title: 'Adjust your photo',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
            const _TemplateCropPreset(),
          ],
        ),
      ],
    );
    if (output == null) return null;
    final cropped = File(output.path);
    if (!await cropped.exists() || await cropped.length() == 0) {
      throw const FileSystemException('Cropper returned an empty image.');
    }
    return cropped;
  }

  Future<void> adjustCrop() async {
    final source = originalPhoto;
    if (source == null || busy) return;
    try {
      await _PendingPhotoPickStore.save(
        templateId: widget.template.id,
        sourcePath: source.path,
        stage: 'cropping',
      );
      final cropped = await _crop(source);
      if (cropped != null && mounted) setState(() => photo = cropped);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not update the crop. Your previous photo selection is unchanged.',
        );
    } finally {
      await _PendingPhotoPickStore.clear();
    }
  }

  Future<void> generate() async {
    final selected = photo;
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final profile = await AccountProfileService.instance.refresh();
      if (profile.credits < widget.template.creditsRequired) {
        if (mounted) setState(() => busy = false);
        if (!mounted) return;
        final canContinue =
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  _CreditGateDialog(required: widget.template.creditsRequired),
            ) ??
            false;
        if (canContinue && mounted) await _runGeneration(selected);
        return;
      }
      await _runGeneration(selected);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not verify your credits. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _runGeneration(File selected) async {
    if (mounted)
      setState(() {
        busy = true;
        error = null;
      });
    try {
      final generated = await service.generateImage(
        sourceImage: selected,
        template: widget.template,
      );
      if (mounted)
        widget.onGenerated(
          Creation(
            template: widget.template,
            image: generated.imageUrl,
            id: generated.generationId,
            generationId: generated.generationId,
            storagePath: generated.storagePath,
          ),
        );
    } on GenerationException catch (e) {
      if (e.insufficientCredits && mounted) {
        setState(() => busy = false);
        final canContinue =
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  _CreditGateDialog(required: widget.template.creditsRequired),
            ) ??
            false;
        if (canContinue && mounted) await _runGeneration(selected);
      } else if (mounted)
        setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Something went wrong while creating your photo. Your credit was not charged. Try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Add your photo')),
    body: PremiumBackground(
      kind: 'create',
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 150,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TemplateArtwork(template: widget.template),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Text(
                                widget.template.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    widget.template.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'For best results, use a clear front-facing photo with good lighting.',
                    style: TextStyle(color: muted, height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => pick(ImageSource.gallery),
                    child: Container(
                      height: 330,
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: photo == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 44,
                                  color: violet,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Choose a photo',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Tap here or select camera below',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ],
                            )
                          : ColoredBox(
                              color: Colors.black26,
                              child: Image.file(
                                photo!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                cacheWidth: 1200,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            photo == null ? 'Gallery' : 'Change photo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => pick(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(photo == null ? 'Camera' : 'Retake'),
                        ),
                      ),
                    ],
                  ),
                  if (photo != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy ? null : adjustCrop,
                        icon: const Icon(Icons.crop, size: 18),
                        label: const Text('Adjust crop'),
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 17),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Creating your lookâ€¦',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'The secure generation service is processing your photo.',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A2632).withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFFFCBD2),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  // Two native ad slots sit below the generation area once a
                  // photo is chosen, so they frame the creating state without
                  // crowding the empty picker.
                  if (photo != null) ...[
                    const SizedBox(height: 6),
                    const _NativeAdBlock(compact: true),
                    const _NativeAdBlock(compact: true),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 7, 20, 15),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: photo == null || busy ? null : generate,
                      icon: busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        busy
                            ? 'Creatingâ€¦'
                            : 'Generate Â· ${widget.template.creditsRequired} credit',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: violet,
                        foregroundColor: const Color(0xFF1A1424),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'By continuing, you agree to our terms and privacy policy.',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CreditGateDialog extends StatefulWidget {
  const _CreditGateDialog({required this.required});
  final int required;
  @override
  State<_CreditGateDialog> createState() => _CreditGateDialogState();
}

class _CreditGateDialogState extends State<_CreditGateDialog> {
  int? _credits;
  bool _working = false;
  bool _adFree = false;
  bool _profileLoaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    RewardedAdService.preloadRewardedAd();
  }

  Future<void> _refresh() async {
    try {
      final profile = await AccountProfileService.instance.refresh();
      if (mounted)
        setState(() {
          _credits = profile.credits;
          _adFree = profile.isAdFree;
          _profileLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _credits = null);
    }
  }

  Future<void> _watch() async {
    if (_working || _adFree) return;
    setState(() => _working = true);
    final granted = await RewardedAdService.showRewardedAd(
      onAdNotReady: () {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rewarded ad is not ready yet. Try again shortly.'),
            ),
          );
      },
      onRewardFailed: (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reward could not be confirmed. No credits were added.',
              ),
            ),
          );
      },
    );
    if (granted) await _refresh();
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final balance = _credits;
    return AlertDialog(
      backgroundColor: panel,
      title: const Text('Not Enough Credits'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You need ${widget.required} credits to create this photo.\n\nCurrent balance: ${balance == null ? 'Checking...' : '$balance credits'}',
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 15),
          if (_profileLoaded && !_adFree)
            FilledButton.icon(
              onPressed: _working ? null : _watch,
              icon: _working
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(
                _working ? 'Waiting for reward...' : 'WATCH AD  •  +5 CREDITS',
              ),
            ),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    );
                    await _refresh();
                  },
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('PURCHASE PREMIUM'),
          ),
          const SizedBox(height: 8),
          Text(
            balance != null && balance >= widget.required
                ? 'You have enough credits to continue.'
                : 'You need ${widget.required} credits to continue.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: balance != null && balance >= widget.required && !_working
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Continue Creating'),
        ),
      ],
    );
  }
}

class _TemplateCropPreset implements CropAspectRatioPresetData {
  const _TemplateCropPreset();
  @override
  (int, int)? get data => (4, 5);
  @override
  String get name => 'Template Â· 4:5';
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.creation, this.onTemplate});
  final Creation creation;
  final ValueChanged<PhotoTemplate>? onTemplate;
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _cleanUnlocked = false;
  bool _busy = false;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final profile = await AccountProfileService.instance.refresh();
      if (mounted)
        setState(() => _isPremium = profile.plan.toLowerCase() != 'free');
    } catch (_) {}
  }

  String _watermarkedUrl() {
    final generationId = widget.creation.generationId;
    if (generationId != null && generationApiBaseUrl.isNotEmpty) {
      return '$generationApiBaseUrl/v1/my-creations/$generationId/watermarked';
    }
    final uri = widget.creation.image;
    if (uri == null) throw StateError('Creation image is unavailable.');
    if (uri.path.endsWith('/image')) {
      return uri
          .replace(
            path: uri.path.replaceFirst(RegExp(r'/image$'), '/watermarked'),
          )
          .toString();
    }
    return uri.replace(path: '${uri.path}/watermarked').toString();
  }

  Future<void> _removeWatermark() async {
    if (_busy || _cleanUnlocked || _isPremium) return;
    setState(() => _busy = true);
    final ok = await RewardedAdService.showRewardedAd(
      onAdNotReady: () {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rewarded ad is not ready. Try again.'),
            ),
          );
      },
      onRewardGranted: (_) {},
      onRewardFailed: (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reward confirmation failed: $e')),
          );
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _cleanUnlocked = true;
    });
    if (ok)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Watermark removed. Download and Share are now enabled.',
          ),
        ),
      );
  }

  Future<Uint8List> _downloadBytes({required bool watermarked}) async {
    if (watermarked && widget.creation.generationId != null) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw StateError('Sign in to access this creation.');
      final response = await http
          .get(
            Uri.parse(_watermarkedUrl()),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200)
        throw StateError('Image download failed.');
      return response.bodyBytes;
    }
    final path = widget.creation.storagePath;
    if (path != null) {
      final bytes = await FirebaseStorage.instance
          .ref(path)
          .getData(50 * 1024 * 1024);
      if (bytes == null) throw StateError('The creation image is unavailable.');
      return bytes;
    }
    final image = widget.creation.image;
    if (image == null) throw StateError('The creation image is unavailable.');
    final response = await http.get(image).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw StateError('Image download failed.');
    return response.bodyBytes;
  }

  Future<void> _download() async {
    final watermarked = !_cleanUnlocked && !_isPremium;
    if (watermarked) await InterstitialAdService.showForDownload(context);
    setState(() => _busy = true);
    try {
      final bytes = await _downloadBytes(watermarked: watermarked);
      await GallerySaveService.save(
        bytes: bytes,
        fileName: 'VYRO_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved directly to Pictures/VYRO')),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;

    // Free users may share; the shared file simply carries the VYRO
    // watermark until the rewarded ad unlocks the clean copy.
    final watermarked = !_cleanUnlocked && !_isPremium;

    setState(() => _busy = true);
    try {
      final bytes = await _downloadBytes(watermarked: watermarked);
      if (bytes.isEmpty) {
        throw StateError('The image data was empty.');
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/vyro-share-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/jpeg')],
          text: watermarked
              ? 'Created with VYRO'
              : 'Created with VYRO · get the app',
          subject: 'Created with VYRO',
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Your creation')),
    body: PremiumBackground(
      kind: 'result',
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: AspectRatio(
                aspectRatio: widget.creation.template.id == 'luxury_car'
                    ? 1.5
                    : .78,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PrivateCreationImage(
                      uri: widget.creation.image,
                      storagePath: widget.creation.storagePath,
                      fit: widget.creation.template.id == 'luxury_car'
                          ? BoxFit.contain
                          : BoxFit.cover,
                    ),
                    if (!_cleanUnlocked && !_isPremium)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Text(
                                'AI PHOTO STUDIO',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.creation.template.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Your new look is ready.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                _ResultToolButton(
                  label: 'Enhance',
                  icon: Icons.auto_awesome,
                  screen: const PhotoEnhancerScreen(),
                ),
                _ResultToolButton(
                  label: 'Remove BG',
                  icon: Icons.layers_clear,
                  screen: const BackgroundRemoverScreen(),
                ),
                _ResultToolButton(
                  label: 'Social',
                  icon: Icons.crop,
                  screen: const SocialMediaScreen(),
                ),
                _ResultToolButton(
                  label: 'More tools',
                  icon: Icons.tune_rounded,
                  screen: const ToolsHomeScreen(),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (!_cleanUnlocked && !_isPremium)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _removeWatermark,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Remove Watermark Â· Watch Ad'),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _download,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      !_cleanUnlocked && !_isPremium
                          ? 'Download'
                          : 'Download Clean',
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(
                      !_cleanUnlocked && !_isPremium
                          ? 'Share'
                          : 'Share Clean',
                    ),
                  ),
                ),
              ],
            ),
            if (!_cleanUnlocked && !_isPremium)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Download and share keep the VYRO watermark. Watch the rewarded ad to unlock clean exports.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.4),
                ),
              ),
            const SizedBox(height: 18),
            const _NativeAdBlock(compact: true),
            const _NativeAdBlock(compact: true),
            const SizedBox(height: 22),
            const Text(
              'More templates you might like',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _TemplateGrid(
              templates: TemplateCatalog.all
                  .where((t) => t.id != widget.creation.template.id)
                  .take(4)
                  .toList(),
              showNativeAds: true,
              compactNativeAds: true,
              trailingNativeAds: 2,
              // This short grid is scanned quickly, so a denser slot cadence
              // keeps an ad in view without scrolling past two full rows.
              adInterval: 2,
              onTap: (template) => widget.onTemplate?.call(template),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResultToolButton extends StatelessWidget {
  const _ResultToolButton({
    required this.label,
    required this.icon,
    required this.screen,
  });
  final String label;
  final IconData icon;
  final Widget screen;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 7),
      child: OutlinedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => screen),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          side: const BorderSide(color: line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: violet),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}

class _PrivateCreationImage extends StatelessWidget {
  const _PrivateCreationImage({
    required this.uri,
    required this.storagePath,
    required this.fit,
  });
  final Uri? uri;
  final String? storagePath;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final path = storagePath;
    if (path != null) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.ref(path).getDownloadURL(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _UnavailableImage();
          if (!snapshot.hasData) {
            return const ColoredBox(
              color: panel,
              child: Center(child: CircularProgressIndicator(color: violet)),
            );
          }
          return _networkImage(snapshot.data!);
        },
      );
    }
    final resolved = uri;
    if (resolved == null || !resolved.hasScheme)
      return const _UnavailableImage();
    return _networkImage(resolved.toString());
  }

  Widget _networkImage(String url) => Image.network(
    url,
    fit: fit,
    cacheWidth: 1200,
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      final total = progress.expectedTotalBytes;
      return ColoredBox(
        color: panel,
        child: Center(
          child: CircularProgressIndicator(
            value: total == null
                ? null
                : progress.cumulativeBytesLoaded / total,
            color: violet,
          ),
        ),
      );
    },
    errorBuilder: (_, _, _) => const _UnavailableImage(),
  );
}

class _UnavailableImage extends StatelessWidget {
  const _UnavailableImage();
  @override
  Widget build(BuildContext context) => Container(
    color: panel,
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: muted, size: 42),
          SizedBox(height: 9),
          Text('Image unavailable', style: TextStyle(color: muted)),
        ],
      ),
    ),
  );
}

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key, required this.onTemplate});
  final ValueChanged<PhotoTemplate> onTemplate;
  @override
  Widget build(BuildContext context) => PremiumBackground(
    kind: 'create',
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Text(
            'Choose your next look',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start with a template. Your photo brings it to life.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          _TemplateGrid(
            templates: TemplateCatalog.all,
            onTap: onTemplate,
            showNativeAds: true,
          ),
        ],
      ),
    ),
  );
}

class CreationsScreen extends StatelessWidget {
  const CreationsScreen({
    super.key,
    required this.creations,
    required this.loading,
    required this.onRetry,
    this.error,
  });
  final List<Creation> creations;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (loading && creations.isEmpty) {
      return const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: violet),
              SizedBox(height: 16),
              Text('Loading your creations...'),
            ],
          ),
        ),
      );
    }
    if (error != null && creations.isEmpty) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: muted, size: 42),
                const SizedBox(height: 12),
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (creations.isEmpty) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(21),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    size: 42,
                    color: violet,
                  ),
                ),
                const SizedBox(height: 17),
                const Text(
                  'Your creations live here',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Choose a look and create your first AI photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: creations.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .72,
        ),
        itemBuilder: (context, i) {
          final item = creations[i];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ResultScreen(creation: item),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PrivateCreationImage(
                    uri: item.image,
                    storagePath: item.storagePath,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.black.withValues(alpha: .65),
                      child: Text(
                        item.template.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Opens the user's mail app addressed to VYRO support.
///
/// Falls back to copying the address when no mail app can handle it, so the
/// address is never a dead end.
Future<void> _contactSupport(BuildContext context) async {
  const address = 'akhileshgulia72@gmail.com';

  void notify(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  try {
    final opened = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: address,
        queryParameters: const {'subject': 'VYRO support request'},
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await Clipboard.setData(const ClipboardData(text: address));
      notify('Support email copied: $address');
    }
  } catch (error) {
    debugPrint('VYRO support: could not open mail app: $error');
    await Clipboard.setData(const ClipboardData(text: address));
    notify('Support email copied: $address');
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGoogle = user != null && !user.isAnonymous;
    final displayName = user?.displayName?.trim();
    final email = user?.email;

    return PremiumBackground(
      kind: 'profile',
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your profile',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Your creative space, all in one place.',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(19),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF33254A),
                    Color(0xFF201827),
                    Color(0xFF17131F),
                  ],
                ),
                border: Border.all(color: const Color(0x66B69BFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFF3A9D1), Color(0xFF9F83FF)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 31,
                      backgroundColor: const Color(0xFF211A2B),
                      backgroundImage: user?.photoURL == null
                          ? null
                          : NetworkImage(user!.photoURL!),
                      child: user?.photoURL == null
                          ? const Icon(
                              Icons.person_rounded,
                              color: Color(0xFFE3D2FF),
                              size: 30,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGoogle
                              ? (displayName?.isNotEmpty == true
                                    ? displayName!
                                    : 'Google account')
                              : 'Guest creator',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isGoogle
                              ? (email ?? 'Google account connected')
                              : 'Guest session Â· connect Google to sync your studio',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFC2B8CD),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isGoogle
                                ? const Color(0x332FCB94)
                                : const Color(0x33B69BFF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isGoogle
                                  ? const Color(0x6648D9A8)
                                  : const Color(0x66B69BFF),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isGoogle
                                    ? Icons.verified_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 12,
                                color: isGoogle
                                    ? const Color(0xFF73E0B5)
                                    : violet,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isGoogle ? 'GOOGLE CONNECTED' : 'VYRO CREATOR',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _HomeCreditBalance(),
            const SizedBox(height: 22),
            const _ProfileSectionTitle('YOUR STUDIO'),
            if (!isGoogle)
              _ProfileItem(
                Icons.login_rounded,
                'Connect Google',
                'Keep your credits and creations attached to your account',
                onTap: () async {
                  try {
                    await AuthService.instance.signInWithGoogle();
                    if (mounted) setState(() {});
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Google Sign-In failed. Please try again.',
                        ),
                      ),
                    );
                  }
                },
              ),
            _ProfileItem(
              Icons.auto_awesome,
              'Credits',
              'View balance and rewarded credit options',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
              ),
            ),
            const SizedBox(height: 22),
            const _ProfileSectionTitle('PREFERENCES & SUPPORT'),
            _ProfileItem(
              Icons.workspace_premium_outlined,
              'Premium',
              'Plans and premium benefits',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
              ),
            ),
            _ProfileItem(
              Icons.privacy_tip_outlined,
              'Privacy options',
              'Review or change your advertising consent choices',
              onTap: () async {
                var optionsPresented = false;
                var failedToOpen = false;
                try {
                  optionsPresented = await UmpConsentService.instance
                      .showPrivacyOptionsForm();
                } catch (error) {
                  failedToOpen = true;
                  debugPrint('UMP: opening privacy options failed: $error');
                }

                RewardedAdService.clearForConsentChange();
                InterstitialAdService.clearForConsentChange();
                if (UmpConsentService.instance.adsAllowed) {
                  RewardedAdService.preloadRewardedAd();
                  InterstitialAdService.preload();
                }
                if (!context.mounted || optionsPresented) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      failedToOpen
                          ? 'Could not open privacy options. Please try again.'
                          : 'Privacy options are not required in your current region.',
                    ),
                  ),
                );
              },
            ),
            _ProfileItem(
              Icons.privacy_tip_outlined,
              'Privacy policy',
              'How photo data is handled',
              onTap: () async {
                final opened = await launchUrl(
                  Uri.parse(
                    'https://akhileshgulia72-dotcom.github.io/vyro-privacy-policy/',
                  ),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open the privacy policy.'),
                    ),
                  );
                }
              },
            ),
            _ProfileItem(
              Icons.support_agent_outlined,
              'Support',
              'akhileshgulia72@gmail.com',
              onTap: () => _contactSupport(context),
            ),
            const SizedBox(height: 12),
            _ProfileItem(
              Icons.logout_rounded,
              'Sign out',
              isGoogle
                  ? 'Sign out of your Google-connected VYRO account'
                  : 'Sign out of this guest session',
              onTap: () async {
                await AuthService.instance.signOut();
              },
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'VYRO Â· Made for your imagination',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem(this.icon, this.title, this.subtitle, {this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: const Color(0xAA191521),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pink.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: pink, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3, bottom: 2),
    child: Text(
      title,
      style: const TextStyle(
        color: muted,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    ),
  );
}
