import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'ump_consent_service.dart';

class RewardedAdService {
  static RewardedAd? _rewardedAd;
  static bool _isLoading = false;
  static bool _isShowing = false;
  static DateTime? _lastRewardedAt;

  static bool get rewardedRecently =>
      _lastRewardedAt != null &&
      DateTime.now().difference(_lastRewardedAt!) <
          const Duration(seconds: 45);

  // Production rewarded ad units, one per platform.
  // This service intentionally uses the production unit in all builds.
  static const String _androidAdUnitId =
      'ca-app-pub-7694497723149363/9751807400';
  static const String _iosAdUnitId =
      'ca-app-pub-7694497723149363/8453252739';

  static String get adUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _iosAdUnitId
          : _androidAdUnitId;

  static const String _baseUrl = generationApiBaseUrl;

  static bool get isReady => _rewardedAd != null;
  static bool get isLoading => _isLoading;
  static bool get isShowing => _isShowing;

  static void preloadRewardedAd() {
    if (_rewardedAd != null || _isLoading || _isShowing) return;

    _isLoading = true;
    debugPrint('RewardedAdService: loading production rewarded ad');

    unawaited(_loadWhenConsentAllows());
  }

  static Future<void> _loadWhenConsentAllows() async {
    try {
      if (!await UmpConsentService.instance.canRequestAds()) {
        debugPrint(
          'RewardedAdService: UMP does not allow ad requests',
        );
        _isLoading = false;
        return;
      }
    } catch (error) {
      debugPrint(
        'RewardedAdService: consent check failed: $error',
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

          if (!UmpConsentService.instance.adsAllowed) {
            ad.dispose();
            return;
          }

          _rewardedAd?.dispose();
          _rewardedAd = ad;

          debugPrint(
            'RewardedAdService: production ad loaded',
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _rewardedAd = null;

          debugPrint(
            'RewardedAdService: load failed: $error',
          );
        },
      ),
    );
  }

  static Future<bool> showRewardedAd({
    VoidCallback? onAdPreparing,
    VoidCallback? onAdNotReady,
    void Function(int credits)? onRewardGranted,
    void Function(Object error)? onRewardFailed,
  }) async {
    if (_isShowing) return false;

    if (!await UmpConsentService.instance.canRequestAds()) {
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
        await Future<void>.delayed(
          const Duration(milliseconds: pollMs),
        );
        waitedMs += pollMs;
      }
    }

    final ad = _rewardedAd;

    if (ad == null) {
      debugPrint(
        'RewardedAdService: production ad not ready',
      );
      onAdNotReady?.call();
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
        debugPrint(
          'RewardedAdService: production ad shown',
        );
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

        debugPrint(
          'RewardedAdService: show failed: $error',
        );

        completeResult(false);
      },
    );

    ad.show(
      onUserEarnedReward:
          (AdWithoutView ad, RewardItem reward) async {
        if (rewardCallbackReceived) return;

        rewardCallbackReceived = true;

        debugPrint(
          'RewardedAdService: ADMOB REWARD EARNED '
          '${reward.amount} ${reward.type}',
        );

        try {
          final granted = await _grantBackendReward(
            rewardId: rewardId,
          );

          if (granted != null) {
            _lastRewardedAt = DateTime.now();
            onRewardGranted?.call(granted);
          }

          completeResult(granted != null);
        } catch (error) {
          debugPrint(
            'RewardedAdService: backend reward failed: $error',
          );

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

  static Future<int?> _grantBackendReward({
    required String rewardId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError(
        'Firebase user is not authenticated.',
      );
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw StateError(
        'Firebase ID token is unavailable.',
      );
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/v1/rewards/ad'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type':
                'application/x-www-form-urlencoded',
          },
          body: {
            'rewardId': rewardId,
          },
        )
        .timeout(
          const Duration(seconds: 20),
        );

    debugPrint(
      'RewardedAdService: reward API '
      '${response.statusCode} ${response.body}',
    );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw StateError(
        'Reward API failed with HTTP '
        '${response.statusCode}.',
      );
    }

    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic> ||
        data['granted'] != true) {
      return null;
    }

    return (data['creditsAwarded'] as num?)?.toInt() ?? 0;
  }

  static void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoading = false;
    _isShowing = false;
  }

  static void clearForConsentChange() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoading = false;
  }
}
