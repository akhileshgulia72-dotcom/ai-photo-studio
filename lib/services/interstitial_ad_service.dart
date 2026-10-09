import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'account_profile_service.dart';
import 'ad_unit_config.dart';
import 'rewarded_ad_service.dart';
import 'ump_consent_service.dart';

class InterstitialAdService {
  static InterstitialAd? _ad;
  static bool _loading = false;
  static bool _showing = false;
  static bool _consentListenerAttached = false;
  static int _loadGeneration = 0;

  /// Counts AI template-card selections. Every [TemplateClickCounter.interval]
  /// selection is an eligible ad event.
  static final TemplateClickCounter _counter = TemplateClickCounter();

  /// Counts screen-to-screen navigations for the separate transition policy.
  static final ScreenTransitionCounter _navCounter = ScreenTransitionCounter();

  /// Minimum spacing between two interstitials. Keeps the every-3rd rule from
  /// stacking ads back-to-back when a user taps through screens quickly.
  static const Duration minimumGap = Duration(seconds: 60);

  static DateTime? _lastShownAt;

  static bool _templateAdDue = false;

  /// Bounded retry state, cancelled on load, consent change or dispose.
  static Timer? _retryTimer;
  static int _retryAttempt = 0;

  static const int _maxLoadRetries = 4;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// True when no interstitial has been shown inside [minimumGap].
  static bool get cooldownElapsed {
    final last = _lastShownAt;
    return last == null || DateTime.now().difference(last) >= minimumGap;
  }

  static String get adUnitId => AdUnitConfig.interstitial;

  static void preload() {
    _attachConsentListener();
    if (_ad != null || _loading || _showing || adUnitId.isEmpty) {
      return;
    }

    _loading = true;
    final generation = ++_loadGeneration;
    unawaited(_loadWhenConsentAllows(generation));
  }

  static void _attachConsentListener() {
    if (_consentListenerAttached) return;
    _consentListenerAttached = true;
    UmpConsentService.instance.addListener(() {
      if (!UmpConsentService.instance.adsAllowed) {
        clearForConsentChange();
      } else {
        preload();
      }
    });
  }

  static Future<void> _loadWhenConsentAllows(int generation) async {
    // Wait for consent and SDK init together instead of sampling once.
    final allowed = await UmpConsentService.instance.waitUntilReady(
      timeout: const Duration(seconds: 12),
    );

    if (generation != _loadGeneration) return;

    if (!allowed) {
      debugPrint(
        'InterstitialAdService: not loading - '
        '${UmpConsentService.instance.describe()}',
      );
      _loading = false;
      return;
    }

    if (_ad != null || _showing || adUnitId.isEmpty) {
      _loading = false;
      return;
    }

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (generation != _loadGeneration) {
            ad.dispose();
            return;
          }
          _loading = false;
          _cancelRetry();

          if (!UmpConsentService.instance.adsAllowed) {
            debugPrint(
              'InterstitialAdService: consent withdrawn before load '
              'completed, disposing ad',
            );
            ad.dispose();
            return;
          }

          _ad?.dispose();
          _ad = ad;

          debugPrint('InterstitialAdService: ad loaded and ready');
        },
        onAdFailedToLoad: (error) {
          if (generation != _loadGeneration) return;
          _loading = false;
          _ad = null;

          _logLoadError(error);
          _scheduleRetry();
        },
      ),
    );
  }

  static void _logLoadError(LoadAdError error) {
    final buffer = StringBuffer()
      ..writeln('InterstitialAdService: load FAILED')
      ..writeln('  code:     ${error.code}')
      ..writeln('  domain:   ${error.domain}')
      ..writeln('  message:  ${error.message}')
      ..writeln('  unit:     $adUnitId')
      ..writeln('  testMode: ${AdUnitConfig.useTestAds}')
      ..writeln('  platform: ${AdUnitConfig.platformName}');

    final responseInfo = error.responseInfo;
    if (responseInfo != null) {
      final responses = responseInfo.adapterResponses ?? const [];
      buffer
        ..writeln('  adapter:  ${responses.length} response(s)')
        ..writeln('  responseId: ${responseInfo.responseId}');
      for (final response in responses) {
        buffer.writeln(
          '    - ${response.adapterClassName} '
          '${response.description} '
          'latency=${response.latencyMillis}ms',
        );
      }
    } else {
      buffer.writeln('  responseInfo: unavailable');
    }

    debugPrint(buffer.toString());
  }

  static void _scheduleRetry() {
    if (!UmpConsentService.instance.adsAllowed) return;
    if (_retryAttempt >= _maxLoadRetries) {
      debugPrint(
        'InterstitialAdService: giving up after $_retryAttempt retries',
      );
      return;
    }

    final delay =
        _retryDelays[_retryAttempt < _retryDelays.length
            ? _retryAttempt
            : _retryDelays.length - 1];
    _retryAttempt++;

    debugPrint(
      'InterstitialAdService: scheduling retry $_retryAttempt/$_maxLoadRetries '
      'in $delay',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_ad != null || _showing || _loading) return;
      if (!UmpConsentService.instance.adsAllowed) return;
      preload();
    });
  }

  static void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  static Future<bool> _isPremium() async {
    try {
      return (await AccountProfileService.instance.refresh()).isAdFree;
    } catch (_) {
      // Fail closed: do not risk showing an ad to a paid user
      // while entitlement cannot be verified.
      return true;
    }
  }

  /// Call only after a user taps an AI template card.
  /// The counter is static for the entire app process, so rebuilds
  /// and navigation cannot reset it.
  static Future<void> showForTemplateCardClick(BuildContext context) async {
    if (!_counter.recordSelection()) {
      preload();
      return;
    }

    if (_showing ||
        !cooldownElapsed ||
        RewardedAdService.rewardedRecently ||
        await _isPremium()) {
      preload();
      return;
    }

    if (!context.mounted) return;

    _templateAdDue = true;

    await _show(context);

    _templateAdDue = false;
  }

  static int get templateClicksForDebug => _counter.count;

  static bool get isShowing => _showing;

  /// Records one screen-to-screen move and reports whether it is the eligible
  /// every-3rd transition.
  ///
  /// Called synchronously from the navigator observer so the cadence is not
  /// distorted by whether an ad happened to be on cooldown.
  static bool beginNavigation() => _navCounter.recordTransition();

  /// Shows the interstitial for a transition that [beginNavigation] already
  /// accepted. Applies the cooldown and entitlement checks, then displays.
  static Future<void> showForNavigation(BuildContext context) async {
    if (_showing ||
        !cooldownElapsed ||
        RewardedAdService.rewardedRecently ||
        await _isPremium() ||
        !context.mounted) {
      preload();
      return;
    }

    await _show(context);
  }

  static Future<void> showForDownload(BuildContext context) async {
    if (_templateAdDue || await _isPremium() || !context.mounted) {
      return;
    }

    await _show(context);
  }

  /// Tool exports are a separate ad event from AI template selection.
  /// This deliberately does not touch the template click counter.
  static Future<void> showForToolProcessing(BuildContext context) async {
    if (_showing ||
        RewardedAdService.rewardedRecently ||
        await _isPremium() ||
        !context.mounted) {
      preload();
      return;
    }

    await _show(context);
  }

  static Future<void> _show(BuildContext context) async {
    if (!await UmpConsentService.instance.waitUntilReady(
      timeout: const Duration(seconds: 5),
    )) {
      clearForConsentChange();
      return;
    }

    var ad = _ad;

    // If the ad is currently loading, give it a short opportunity
    // to become ready before silently skipping this eligible event.
    if (ad == null && _loading) {
      const maxWaitMs = 5000;
      const pollMs = 100;
      var waitedMs = 0;

      while (_loading && waitedMs < maxWaitMs) {
        await Future<void>.delayed(const Duration(milliseconds: pollMs));
        waitedMs += pollMs;
      }

      ad = _ad;
    }

    if (ad == null || _showing) {
      preload();
      return;
    }

    _ad = null;
    _showing = true;

    final completer = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        // Stamp the shared cooldown only once an ad really covered the app.
        _lastShownAt = DateTime.now();

        debugPrint('InterstitialAdService: ad shown');
      },
      onAdDismissedFullScreenContent: (ad) {
        _showing = false;
        ad.dispose();

        preload();

        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _showing = false;
        ad.dispose();

        preload();

        debugPrint('InterstitialAdService: show failed: ${error.message}');

        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    ad.show();

    await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {},
    );
  }

  static void clearForConsentChange() {
    _loadGeneration++;
    _cancelRetry();
    _ad?.dispose();
    _ad = null;
    _loading = false;
  }
}

