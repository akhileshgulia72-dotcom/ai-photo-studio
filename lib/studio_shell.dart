import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/photo_template.dart';
import '../services/image_generation_service.dart';
import 'credits_screen.dart';

const bg = Color(0xFF0D0B12);
const panel = Color(0xFF191521);
const line = Color(0xFF30283A);
const violet = Color(0xFFB69BFF);
const pink = Color(0xFFF3A9D1);
const muted = Color(0xFFAAA2B3);

// Android emulator -> host machine. For a physical device, replace with
// your PC's LAN IP, e.g. http://192.168.1.10:8000
const generationApiBaseUrl = String.fromEnvironment(
  'GENERATION_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class Creation {
  const Creation({required this.template, required this.image});
  final PhotoTemplate template;
  final Uri image;
}

class StudioShell extends StatefulWidget {
  const StudioShell({super.key});
  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int tab = 0;
  final creations = <Creation>[];

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

  void openPhoto(PhotoTemplate template) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PhotoSelectionScreen(
          template: template,
          onGenerated: (creation) {
            setState(() => creations.insert(0, creation));
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    ResultScreen(creation: creation, onTemplate: openTemplate),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        onTemplate: openTemplate,
        onCredits: () => setState(() => tab = 3),
      ),
      CreateScreen(onTemplate: openTemplate),
      CreationsScreen(creations: creations),
      const CreditsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: bg,
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF15121B),
        indicatorColor: violet.withValues(alpha: .17),
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
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
            label: 'My Creations',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Credits',
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
    required this.onCredits,
  });
  final ValueChanged<PhotoTemplate> onTemplate;
  final VoidCallback onCredits;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final search = TextEditingController();
  String category = 'All';

  int? credits;
  String plan = 'free';
  bool loadingCredits = true;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => loadingCredits = false);
        return;
      }

      final token = await user.getIdToken();
      if (token == null) {
        if (mounted) setState(() => loadingCredits = false);
        return;
      }

      final response = await http.get(
        Uri.parse('$generationApiBaseUrl/v1/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            credits = (data['credits'] as num?)?.toInt() ?? 0;
            plan = (data['plan'] as String?) ?? 'free';
            loadingCredits = false;
          });
        }
      } else if (mounted) {
        setState(() => loadingCredits = false);
      }
    } catch (_) {
      if (mounted) setState(() => loadingCredits = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Profile is refreshed whenever Home becomes visible again.
    _loadCredits();
  }
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
    return SafeArea(
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
                            'Make a little magic.',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: violet,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              loadingCredits
                                  ? '...'
                                  : '${credits ?? 0}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'credits',
                              style: TextStyle(
                                color: muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Turn your photos into something extraordinary.',
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
                              'A new you,\nin one tap.',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Pick a style. We’ll take it from here.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD5CCDF),
                              ),
                            ),
                            const SizedBox(height: 15),
                            FilledButton.icon(
                              onPressed: () =>
                                  widget.onTemplate(TemplateCatalog.all.first),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 17,
                              ),
                              label: const Text('Explore styles'),
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
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: violet.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: violet,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your AI credits',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              loadingCredits
                                  ? 'Checking your balance…'
                                  : plan == 'free'
                                      ? '${credits ?? 0} credits available'
                                      : '${credits ?? 0} credits · ${plan.toUpperCase()}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onCredits,
                        tooltip: 'Earn credits',
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: violet,
                          size: 20,
                        ),
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
                    prefixIcon: const Icon(Icons.search_rounded, color: muted),
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
                                  selectedColor: violet.withValues(alpha: .22),
                                  backgroundColor: panel,
                                  side: BorderSide(
                                    color: category == c
                                        ? violet.withValues(alpha: .5)
                                        : line,
                                  ),
                                  labelStyle: TextStyle(
                                    color: category == c ? Colors.white : muted,
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
                  _TemplateGrid(templates: matches, onTap: widget.onTemplate),
                if (query.isEmpty && category == 'All') ...[
                  const SizedBox(height: 24),
                  const _SectionTitle(
                    'Popular templates',
                    'Looks creators love',
                  ),
                  const SizedBox(height: 13),
                  _TemplateGrid(
                    templates: TemplateCatalog.all.skip(1).take(4).toList(),
                    onTap: widget.onTemplate,
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Premium looks', 'A little extra magic'),
                  const SizedBox(height: 12),
                  _TemplateGrid(
                    templates: TemplateCatalog.all
                        .where((t) => t.isPremium)
                        .toList(),
                    onTap: widget.onTemplate,
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
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();
  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 134,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFEDB2D1), Color(0xFF9579D9), Color(0xFF484069)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(60),
      boxShadow: [BoxShadow(color: pink.withValues(alpha: .2), blurRadius: 25)],
    ),
    child: const Center(
      child: Icon(
        Icons.face_retouching_natural_rounded,
        size: 56,
        color: Colors.white,
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
  const _TemplateGrid({required this.templates, required this.onTap});
  final List<PhotoTemplate> templates;
  final ValueChanged<PhotoTemplate> onTap;
  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: templates.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: .72,
    ),
    itemBuilder: (context, i) =>
        _TemplateCard(template: templates[i], onTap: () => onTap(templates[i])),
  );
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _palette(template),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _categoryIcon(template.category),
                      size: 53,
                      color: Colors.white.withValues(alpha: .82),
                    ),
                  ),
                ),
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
                  const Positioned(
                    right: 9,
                    top: 9,
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFFFD58B),
                      size: 19,
                    ),
                  ),
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

