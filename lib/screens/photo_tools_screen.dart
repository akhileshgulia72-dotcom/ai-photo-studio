import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../widgets/premium_background.dart';
import '../services/account_profile_service.dart';
import '../services/ad_unit_config.dart';
import '../services/ad_diagnostics.dart';
import '../services/rewarded_ad_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/gallery_save_service.dart';
import '../services/ump_consent_service.dart';

const _bg = Color(0xFF0D0B12),
    _panel = Color(0xFF191521),
    _violet = Color(0xFFB69BFF),
    _muted = Color(0xFFAAA2B3);

const double _toolPickMaxDimension = 1600;
const _toolPickQuality = 84;

/// Image decoding and pixel work must stay off the UI isolate. Limit dimensions
/// before applying filters so high megapixel camera photos cannot exhaust RAM.
Uint8List _processLocalPhoto(Map<String, Object?> args) {
  final source = args['bytes'] as Uint8List;
  final mode = args['mode'] as String;
  final maxDimension = args['maxDimension'] as int? ?? 2400;
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const FormatException('Unsupported image.');
  var image = img.bakeOrientation(decoded);
  if (image.width > maxDimension || image.height > maxDimension) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? maxDimension : null,
      height: image.height > image.width ? maxDimension : null,
      interpolation: img.Interpolation.average,
    );
  }
  if (mode == 'blur') {
    image = img.gaussianBlur(image, radius: args['radius'] as int? ?? 8);
  } else if (mode == 'enhance') {
    image = img.adjustColor(
      image,
      brightness: args['brightness'] as num? ?? 1,
      contrast: args['contrast'] as num? ?? 1,
      saturation: args['saturation'] as num? ?? 1,
      gamma: args['gamma'] as num? ?? 1,
      exposure: args['exposure'] as num? ?? 0,
    );
    final sharpness = args['sharpness'] as num? ?? 0;
    if (sharpness > 0) {
      image = img.convolution(
        image,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: sharpness.toDouble(),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

Uint8List _compressLocalPhoto(Map<String, Object?> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Unsupported image.');
  var image = img.bakeOrientation(decoded);
  const maxDimension = 2600;
  if (image.width > maxDimension || image.height > maxDimension) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? maxDimension : null,
      height: image.height > image.width ? maxDimension : null,
      interpolation: img.Interpolation.average,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(image, quality: args['quality'] as int),
  );
}

Future<Uint8List> _processPickedFile(
  File file, {
  required String mode,
  required int maxDimension,
}) async {
  final bytes = await file.readAsBytes();
  return compute(_processLocalPhoto, <String, Object?>{
    'bytes': bytes,
    'mode': mode,
    'maxDimension': maxDimension,
  });
}

class _ToolLoadingOverlay extends StatelessWidget {
  const _ToolLoadingOverlay({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x660D0B12),
    child: Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF302346), Color(0xFF17131F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _violet.withValues(alpha: .35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: _violet, size: 42),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Optimizing your photo on this device…',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 22),
            const SizedBox(width: 190, child: LinearProgressIndicator()),
          ],
        ),
      ),
    ),
  );
}

/// Stamps the VYRO mark onto tool exports for users without clean export.
///
/// A corner badge rather than a full-width band: it stays clearly legible at
/// roughly a third of the frame width without covering the subject, and it
/// matches the watermark the backend burns into studio downloads.
Future<Uint8List> _withVyroMark(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1800);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.high,
  );

  final shortSide = image.width < image.height ? image.width : image.height;
  final fontSize = (shortSide / 12).clamp(30.0, 240.0).toDouble();
  final margin = (shortSide * .028).clamp(18.0, 90.0).toDouble();

  final text = TextPainter(
    text: TextSpan(
      text: 'VYRO',
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: fontSize * .04,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final padX = fontSize * .75;
  final padY = fontSize * .34;
  final pillWidth = text.width + padX * 2;
  final pillHeight = text.height + padY * 2;
  final left = image.width - pillWidth - margin;
  final top = image.height - pillHeight - margin;
  final radius = Radius.circular((fontSize / 3).clamp(12.0, 70.0));

  // Soft shadow keeps the badge readable over pale photos too.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left + 3, top + 4, pillWidth, pillHeight),
      radius,
    ),
    Paint()..color = const Color(0x46000000),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, pillWidth, pillHeight),
      radius,
    ),
    Paint()..color = const Color(0xB9000000),
  );
  text.paint(canvas, Offset(left + padX, top + padY));

  final marked = await recorder.endRecording().toImage(
    image.width,
    image.height,
  );
  final data = await marked.toByteData(format: ui.ImageByteFormat.png);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  marked.dispose();
  codec.dispose();
  return result;
}

