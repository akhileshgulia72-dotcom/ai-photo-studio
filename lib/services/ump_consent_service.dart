import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Owns the UMP flow and the gate shared by every AdMob format.
///
/// Configure the GDPR consent message in AdMob for the EEA, UK, and
/// Switzerland. UMP decides from its current region/message settings whether
/// a consent form is required; this app never overrides the user's geography.
class UmpConsentService extends ChangeNotifier {
  UmpConsentService._();

  static final UmpConsentService instance = UmpConsentService._();

  Future<bool>? _initialization;
  Future<void>? _adsInitialization;
  bool _canRequestAds = false;
  bool _adsSdkInitialized = false;
  PrivacyOptionsRequirementStatus _privacyOptionsStatus =
      PrivacyOptionsRequirementStatus.unknown;

  bool get adsAllowed => _canRequestAds;
  bool get privacyOptionsRequired =>
      _privacyOptionsStatus == PrivacyOptionsRequirementStatus.required;

  /// Request fresh consent information on each app launch, show only forms
  /// required by UMP, then initialize Google Mobile Ads when permitted.
  Future<bool> initialize() => _initialization ??= _updateConsent();

  Future<bool> canRequestAds() async {
    await initialize();
    return _canRequestAds && _adsSdkInitialized;
  }

  Future<bool> _updateConsent() async {
    final flowFinished = Completer<void>();
    final infoFinished = Completer<void>();

    void finishFlow([FormError? error]) {
      if (error != null) {
        debugPrint(
          'UMP: consent form error ${error.errorCode}: ${error.message}',
        );
      }
      if (flowFinished.isCompleted) {
        // The consent-info request can complete after its startup timeout.
        // Re-read the eventual UMP decision so the gate can open safely.
        unawaited(_refreshPermissionAndInitializeAds());
      } else {
        flowFinished.complete();
      }
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!infoFinished.isCompleted) infoFinished.complete();
          unawaited(
            ConsentForm.loadAndShowConsentFormIfRequired(finishFlow).catchError(
              (Object error) {
                debugPrint('UMP: could not present consent form: $error');
                finishFlow();
              },
            ),
          );
        },
        (FormError error) {
          debugPrint(
            'UMP: consent info update failed ${error.errorCode}: ${error.message}',
          );
          if (!infoFinished.isCompleted) infoFinished.complete();
          finishFlow();
        },
      );
    } catch (error) {
      debugPrint('UMP: consent info request could not start: $error');
      infoFinished.complete();
      finishFlow();
    }

    // Do not hold the app startup screen indefinitely if consent servers are
    // unreachable. The cached UMP decision can still allow ads; otherwise the
    // gate remains closed until a later successful update.
    try {
      await infoFinished.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      debugPrint('UMP: consent info update timed out; using cached decision');
      finishFlow();
    }
    await flowFinished.future;
    await _refreshPermissionAndInitializeAds();
    return _canRequestAds;
  }

  Future<void> _refreshPermissionAndInitializeAds() async {
    var allowed = false;
    var optionsStatus = PrivacyOptionsRequirementStatus.unknown;
    try {
      allowed = await ConsentInformation.instance.canRequestAds();
      optionsStatus = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
    } catch (error) {
      debugPrint('UMP: could not read consent status: $error');
    }

    final changed =
        allowed != _canRequestAds || optionsStatus != _privacyOptionsStatus;
    _canRequestAds = allowed;
    _privacyOptionsStatus = optionsStatus;

    if (_canRequestAds && !_adsSdkInitialized) {
      _adsInitialization ??= MobileAds.instance.initialize().then<void>((_) {
        _adsSdkInitialized = true;
      });
      try {
        await _adsInitialization;
      } catch (error) {
        _adsInitialization = null;
        debugPrint('AdMob: SDK initialization failed: $error');
      }
    }
    if (changed) notifyListeners();
  }

  /// Present the publisher's privacy options form when UMP says it is needed.
  /// Returns false in regions where no privacy options form is required.
  Future<bool> showPrivacyOptionsForm() async {
    await initialize();
    if (!privacyOptionsRequired) return false;

    final completed = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) {
        debugPrint(
          'UMP: privacy options error ${error.errorCode}: ${error.message}',
        );
      }
      if (!completed.isCompleted) completed.complete();
    });
    await completed.future;
    await _refreshPermissionAndInitializeAds();
    return true;
  }
}
