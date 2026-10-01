import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;

class RewardedAdService {
  static RewardedAd? _rewardedAd;
  static bool _isLoading = false;
  static bool _isShowing = false;

  static const String _productionAdUnitId =
      'ca-app-pub-7694497723149363/4829954140';

  // Official Google test rewarded-ad unit for Android.
  static const String _testAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  static String get adUnitId =>
      kDebugMode ? _testAdUnitId : _productionAdUnitId;

  static const String _baseUrl = String.fromEnvironment(
    'GENERATION_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static bool get isReady => _rewardedAd != null;
  static bool get isLoading => _isLoading;
  static bool get isShowing => _isShowing;

  static void preloadRewardedAd() {
    if (_rewardedAd != null || _isLoading || _isShowing) {
      return;
    }

    _isLoading = true;

    debugPrint('RewardedAdService: loading rewarded ad');

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _isLoading = false;
          _rewardedAd?.dispose();
          _rewardedAd = ad;
          debugPrint('RewardedAdService: ad loaded');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _rewardedAd = null;
          debugPrint('RewardedAdService: load failed: $error');
        },
      ),
    );
  }

  /// Shows a rewarded ad and grants +5 credits ONLY after AdMob fires
  /// onUserEarnedReward and the backend accepts the reward.
  ///
  /// Returns true only when the backend confirms the credits were granted.
  static Future<bool> showRewardedAd({
    VoidCallback? onAdPreparing,
    VoidCallback? onAdNotReady,
    void Function(int credits)? onRewardGranted,
    void Function(Object error)? onRewardFailed,
  }) async {
    if (_isShowing) {
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
      debugPrint('RewardedAdService: ad not ready');
      onAdNotReady?.call();
      return false;
    }

    _rewardedAd = null;
    _isShowing = true;

    final result = Completer<bool>();
    bool rewardCallbackReceived = false;

    final rewardId =
        '${DateTime.now().microsecondsSinceEpoch}_${FirebaseAuth.instance.currentUser?.uid ?? 'unknown'}';

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
          'RewardedAdService: ad dismissed | rewardCallback=$rewardCallbackReceived',
        );

        // No earned-reward callback means NO credits.
        if (!rewardCallbackReceived) {
          completeResult(false);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;
        ad.dispose();
        preloadRewardedAd();
        debugPrint('RewardedAdService: show failed: $error');
        completeResult(false);
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        if (rewardCallbackReceived) {
          return;
        }

        rewardCallbackReceived = true;

        debugPrint(
          'RewardedAdService: ADMOB REWARD EARNED '
          '${reward.amount} ${reward.type}',
        );

        try {
          final granted = await _grantBackendReward(
            rewardId: rewardId,
          );

          if (granted) {
            onRewardGranted?.call(5);
          }

          completeResult(granted);
        } catch (error) {
          debugPrint('RewardedAdService: backend reward failed: $error');
          onRewardFailed?.call(error);
          completeResult(false);
        }
      },
    );

    // Safety timeout: never leave the caller waiting forever.
    return result.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => false,
    );
  }

  static Future<bool> _grantBackendReward({
    required String rewardId,
  }) async {
    if (_baseUrl.trim().isEmpty) {
      throw StateError(
        'GENERATION_API_BASE_URL is not configured.',
      );
    }

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
          body: {
            'rewardId': rewardId,
          },
        )
        .timeout(const Duration(seconds: 20));

    debugPrint(
      'RewardedAdService: reward API ${response.statusCode} ${response.body}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Reward API failed with HTTP ${response.statusCode}.',
      );
    }

    return true;
  }

  static void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoading = false;
    _isShowing = false;
  }
}