Future<void> _shareToolImage(
  BuildContext context,
  Uint8List cleanBytes,
  String prefix,
) async {
  var cleanAllowed = false;
  try {
    cleanAllowed =
        (await AccountProfileService.instance.refresh()).hasNoWatermark;
  } catch (_) {
    cleanAllowed = false;
  }
  final marked = cleanAllowed ? cleanBytes : await _withVyroMark(cleanBytes);
  if (!context.mounted) return;
  if (!cleanAllowed) {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _panel,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your photo is ready',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share with a VYRO watermark, or watch a rewarded ad to remove it.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Remove VYRO watermark · Watch ad'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Continue with VYRO watermark'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (remove == true) {
      final granted = await RewardedAdService.showRewardedAd();
      if (!granted || !context.mounted) return;
      cleanAllowed = true;
    }
  }
  final toShare = cleanAllowed ? cleanBytes : marked;
  if (!context.mounted) return;
  final isPng =
      toShare.length > 8 &&
      toShare[0] == 0x89 &&
      toShare[1] == 0x50 &&
      toShare[2] == 0x4e &&
      toShare[3] == 0x47;
  await GallerySaveService.save(
    bytes: toShare,
    fileName:
        '$prefix-${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}',
    mimeType: isPng ? 'image/png' : 'image/jpeg',
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved directly to Pictures/VYRO')),
    );
  }
}

class StudioInfoScreen extends StatelessWidget {
  const StudioInfoScreen({
    super.key,
    required this.title,
    required this.description,
  });
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(title: Text(title)),
    body: PremiumBackground(
      kind: 'profile',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: GlassCard(
            child: Text(
              description,
              style: const TextStyle(color: _muted, height: 1.5),
            ),
          ),
        ),
      ),
    ),
  );
}

