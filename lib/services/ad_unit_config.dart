import 'package:flutter/foundation.dart';

/// Single source of truth for every AdMob ad unit id in the app.
///
/// Two independent decisions are made here, and they must never be
/// conflated:
///
///   1. Platform — Android and iOS need *different* production unit ids.
///      Using an Android unit id in an iOS slot silently serves nothing,
///      which is invisible in the AdMob dashboard.
///   2. Environment — production units must never be requested from a
///      development build, and test units must never ship.
///
/// [useTestAds] is a compile-time constant, so the ids below cannot be
/// swapped at runtime and test ids cannot reach a release build by
/// accident. It defaults to `false`: a normal build uses the real ids.
///
/// Enable test ads with:
///   flutter run --dart-define=ADMOB_USE_TEST_ADS=true
class AdUnitConfig {
  AdUnitConfig._();

  /// Compile-time switch. Absent, or anything other than `true`, disables it.
  static const bool useTestAds =
      kDebugMode &&
      bool.fromEnvironment('ADMOB_USE_TEST_ADS', defaultValue: false);

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static String get platformName => _isIOS ? 'iOS' : 'Android';

  // ===============================================================
  // Production unit ids — unchanged from what is already shipping.
  // ===============================================================

  static const String _prodRewardedAndroid =
      'ca-app-pub-7694497723149363/9751807400';
  static const String _prodRewardedIos =
      'ca-app-pub-7694497723149363/8453252739';

  static const String _prodInterstitialAndroid =
      'ca-app-pub-7694497723149363/7630322351';
  static const String _prodInterstitialIos =
      'ca-app-pub-7694497723149363/8336693504';

  static const String _prodNativeAndroid =
      'ca-app-pub-7694497723149363/6374835026';
  static const String _prodNativeIos = 'ca-app-pub-7694497723149363/7462595539';

  // ===============================================================
  // Google's official test unit ids.
  //
  // Google publishes rewarded, interstitial, banner, and native test units
  // for both platforms. These IDs are selected only in debug builds when
  // ADMOB_USE_TEST_ADS=true is passed.
  // ===============================================================

  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIos =
      'ca-app-pub-3940256099942544/1712485313';

  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static const String _testNativeAndroid =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  // ===============================================================
  // Selectors
  // ===============================================================

  static String get rewarded => useTestAds
      ? (_isIOS ? _testRewardedIos : _testRewardedAndroid)
      : (_isIOS ? _prodRewardedIos : _prodRewardedAndroid);

  static String get interstitial => useTestAds
      ? (_isIOS ? _testInterstitialIos : _testInterstitialAndroid)
      : (_isIOS ? _prodInterstitialIos : _prodInterstitialAndroid);

  /// Native advanced test unit in debug test mode, otherwise production unit.
  static String get native {
    if (useTestAds) return _isIOS ? _testNativeIos : _testNativeAndroid;
    return _isIOS ? _prodNativeIos : _prodNativeAndroid;
  }

  /// Banner. The app does not currently render a banner, and no banner
  /// production unit is configured, so there is nothing to request. When a banner slot is
  /// added, set the production ids here rather than inventing them inline.
  static String? get banner {
    if (useTestAds) return _isIOS ? _testBannerIos : _testBannerAndroid;
    return null;
  }

  /// Production native id regardless of [useTestAds]. Exposed only so the
  /// configuration tests can assert production values do not drift.
  @visibleForTesting
  static String get productionNative =>
      _isIOS ? _prodNativeIos : _prodNativeAndroid;

  /// Production ids for a given platform, for configuration testing.
  @visibleForTesting
  static Map<String, String> productionIdsFor({
    required TargetPlatform platform,
  }) {
    final bool ios = platform == TargetPlatform.iOS;
    return <String, String>{
      'rewarded': ios ? _prodRewardedIos : _prodRewardedAndroid,
      'interstitial': ios ? _prodInterstitialIos : _prodInterstitialAndroid,
      'native': ios ? _prodNativeIos : _prodNativeAndroid,
    };
  }

  /// Google's test ids for a given platform, for configuration testing.
  @visibleForTesting
  static Map<String, String?> testIdsFor({required TargetPlatform platform}) {
    final bool ios = platform == TargetPlatform.iOS;
    return <String, String?>{
      'rewarded': ios ? _testRewardedIos : _testRewardedAndroid,
      'interstitial': ios ? _testInterstitialIos : _testInterstitialAndroid,
      'native': ios ? _testNativeIos : _testNativeAndroid,
      'banner': ios ? _testBannerIos : _testBannerAndroid,
    };
  }

  /// Human-readable summary for startup diagnostics.
  static String describe() =>
      'AdUnitConfig(platform: $platformName, useTestAds: $useTestAds, '
      'native: $native)';
}