IconData _categoryIcon(TemplateCategory c) => switch (c) {
  TemplateCategory.luxury => Icons.diamond_outlined,
  TemplateCategory.cinematic => Icons.movie_filter_outlined,
  TemplateCategory.professional => Icons.work_outline_rounded,
  TemplateCategory.indian => Icons.local_florist_outlined,
  TemplateCategory.social => Icons.camera_alt_outlined,
  TemplateCategory.couple => Icons.favorite_border,
  TemplateCategory.travel => Icons.flight_takeoff_rounded,
  TemplateCategory.creative => Icons.palette_outlined,
};

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
                  child: Container(
                    height: 360,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _palette(template),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        _categoryIcon(template.category),
                        color: Colors.white.withValues(alpha: .85),
                        size: 94,
                      ),
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
                const SizedBox(height: 16),
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
                  'AI uses this look as inspiration while keeping your face recognizable and natural.',
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
  });
  final PhotoTemplate template;
  final ValueChanged<Creation> onGenerated;
  @override
  State<PhotoSelectionScreen> createState() => _PhotoSelectionScreenState();
}

class _PhotoSelectionScreenState extends State<PhotoSelectionScreen> {
  final picker = ImagePicker();
  final service = BackendImageGenerationService();
  File? photo;
  bool busy = false;
  String? error;
  int stage = 0;
  int? credits;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$generationApiBaseUrl/v1/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => credits = (data['credits'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    try {
      final x = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (x != null && mounted) {
        setState(() {
          photo = File(x.path);
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open that photo source. Please try again.',
        );
      }
    }
  }

  Future<void> generate() async {
    final selected = photo;
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      error = null;
      stage = 0;
    });
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && busy && stage < 3) setState(() => stage++);
    });
    try {
      final uri = await service.generateImage(
        sourceImage: selected,
        template: widget.template,
      );
      if (mounted) {
        widget.onGenerated(Creation(template: widget.template, image: uri));
      }
    } on GenerationException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Something went wrong while creating your photo. Your credit was not charged. Try again.',
        );
      }
    } finally {
      timer?.cancel();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Add your photo')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
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
                        : Image.file(
                            photo!,
                            fit: BoxFit.cover,
                            width: double.infinity,
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
                        label: Text(photo == null ? 'Gallery' : 'Change photo'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(photo == null ? 'Camera' : 'Retake'),
                      ),
                    ),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 17),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Creating your photo…',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 9),
                        for (var i = 0; i < 4; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  i < stage
                                      ? Icons.check_circle
                                      : i == stage
                                      ? Icons.circle
                                      : Icons.circle_outlined,
                                  size: 15,
                                  color: i <= stage ? violet : muted,
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  [
                                    'Analyzing photo',
                                    'Applying style',
                                    'Generating image',
                                    'Finalizing result',
                                  ][i],
                                  style: TextStyle(
                                    color: i <= stage ? Colors.white : muted,
                                    fontSize: 12,
                                  ),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 7, 20, 15),
            child: Column(
              children: [
                if (credits != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: violet,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${credits ?? 0} credits available',
                          style: const TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          ? 'Creating…'
                          : 'Generate · ${widget.template.creditsRequired} credit',
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
  );
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.creation, this.onTemplate});
  final Creation creation;
  final ValueChanged<PhotoTemplate>? onTemplate;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Your creation')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: AspectRatio(
              aspectRatio: .78,
              child: Image.network(
                creation.image.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _UnavailableImage(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            creation.template.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text('Your new look is ready.', style: TextStyle(color: muted)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saved to My Creations for this session.'),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Device sharing will be enabled with the share integration.',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'More templates you might like',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _TemplateGrid(
            templates: TemplateCatalog.all
                .where((t) => t.id != creation.template.id)
                .take(4)
                .toList(),
            onTap: (template) => onTemplate?.call(template),
          ),
        ],
      ),
    ),
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
  Widget build(BuildContext context) => SafeArea(
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
        _TemplateGrid(templates: TemplateCatalog.all, onTap: onTemplate),
      ],
    ),
  );
}

class CreationsScreen extends StatelessWidget {
  const CreationsScreen({super.key, required this.creations});
  final List<Creation> creations;
  @override
  Widget build(BuildContext context) {
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
                  Image.network(
                    item.image.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _UnavailableImage(),
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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 14),
        const Text(
          'Your profile',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your creative space, all in one place.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: line),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFF392B54),
                child: Icon(Icons.person_outline, color: violet, size: 28),
              ),
              SizedBox(width: 13),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome creator',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sign-in and cloud sync coming soon',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ProfileItem(
          Icons.auto_awesome,
          'Credits',
          'Watch ads to earn +5 credits',
          onTap: () {},
        ),
        const _ProfileItem(
          Icons.workspace_premium_outlined,
          'Premium',
          'Explore premium looks soon',
        ),
        const _ProfileItem(
          Icons.privacy_tip_outlined,
          'Privacy & terms',
          'Your photos are handled securely',
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'AI Photo Studio · Made for your imagination',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem(
    this.icon,
    this.title,
    this.subtitle, {
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Icon(icon, color: pink),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: muted, fontSize: 11),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted),
    onTap: onTap,
  );
}