class ToolsHomeScreen extends StatelessWidget {
  const ToolsHomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(title: const Text('Photo Tools')),
    body: PremiumBackground(
      kind: 'create',
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Create locally',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 20),
              child: Text(
                'Private, on-device edits. These tools use no AI credits or paid APIs.',
                style: TextStyle(color: _muted),
              ),
            ),
            _heading('PHOTO TOOLS'),
            _tile(
              context,
              Icons.auto_fix_high,
              'Photo Enhancer',
              'Adjust brightness, contrast and color locally',
              const PhotoEnhancerScreen(),
            ),
            _tile(
              context,
              Icons.blur_on,
              'Background Blur',
              'Apply a controllable blur to the complete photo',
              const BackgroundBlurScreen(),
            ),
            _tile(
              context,
              Icons.compress,
              'Photo Compressor',
              'Create a smaller JPEG copy and choose a target size',
              const PhotoCompressorScreen(),
            ),
            _tile(
              context,
              Icons.layers_clear,
              'Background Remover',
              'On-device subject segmentation is not available in this build',
              const BackgroundRemoverScreen(),
              disabled: true,
            ),
            _heading('SOCIAL CREATOR'),
            _tile(
              context,
              Icons.crop_square,
              'Instagram Post',
              'Square 1:1 image with text and background',
              const SocialMediaScreen(initialPreset: 0),
            ),
            _tile(
              context,
              Icons.phone_android,
              'Instagram Story',
              'Portrait 9:16 story canvas',
              const SocialMediaScreen(initialPreset: 1),
            ),
            _tile(
              context,
              Icons.account_circle,
              'WhatsApp DP',
              'Square profile image',
              const SocialMediaScreen(initialPreset: 2, circle: true),
            ),
            _tile(
              context,
              Icons.work_outline,
              'LinkedIn',
              'Square professional post/profile canvas',
              const SocialMediaScreen(initialPreset: 3),
            ),
            _tile(
              context,
              Icons.ondemand_video,
              'YouTube Thumbnail',
              'Wide 16:9 canvas',
              const SocialMediaScreen(initialPreset: 4),
            ),
            _tile(
              context,
              Icons.wallpaper,
              'Phone Wallpaper',
              'Portrait 9:16 wallpaper canvas',
              const SocialMediaScreen(initialPreset: 5),
            ),
            _heading('CREATIVE'),
            _tile(
              context,
              Icons.badge_outlined,
              'Passport / ID Photo',
              'Basic 35:45 crop on a 4×6 inch sheet; not government-compliance certified',
              const SocialMediaScreen(initialPreset: 6),
            ),
            _tile(
              context,
              Icons.grid_view,
              'Collage Maker',
              'Arrange 2, 3, 4 or 6 local photos with spacing and background',
              const CollageMakerScreen(),
            ),
            _tile(
              context,
              Icons.face_retouching_natural,
              'Profile Picture Maker',
              'Square composition with circular preview and color ring',
              const SocialMediaScreen(initialPreset: 2, circle: true),
            ),
          ],
        ),
      ),
    ),
  );
  static Widget _heading(String s) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      s,
      style: const TextStyle(
        color: Color(0xFFF3A9D1),
        letterSpacing: 1.4,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
  static Widget _tile(
    BuildContext c,
    IconData i,
    String title,
    String desc,
    Widget screen, {
    bool disabled = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Card(
      color: _panel,
      child: ListTile(
        enabled: !disabled,
        leading: Icon(i, color: _violet),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          desc,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        trailing: disabled
            ? const Text(
                'UNAVAILABLE',
                style: TextStyle(fontSize: 9, color: _muted),
              )
            : const Icon(Icons.arrow_forward_ios_rounded, size: 15),
        onTap: disabled
            ? null
            : () => Navigator.push(
                c,
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
      ),
    ),
  );
}

class BackgroundRemoverScreen extends StatelessWidget {
  const BackgroundRemoverScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Background Remover')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'True background removal needs an on-device person/object segmentation model. No segmentation model is configured, so this tool is disabled instead of returning a fake transparent image.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class PhotoEnhancerScreen extends StatelessWidget {
  const PhotoEnhancerScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AdjustScreen(blur: false);
}

class BackgroundBlurScreen extends StatelessWidget {
  const BackgroundBlurScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AdjustScreen(blur: true);
}

class _ToolNativeAdSlot extends StatefulWidget {
  const _ToolNativeAdSlot();
  @override
  State<_ToolNativeAdSlot> createState() => _ToolNativeAdSlotState();
}

class _ToolNativeAdSlotState extends State<_ToolNativeAdSlot> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _hide = false;
  bool _loading = false;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  int _loadGeneration = 0;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  // Platform and test/production selection stay centralized.
  static String? get _unitId => AdUnitConfig.native;

  @override
  void initState() {
    super.initState();
    UmpConsentService.instance.addListener(_onConsentChanged);
    _load();
  }

  void _onConsentChanged() {
    if (!UmpConsentService.instance.adsAllowed) {
      _loadGeneration++;
      _retryTimer?.cancel();
      _retryTimer = null;
      _ad?.dispose();
      _ad = null;
      _loading = false;
      if (mounted) {
        setState(() {
          _loaded = false;
          _hide = true;
        });
      }
      return;
    }
    _retryAttempt = 0;
    if (mounted) setState(() => _hide = false);
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || _ad != null) return;

    final id = _unitId;
    if (id == null) {
      debugPrint(
        'ToolNativeAdSlot: native slot skipped - '
        'no unit available (testAds=${AdUnitConfig.useTestAds})',
      );
      _hide = true;
      if (mounted) setState(() {});
      return;
    }

    _loading = true;
    final generation = ++_loadGeneration;
    try {
      // Wait for consent and SDK init together instead of sampling once.
      if (!await UmpConsentService.instance.waitUntilReady(
        timeout: const Duration(seconds: 8),
      )) {
        debugPrint(
          'ToolNativeAdSlot: not loading - '
          '${UmpConsentService.instance.describe()}',
        );
        _hide = true;
        return;
      }
      final profile = await AccountProfileService.instance.refresh();
      if (!mounted || profile.isAdFree) {
        _hide = true;
        return;
      }
    } catch (error) {
      debugPrint('ToolNativeAdSlot: skipping - $error');
      _hide = true;
      return;
    } finally {
      _loading = false;
    }
    if (!mounted ||
        generation != _loadGeneration ||
        !UmpConsentService.instance.adsAllowed) {
      return;
    }
    _ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: _panel,
        cornerRadius: 18,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted ||
              generation != _loadGeneration ||
              !UmpConsentService.instance.adsAllowed) {
            ad.dispose();
            return;
          }
          _retryTimer?.cancel();
          _retryTimer = null;
          _retryAttempt = 0;
          debugPrint('ToolNativeAdSlot: ad loaded');
          logAdResponseInfo('ToolNativeAdSlot', ad.responseInfo);
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          logAdFailure(
            'ToolNativeAdSlot load unit=$id',
            error,
            responseInfo: error.responseInfo,
          );
          if (generation == _loadGeneration) {
            _ad = null;
            _scheduleRetry();
          }
        },
      ),
    )..load();
  }

  void _scheduleRetry() {
    if (!mounted ||
        !UmpConsentService.instance.adsAllowed ||
        _retryAttempt >= _retryDelays.length) {
      return;
    }
    final delay = _retryDelays[_retryAttempt++];
    debugPrint('ToolNativeAdSlot: retry $_retryAttempt in $delay');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (mounted && UmpConsentService.instance.adsAllowed) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    UmpConsentService.instance.removeListener(_onConsentChanged);
    _loadGeneration++;
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hide || !_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        height: 280,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF30283A)),
        ),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}