/// Watches pushes so a screen-to-screen move can serve an interstitial on
/// every 3rd transition.
///
/// Only real content screens count: dialogs, bottom sheets and other popup
/// routes are ignored, because an ad covering a dialog the user just opened
/// feels like a malfunction.
///
/// Every non-popup push is handed to the service, which owns the cadence and
/// advances its counter exactly once per move. Cooldown-blocked moves still
/// count, so the every-3rd rhythm tracks actual navigation rather than
/// resetting whenever an ad is skipped.
class InterstitialNavigationObserver extends NavigatorObserver {
  /// Lets the destination screen settle before covering it with an ad.
  static const Duration _settleDelay = Duration(milliseconds: 700);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    if (route is PopupRoute) return;

    final context = route.navigator?.context;
    if (context == null) return;

    // Capture the eligible move now, then defer only the display so the user
    // sees the new screen before the ad covers it.
    final eligible = InterstitialAdService.beginNavigation();
    if (!eligible) return;

    Future<void>.delayed(_settleDelay, () {
      if (!context.mounted) return;
      unawaited(InterstitialAdService.showForNavigation(context));
    });
  }
}

/// Session-persistent counting policy used only by
/// template-card selections.
class TemplateClickCounter {
  TemplateClickCounter({this.interval = 3}) : assert(interval > 0);

  final int interval;

  int _count = 0;

  int get count => _count;

  /// Returns true exactly on the intervalth selection
  /// and resets the cycle.
  bool recordSelection() {
    _count++;

    if (_count < interval) {
      return false;
    }

    _count = 0;
    return true;
  }
}

/// Session-persistent counting policy for screen-to-screen navigation.
///
/// Kept separate from [TemplateClickCounter] so a user tapping through screens
/// and a user tapping template cards each get their own every-3rd cadence.
class ScreenTransitionCounter {
  ScreenTransitionCounter({this.interval = 3}) : assert(interval > 0);

  final int interval;

  int _count = 0;

  int get count => _count;

  /// Records one navigation and returns true when it is the eligible one.
  bool recordTransition() {
    _count++;

    if (_count < interval) {
      return false;
    }

    _count = 0;
    return true;
  }
}
