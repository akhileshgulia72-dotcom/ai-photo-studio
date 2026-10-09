import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;

import 'ad_unit_config.dart';
import 'api_config.dart';
import 'ump_consent_service.dart';

class RewardedAdService {
  static RewardedAd? _rewardedAd;
  static bool _isLoading = false;
  static bool _isShowing = false;
  static DateTime? _lastRewardedAt;

  /// Bounded retry state. Cancelled whenever an ad loads, consent changes,
  /// or the service is disposed, so retries can never run forever or stack.
  static Timer? _retryTimer;
  static int _retryAttempt = 0;

  static const int _maxLoadRetries = 4;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  static bool get rewardedRecently =>
      _lastRewardedAt != null &&
      DateTime.now().difference(_lastRewardedAt!) < const Duration(seconds: 45);

  static String get adUnitId => AdUnitConfig.rewarded;

  static const String _baseUrl = generationApiBaseUrl;

  static bool get isReady => _rewardedAd != null;
  static bool get isLoading => _isLoading;
  static bool get isShowing => _isShowing;

  static void preloadRewardedAd() {
    if (_rewardedAd != null || _isLoading || _isShowing) return;

    _isLoading = true;
    debugPrint(
      'RewardedAdService: loading rewarded ad '
      '(${AdUnitConfig.useTestAds ? 'TEST' : 'PRODUCTION'} unit ${AdUnitConfig.rewarded})',
    );

    unawaited(_loadWhenConsentAllows());
  }

  static Future<void> _loadWhenConsentAllows() async {
    // Wait for consent *and* SDK init rather than sampling once. Sampling
    // once meant a preload that raced startup was dropped permanently.
    final allowed = await UmpConsentService.instance.waitUntilReady(
      timeout: const Duration(seconds: 12),
    );

    if (!allowed) {
      debugPrint(
        'RewardedAdService: not loading - '
        '${UmpConsentService.instance.describe()}',
      );
      _isLoading = false;
      return;
    }

    if (_rewardedAd != null || _isShowing) {
      _isLoading = false;
      return;
    }

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _isLoading = false;
          _cancelRetry();

          if (!UmpConsentService.instance.adsAllowed) {
            debugPrint(
              'RewardedAdService: consent withdrawn before load completed, '
              'disposing ad',
            );
            ad.dispose();
            return;
          }

          _rewardedAd?.dispose();
          _rewardedAd = ad;

          debugPrint('RewardedAdService: ad loaded and ready');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _rewardedAd = null;

          _logLoadError('rewarded', error);
          _scheduleRetry('rewarded');
        },
      ),
    );
  }

  /// Logs every field [LoadAdError] exposes, so a failing unit can be
  /// diagnosed from the device log without guessing.
  static void _logLoadError(String format, LoadAdError error) {
    final buffer = StringBuffer()
      ..writeln('RewardedAdService: $format load FAILED')
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

  static void _scheduleRetry(String format) {
    if (!UmpConsentService.instance.adsAllowed) return;
    if (_retryAttempt >= _maxLoadRetries) {
      debugPrint(
        'RewardedAdService: giving up on $format after $_retryAttempt retries',
      );
      return;
    }

    final delay =
        _retryDelays[_retryAttempt < _retryDelays.length
            ? _retryAttempt
            : _retryDelays.length - 1];
    _retryAttempt++;

    debugPrint(
      'RewardedAdService: scheduling $format retry '
      '$_retryAttempt/$_maxLoadRetries in $delay',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_rewardedAd != null || _isShowing || _isLoading) return;
      if (!UmpConsentService.instance.adsAllowed) return;
      preloadRewardedAd();
    });
  }

  static void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  static Future<bool> showRewardedAd({
    VoidCallback? onAdPreparing,
    VoidCallback? onAdNotReady,
    void Function(int credits)? onRewardGranted,
    void Function(Object error)? onRewardFailed,
  }) async {
    if (_isShowing) return false;

    // A user-initiated rewarded ad may wait briefly for the SDK, since the
    // user has explicitly asked for it.
    if (!await UmpConsentService.instance.waitUntilReady(
      timeout: const Duration(seconds: 10),
    )) {
      debugPrint(
        'RewardedAdService: cannot show - '
        '${UmpConsentService.instance.describe()}',
      );
      onAdNotReady?.call();
      return false;
    }

    if (_rewardedAd == null && !_isLoading) {
      preloadRewardedAd();
    }

    if (_rewardedAd == null) {
      onAdPreparing?.call();

      const maxWaitMs = 15000;
      const pollMs = 100;
      var waitedMs = 0;

      while (_isLoading && waitedMs < maxWaitMs) {
        await Future<void>.delayed(const Duration(milliseconds: pollMs));
        waitedMs += pollMs;
      }
    }

    final ad = _rewardedAd;

    if (ad == null) {
      debugPrint('RewardedAdService: ad not ready to show');
      onAdNotReady?.call();
      // A failed show is still an eligible moment to try loading again.
      _scheduleRetry('rewarded');
      return false;
    }

    _rewardedAd = null;
    _isShowing = true;

    final result = Completer<bool>();
    bool rewardCallbackReceived = false;

    final rewardId =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${FirebaseAuth.instance.currentUser?.uid ?? 'unknown'}';

    void completeResult(bool value) {
      if (!result.isCompleted) {
        result.complete(value);
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('RewardedAdService: ad shown');
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowing = false;

        ad.dispose();

        preloadRewardedAd();

        debugPrint(
          'RewardedAdService: ad dismissed | '
          'rewardCallback=$rewardCallbackReceived',
        );

        if (!rewardCallbackReceived) {
          completeResult(false);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;

        ad.dispose();

        preloadRewardedAd();

        debugPrint('RewardedAdService: show failed: ${error.message}');

        completeResult(false);
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        if (rewardCallbackReceived) return;

        rewardCallbackReceived = true;

        debugPrint(
          'RewardedAdService: ADMOB REWARD EARNED '
          '${reward.amount} ${reward.type}',
        );

        try {
          final granted = await _grantBackendReward(rewardId: rewardId);

          if (granted != null) {
            _lastRewardedAt = DateTime.now();
            onRewardGranted?.call(granted);
          }

          completeResult(granted != null);
        } catch (error) {
          debugPrint('RewardedAdService: backend reward failed: $error');

          onRewardFailed?.call(error);
          completeResult(false);
        }
      },
    );

    return result.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => false,
    );
  }

  static Future<int?> _grantBackendReward({required String rewardId}) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('Firebase user is not authenticated.');
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw StateError('Firebase ID token is unavailable.');
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/v1/rewards/ad'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'rewardId': rewardId},
        )
        .timeout(const Duration(seconds: 20));

    debugPrint(
      'RewardedAdService: reward API '
      '${response.statusCode}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Reward API failed with HTTP '
        '${response.statusCode}.',
      );
    }

    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic> || data['granted'] != true) {
      return null;
    }

    return (data['creditsAwarded'] as num?)?.toInt() ?? 0;
  }

  static void dispose() {
    _cancelRetry();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoading = false;
    _isShowing = false;
  }

  static void clearForConsentChange() {
    _cancelRetry();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoading = false;
  }
}