class _AdjustScreen extends StatefulWidget {
  const _AdjustScreen({required this.blur});
  final bool blur;
  @override
  State<_AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<_AdjustScreen> {
  File? _file;
  Uint8List? _sourceBytes;
  Uint8List? _bytes;
  bool _busy = false;
  double _brightness = 1;
  double _contrast = 1;
  double _saturation = 1;
  double _exposure = 0;
  double _gamma = 1;
  double _sharpness = .35;
  double _blurAmount = .5;
  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: _toolPickMaxDimension,
        maxHeight: _toolPickMaxDimension,
        imageQuality: _toolPickQuality,
        requestFullMetadata: false,
      );
      if (x == null || !mounted) return;
      final file = File(x.path);
      final source = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _file = file;
        _sourceBytes = source;
        _bytes = source;
      });
      await _process();
    } catch (_) {
      if (mounted) _message('Could not open this photo. Try a smaller image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _process() async {
    final input = _sourceBytes;
    if (_file == null || input == null) return;
    setState(() => _busy = true);
    try {
      final result = await compute(_processLocalPhoto, <String, Object?>{
        'bytes': input,
        'mode': widget.blur ? 'blur' : 'enhance',
        'maxDimension': 1600,
        if (widget.blur) 'radius': (1 + _blurAmount * 18).round(),
        if (!widget.blur) 'brightness': _brightness,
        if (!widget.blur) 'contrast': _contrast,
        if (!widget.blur) 'saturation': _saturation,
        if (!widget.blur) 'gamma': _gamma,
        if (!widget.blur) 'exposure': _exposure,
        if (!widget.blur) 'sharpness': _sharpness,
      });
      if (mounted) setState(() => _bytes = result);
    } catch (_) {
      if (mounted) _message('This image could not be decoded.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      await InterstitialAdService.showForToolProcessing(context);
      if (!mounted) return;
      await _shareToolImage(
        context,
        bytes,
        'vyro-${widget.blur ? 'blur' : 'enhanced'}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Widget _toolSlider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · ${value.toStringAsFixed(2)}'),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: (v) => setState(() => update(v)),
        onChangeEnd: (_) => _process(),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.blur ? 'Background Blur' : 'Photo Enhancer'),
    ),
    body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose photo'),
            ),
            if (_bytes != null) ...[
              const SizedBox(height: 14),
              Image.memory(
                _bytes!,
                fit: BoxFit.contain,
                cacheWidth: 1200,
                filterQuality: FilterQuality.medium,
              ),
              if (widget.blur)
                _toolSlider(
                  'Blur strength',
                  _blurAmount,
                  0,
                  1,
                  (v) => _blurAmount = v,
                )
              else ...[
                _toolSlider('Exposure', _exposure, -1, 1, (v) => _exposure = v),
                _toolSlider(
                  'Brightness',
                  _brightness,
                  .5,
                  1.5,
                  (v) => _brightness = v,
                ),
                _toolSlider(
                  'Contrast',
                  _contrast,
                  .5,
                  1.6,
                  (v) => _contrast = v,
                ),
                _toolSlider(
                  'Color intensity',
                  _saturation,
                  0,
                  1.8,
                  (v) => _saturation = v,
                ),
                _toolSlider('Gamma', _gamma, .5, 1.8, (v) => _gamma = v),
                _toolSlider(
                  'Edge detail',
                  _sharpness,
                  0,
                  1,
                  (v) => _sharpness = v,
                ),
                const Text(
                  'On-device enhancement · original photo stays unchanged',
                  style: TextStyle(color: _muted),
                ),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export / Share'),
              ),
            ],
            const _ToolNativeAdSlot(),
            const _ToolNativeAdSlot(),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: _ToolLoadingOverlay(
              title: widget.blur
                  ? 'Creating your softened look'
                  : 'Enhancing your photo',
            ),
          ),
      ],
    ),
  );
}

