import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Owns the UMP flow and the gate shared by every AdMob format.
///
/// Configure the GDPR consent message in AdMob for the EEA, UK, and
/// Switzerland. UMP decides from its current region/message settings whether
/// a consent form is required; this app never overrides the user's geography.
///
/// Two states are tracked separately and are frequently confused:
///
///   * [_canRequestAds] — UMP says requests are permitted. This is consent.
///   * [_adsSdkInitialized] — `MobileAds.initialize()` completed.
///
/// The SDK is initialised *regardless* of consent, because Google documents
/// that it may be initialised while the consent flow runs; it simply will not
/// request ads until consent allows. Gating initialisation behind consent
/// meant a transient `canRequestAds() == false` (for example the decision
/// arriving after the startup timeout) left the SDK uninitialised with no
/// retry path, and every later ad request silently did nothing.
class UmpConsentService extends ChangeNotifier {
  UmpConsentService._();

  static final UmpConsentService instance = UmpConsentService._();

  /// Consent flow runs at most once per process.
  Future<bool>? _initialization;

  /// SDK initialisation is attempted at most once at a time.
  Future<void>? _adsInitialization;

  bool _canRequestAds = false;
  bool _adsSdkInitialized = false;
  bool _sdkInitAttempted = false;
  int _sdkInitAttempts = 0;
  bool _disposed = false;

  /// Bounded retry for SDK initialisation.
  static const int _maxSdkInitAttempts = 3;
  static const List<Duration> _sdkRetryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  PrivacyOptionsRequirementStatus _privacyOptionsStatus =
      PrivacyOptionsRequirementStatus.unknown;

  bool get adsAllowed => _canRequestAds;

  /// True once `MobileAds.initialize()` has completed successfully.
  bool get sdkInitialized => _adsSdkInitialized;

  bool get privacyOptionsRequired =>
      _privacyOptionsStatus == PrivacyOptionsRequirementStatus.required;

  /// Request fresh consent information on each app launch and show a form
  /// only when UMP requires one. SDK startup runs independently of this flow.
  Future<bool> initialize() => _initialization ??= _updateConsent();

  /// The single gate every ad format must consult before requesting an ad.
  ///
  /// Waits for the consent flow to settle, then requires *both* that UMP
  /// permits requests and that the SDK finished initialising. If the SDK
  /// has not initialised yet it is kicked off here, so a caller that asks
  /// too early does not permanently lose its chance to load.
  Future<bool> canRequestAds() async {
    await initialize();
    if (_canRequestAds && !_adsSdkInitialized) {
      unawaited(_initializeAdsSdk());
    }
    return _canRequestAds && _adsSdkInitialized;
  }

  /// Waits until the SDK is ready or [timeout] elapses.
  ///
  /// Returns true when ads may be requested. Callers that can afford to wait
  /// (a preload, or a user-initiated rewarded ad) should use this instead of
  /// polling [canRequestAds].
  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    await initialize();

    while (!_disposed && DateTime.now().isBefore(deadline)) {
      if (_canRequestAds && _adsSdkInitialized) return true;

      // Consent is still unknown: a late decision may yet open the gate.
      if (_canRequestAds && !_adsSdkInitialized) {
        unawaited(_initializeAdsSdk());
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    return _canRequestAds && _adsSdkInitialized;
  }

  Future<bool> _updateConsent() async {
    // SDK initialization does not request ads. Start it while UMP refreshes
    // consent so a required form or slow consent server cannot delay it.
    unawaited(_initializeAdsSdk());

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
        debugPrint('UMP: late consent update received, re-reading decision');
        unawaited(_refreshPermission());
      } else {
        flowFinished.complete();
      }
    }

    debugPrint('UMP: requesting consent info update');

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          debugPrint('UMP: consent info update succeeded');
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
      if (!infoFinished.isCompleted) infoFinished.complete();
      finishFlow();
    }

    // Do not hold the app startup screen indefinitely if consent servers are
    // unreachable. The cached UMP decision can still allow ads; otherwise the
    // gate remains closed until a later successful update.
    try {
      await infoFinished.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      debugPrint(
        'UMP: consent info update timed out; using cached decision if any',
      );
      finishFlow();
    }

    await flowFinished.future;
    await _refreshPermission();

    // Do not call canRequestAds() here: it awaits initialize(), which is this
    // very future. Logging the independent state avoids a self-wait/deadlock.
    debugPrint(
      'UMP: consent flow finished; canRequestAds=$_canRequestAds '
      'sdkInitialized=$_adsSdkInitialized',
    );

    return _canRequestAds;
  }

  Future<void> _refreshPermission() async {
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

    debugPrint(
      'UMP: canRequestAds=$_canRequestAds '
      'privacyOptions=${optionsStatus.name} changed=$changed',
    );

    if (changed && !_disposed) notifyListeners();
  }

  /// Initialise the Google Mobile Ads SDK, with bounded retry.
  ///
  /// Never throws: a failure is recorded and retried, so a single transient
  /// error does not permanently prevent ads from loading.
  Future<void> _initializeAdsSdk() {
    if (_adsSdkInitialized) return Future<void>.value();
    return _adsInitialization ??= _runSdkInitialization();
  }

  Future<void> _runSdkInitialization() async {
    for (var attempt = 0; attempt < _maxSdkInitAttempts; attempt++) {
      if (_disposed) return;
      if (_adsSdkInitialized) return;

      _sdkInitAttempted = true;
      _sdkInitAttempts = attempt + 1;

      try {
        debugPrint('AdMob: initializing SDK (attempt ${attempt + 1})');
        final status = await MobileAds.instance.initialize();
        _adsSdkInitialized = true;

        final adapters = status.adapterStatuses.values
            .map((a) => '${a.description}:${a.state.name}')
            .join(', ');
        debugPrint(
          'AdMob: SDK initialized. adapters=[${adapters.isEmpty ? 'none' : adapters}]',
        );

        if (!_disposed) notifyListeners();
        return;
      } catch (error) {
        debugPrint(
          'AdMob: SDK initialization failed on attempt ${attempt + 1}: $error',
        );
      }

      if (attempt < _maxSdkInitAttempts - 1) {
        final delay =
            _sdkRetryDelays[attempt < _sdkRetryDelays.length
                ? attempt
                : _sdkRetryDelays.length - 1];
        debugPrint('AdMob: retrying SDK initialization in $delay');
        await Future<void>.delayed(delay);
      }
    }

    debugPrint(
      'AdMob: SDK initialization gave up after $_sdkInitAttempts attempt(s)',
    );

    // Allow a later call to try again rather than latching failure forever.
    _adsInitialization = null;
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
    await _refreshPermission();
    return true;
  }

  /// Diagnostic summary for startup logging.
  String describe() =>
      'UMP(canRequestAds: $_canRequestAds, sdkInitialized: $_adsSdkInitialized, '
      'sdkInitAttempted: $_sdkInitAttempted, sdkInitAttempts: $_sdkInitAttempts, '
      'privacyOptionsRequired: $privacyOptionsRequired)';

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