class PhotoCompressorScreen extends StatefulWidget {
  const PhotoCompressorScreen({super.key});
  @override
  State<PhotoCompressorScreen> createState() => _PhotoCompressorScreenState();
}

class _PhotoCompressorScreenState extends State<PhotoCompressorScreen> {
  File? _source;
  Uint8List? _out;
  int _target = 1024 * 1024;
  int _sourceSize = 0;
  int _quality = 90;
  bool _busy = false;
  Future<void> _pick([ImageSource source = ImageSource.gallery]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (x == null || !mounted) return;
      _source = File(x.path);
      _sourceSize = await _source!.length();
      await _compress(showBusy: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this photo. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compress({bool showBusy = true}) async {
    final s = _source;
    if (s == null) return;
    if (showBusy) setState(() => _busy = true);
    try {
      final raw = await s.readAsBytes();
      var q = _quality;
      Uint8List bytes = await compute(_compressLocalPhoto, <String, Object?>{
        'bytes': raw,
        'quality': q,
        'target': _target,
      });
      while (bytes.length > _target && q > 30) {
        q -= 10;
        bytes = await compute(_compressLocalPhoto, <String, Object?>{
          'bytes': raw,
          'quality': q,
          'target': _target,
        });
      }
      _quality = q;
      if (mounted) setState(() => _out = bytes);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not decode the selected image.')),
        );
    } finally {
      if (showBusy && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_out == null) return;
    setState(() => _busy = true);
    try {
      await InterstitialAdService.showForToolProcessing(context);
      if (!mounted) return;
      await _shareToolImage(context, _out!, 'vyro-compressed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo Compressor')),
    body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.photo),
              label: const Text('Choose photo'),
            ),
            const SizedBox(height: 12),
            DropdownButton<int>(
              value: _target,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 512000, child: Text('Target · 500 KB')),
                DropdownMenuItem(value: 1048576, child: Text('Target · 1 MB')),
                DropdownMenuItem(value: 2097152, child: Text('Target · 2 MB')),
              ],
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    _target = v;
                    _quality = 90;
                  });
                _compress();
              },
            ),
            if (_source != null)
              Text('Original: ${(_sourceSize / 1024).toStringAsFixed(0)} KB'),
            if (_out != null) ...[
              Text(
                'Output: ${(_out!.length / 1024).toStringAsFixed(0)} KB · JPEG quality $_quality',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download),
                label: const Text('Export compressed copy'),
              ),
            ],
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: _ToolLoadingOverlay(title: 'Compressing your photo'),
          ),
      ],
    ),
  );
}

class SocialMediaScreen extends StatefulWidget {
  const SocialMediaScreen({
    super.key,
    this.initialPreset = 0,
    this.circle = false,
  });
  final int initialPreset;
  final bool circle;
  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen> {
  static const _titles = [
    'Instagram Post · 1:1',
    'Instagram Story · 9:16',
    'WhatsApp DP · 1:1',
    'LinkedIn · 1:1',
    'YouTube Thumbnail · 16:9',
    'Phone Wallpaper · 9:16',
    'Passport / ID · 35:45',
  ];
  static const _ratios = [1.0, 9 / 16, 1.0, 1.0, 16 / 9, 9 / 16, 35 / 45];
  int _preset = 0;
  ui.Image? _image;
  Uint8List? _png;
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _fontSize = 30;
  String _text = '';
  TextAlign _textAlign = TextAlign.center;
  double _scaleStart = 1;
  Color _background = const Color(0xFF1C1830);
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _preset = widget.initialPreset.clamp(0, 6);
  }

  Future<void> _pick([ImageSource source = ImageSource.gallery]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: _toolPickMaxDimension,
        maxHeight: _toolPickMaxDimension,
        imageQuality: _toolPickQuality,
        requestFullMetadata: false,
      );
      if (x == null || !mounted) return;
      final bytes = await _processPickedFile(
        File(x.path),
        mode: 'social',
        maxDimension: 1400,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        _image?.dispose();
        setState(() {
          _image = frame.image;
          _png = Uint8List.fromList(bytes);
          _scale = 1;
          _offset = Offset.zero;
        });
      } else {
        frame.image.dispose();
      }
      codec.dispose();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this image.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final im = _image;
    if (im == null) return;
    setState(() => _busy = true);
    try {
      final ratio = _ratios[_preset];
      const w = 1080.0;
      final h = _preset == 6 ? 1620.0 : w / ratio;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawColor(_background, BlendMode.src);
      final fit = applyBoxFit(
        widget.circle ? BoxFit.cover : BoxFit.contain,
        Size(im.width.toDouble(), im.height.toDouble()),
        Size(w, h),
      );
      final src = Alignment.center.inscribe(
        fit.source,
        Offset.zero & Size(im.width.toDouble(), im.height.toDouble()),
      );
      final dst = Alignment.center.inscribe(fit.destination, rect);
      canvas.save();
      if (widget.circle) {
        canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, w, h < w ? h : w)));
      }
      canvas.translate(_offset.dx * w, _offset.dy * h);
      canvas.translate(w / 2, h / 2);
      canvas.scale(_scale);
      canvas.translate(-w / 2, -h / 2);
      if (_preset == 6) {
        final cellW = 420.0, cellH = 540.0;
        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < 2; col++) {
            final r = Rect.fromLTWH(
              90 + col * 480,
              0 + row * 540,
              cellW,
              cellH,
            );
            final perCopy = applyBoxFit(
              BoxFit.contain,
              Size(im.width.toDouble(), im.height.toDouble()),
              r.size,
            );
            final copySource = Alignment.center.inscribe(
              perCopy.source,
              Offset.zero & Size(im.width.toDouble(), im.height.toDouble()),
            );
            final copyDestination = Alignment.center.inscribe(
              perCopy.destination,
              r,
            );
            canvas.drawImageRect(
              im,
              copySource,
              copyDestination,
              Paint()..filterQuality = FilterQuality.high,
            );
          }
        }
      } else {
        canvas.drawImageRect(
          im,
          src,
          dst,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      canvas.restore();
      if (widget.circle) {
        canvas.drawOval(
          Rect.fromLTWH(4, 4, w - 8, h < w ? h - 8 : w - 8),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 18
            ..color = _violet,
        );
      }
      if (_text.trim().isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: _text,
            style: TextStyle(
              color: Colors.white,
              fontSize: _fontSize * (w / 360),
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: _textAlign,
        )..layout(maxWidth: w - 80);
        final textX = switch (_textAlign) {
          TextAlign.left => 40.0,
          TextAlign.right => w - tp.width - 40,
          _ => (w - tp.width) / 2,
        };
        tp.paint(canvas, Offset(textX, h - tp.height - 50));
      }
      final picture = rec.endRecording();
      final rendered = await picture.toImage(w.round(), h.round());
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      rendered.dispose();
      await InterstitialAdService.showForToolProcessing(context);
      if (mounted) await _shareToolImage(context, bytes, 'vyro-social');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final im = _image;
    final ratio = _ratios[_preset];
    return Scaffold(
      appBar: AppBar(title: const Text('Social Creator')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              DropdownButton<int>(
                value: _preset,
                isExpanded: true,
                items: List.generate(
                  _titles.length,
                  (i) => DropdownMenuItem(value: i, child: Text(_titles[i])),
                ),
                onChanged: (v) => setState(() => _preset = v ?? 0),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: ClipRect(
                    child: GestureDetector(
                      onScaleStart: (_) => _scaleStart = _scale,
                      onScaleUpdate: (d) => setState(() {
                        _scale = (_scaleStart * d.scale).clamp(1, 4);
                        _offset += d.focalPointDelta / 500;
                      }),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Container(
                          color: _background,
                          child: im == null
                              ? const Center(
                                  child: Text(
                                    'Choose a photo',
                                    style: TextStyle(color: _muted),
                                  ),
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Transform.translate(
                                      offset: Offset(
                                        _offset.dx * constraints.maxWidth,
                                        _offset.dy * constraints.maxHeight,
                                      ),
                                      child: Transform.scale(
                                        scale: _scale,
                                        child: widget.circle
                                            ? ClipOval(
                                                child: Image.memory(
                                                  _png!,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 1200,
                                                  filterQuality:
                                                      FilterQuality.medium,
                                                ),
                                              )
                                            : Image.memory(
                                                _png!,
                                                fit: BoxFit.contain,
                                                cacheWidth: 1200,
                                                filterQuality:
                                                    FilterQuality.medium,
                                              ),
                                      ),
                                    ),
                                    if (widget.circle)
                                      Center(
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: _violet,
                                                width: 4,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_text.isNotEmpty)
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Text(
                                            _text,
                                            textAlign: _textAlign,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: _fontSize,
                                              fontWeight: FontWeight.bold,
                                              shadows: const [
                                                Shadow(
                                                  blurRadius: 5,
                                                  color: Colors.black,
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
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Drag to reposition / pinch to zoom / image stays proportional',
              ),
              Slider(
                value: _scale,
                min: 1,
                max: 4,
                onChanged: (v) => setState(() => _scale = v),
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Optional text'),
                onChanged: (v) => setState(() => _text = v),
              ),
              SegmentedButton<TextAlign>(
                segments: const [
                  ButtonSegment(value: TextAlign.left, label: Text('Left')),
                  ButtonSegment(value: TextAlign.center, label: Text('Center')),
                  ButtonSegment(value: TextAlign.right, label: Text('Right')),
                ],
                selected: {_textAlign},
                onSelectionChanged: (v) => setState(() => _textAlign = v.first),
              ),
              Slider(
                value: _fontSize,
                min: 14,
                max: 54,
                onChanged: (v) => setState(() => _fontSize = v),
              ),
              Wrap(
                spacing: 10,
                children: [
                  for (final c in [
                    const Color(0xFF1C1830),
                    Colors.black,
                    Colors.white,
                    const Color(0xFF562A7A),
                    const Color(0xFF173B4B),
                  ])
                    InkWell(
                      onTap: () => setState(() => _background = c),
                      child: CircleAvatar(backgroundColor: c, radius: 16),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy || im == null ? null : _export,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export and share'),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: _ToolLoadingOverlay(title: 'Building your social design'),
            ),
        ],
      ),
    );
  }
}

class CollageMakerScreen extends StatefulWidget {
  const CollageMakerScreen({super.key});
  @override
  State<CollageMakerScreen> createState() => _CollageMakerScreenState();
}

class _CollageMakerScreenState extends State<CollageMakerScreen> {
  List<Uint8List> _photos = [];
  int _count = 2;
  double _spacing = 8;
  Color _background = _panel;
  bool _busy = false;
  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await ImagePicker().pickMultiImage(
        limit: _count,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 82,
        requestFullMetadata: false,
      );
      if (files.isEmpty || !mounted) return;
      final list = <Uint8List>[];
      for (final f in files.take(_count)) {
        list.add(
          await _processPickedFile(
            File(f.path),
            mode: 'social',
            maxDimension: 900,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _photos = list;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load those photos. Try fewer or smaller images.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replace(int index) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 82,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      final safe = await _processPickedFile(
        File(file.path),
        mode: 'social',
        maxDimension: 900,
      );
      final updated = [..._photos];
      updated[index] = safe;
      if (mounted) setState(() => _photos = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not replace that photo. Try a smaller image.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_photos.isEmpty) return;
    setState(() => _busy = true);
    final pics = <ui.Image>[];
    try {
      for (final b in _photos) {
        final c = await ui.instantiateImageCodec(b);
        pics.add((await c.getNextFrame()).image);
      }
      const w = 1080.0, h = 1350.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..drawColor(_background, BlendMode.src);
      final cols = _count == 2 || _count == 3 ? 2 : 2;
      final rows = (_count / cols).ceil();
      final cw = (w - _spacing * (cols + 1)) / cols,
          ch = (h - _spacing * (rows + 1)) / rows;
      for (var i = 0; i < pics.length; i++) {
        final x = i % cols, y = i ~/ cols;
        final dst = Rect.fromLTWH(
          _spacing + x * (cw + _spacing),
          _spacing + y * (ch + _spacing),
          cw,
          ch,
        );
        final fit = applyBoxFit(
          BoxFit.cover,
          Size(pics[i].width.toDouble(), pics[i].height.toDouble()),
          dst.size,
        );
        final src = Alignment.center.inscribe(
          fit.source,
          Offset.zero &
              Size(pics[i].width.toDouble(), pics[i].height.toDouble()),
        );
        canvas.drawImageRect(
          pics[i],
          src,
          dst,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      final image = await rec.endRecording().toImage(w.round(), h.round());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await InterstitialAdService.showForToolProcessing(context);
      if (mounted)
        await _shareToolImage(
          context,
          data!.buffer.asUint8List(),
          'vyro-collage',
        );
    } finally {
      for (final pic in pics) {
        pic.dispose();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Collage Maker')),
    body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButton<int>(
              value: _count,
              items: const [2, 3, 4, 6]
                  .map(
                    (n) => DropdownMenuItem(value: n, child: Text('$n photos')),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _count = v ?? 2),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text('Choose up to $_count photos'),
            ),
            Slider(
              value: _spacing,
              min: 0,
              max: 32,
              onChanged: (v) => setState(() => _spacing = v),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final c in [_panel, Colors.white, Colors.black, _violet])
                  InkWell(
                    onTap: () => setState(() => _background = c),
                    child: CircleAvatar(backgroundColor: c, radius: 16),
                  ),
              ],
            ),
            if (_photos.isNotEmpty)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    InkWell(
                      onTap: () => _replace(i),
                      child: Image.memory(
                        _photos[i],
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                ],
              ),
            FilledButton.icon(
              onPressed: _photos.isEmpty || _busy ? null : _export,
              icon: const Icon(Icons.download),
              label: const Text('Export collage'),
            ),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: _ToolLoadingOverlay(title: 'Composing your collage'),
          ),
      ],
    ),
  );
}
