import 'package:ai_photo_studio/services/ad_unit_config.dart';
import 'package:ai_photo_studio/services/interstitial_ad_service.dart';
import 'package:ai_photo_studio/services/rewarded_ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdMob unit ids are `ca-app-pub-<publisher>/<unit>`; application ids use `~`.
final _unitId = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');
const vyroPublisher = 'ca-app-pub-7694497723149363';
const googleTestPublisher = 'ca-app-pub-3940256099942544';

void main() {
  group('ADMOB_USE_TEST_ADS default', () {
    test('test ads are OFF unless explicitly requested in debug mode', () {
      expect(
        AdUnitConfig.useTestAds,
        isFalse,
        reason: 'ADMOB_USE_TEST_ADS defaults to false',
      );
    });
  });

  group('production ids are unchanged', () {
    test('Android production ids', () {
      final ids = AdUnitConfig.productionIdsFor(
        platform: TargetPlatform.android,
      );
      expect(ids['rewarded'], '$vyroPublisher/9751807400');
      expect(ids['interstitial'], '$vyroPublisher/7630322351');
      expect(ids['native'], '$vyroPublisher/6374835026');
    });

    test('iOS production ids', () {
      final ids = AdUnitConfig.productionIdsFor(platform: TargetPlatform.iOS);
      expect(ids['rewarded'], '$vyroPublisher/8453252739');
      expect(ids['interstitial'], '$vyroPublisher/8336693504');
      expect(ids['native'], '$vyroPublisher/7462595539');
    });

    test('iOS and Android never share a production unit', () {
      for (final format in ['rewarded', 'interstitial', 'native']) {
        final android = AdUnitConfig.productionIdsFor(
          platform: TargetPlatform.android,
        )[format];
        final ios = AdUnitConfig.productionIdsFor(
          platform: TargetPlatform.iOS,
        )[format];
        expect(
          android,
          isNot(equals(ios)),
          reason: '$format must differ per platform',
        );
      }
    });
  });

  group('test ids', () {
    test('exist for every format Google publishes one for', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final ids = AdUnitConfig.testIdsFor(platform: platform);
        expect(ids['rewarded'], startsWith(googleTestPublisher));
        expect(ids['interstitial'], startsWith(googleTestPublisher));
        expect(ids['banner'], startsWith(googleTestPublisher));
      }
    });

    test('iOS native uses Google official demo unit', () {
      final ids = AdUnitConfig.testIdsFor(platform: TargetPlatform.iOS);
      expect(ids['native'], '$googleTestPublisher/3986624511');
    });

    test('Android and iOS test ids differ', () {
      final android = AdUnitConfig.testIdsFor(platform: TargetPlatform.android);
      final ios = AdUnitConfig.testIdsFor(platform: TargetPlatform.iOS);
      expect(android['rewarded'], isNot(equals(ios['rewarded'])));
      expect(android['interstitial'], isNot(equals(ios['interstitial'])));
      expect(android['banner'], isNot(equals(ios['banner'])));
      expect(android['native'], isNot(equals(ios['native'])));
    });

    test('no test id is ever a VYRO production id', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final id in AdUnitConfig.testIdsFor(platform: platform).values) {
          expect(
            id,
            isNot(startsWith(vyroPublisher)),
            reason: 'test id leaked a production publisher: $id',
          );
        }
      }
    });
  });

  group('services use AdUnitConfig as the single source of truth', () {
    test('rewarded service returns the configured production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(RewardedAdService.adUnitId, AdUnitConfig.rewarded);
      expect(RewardedAdService.adUnitId, '$vyroPublisher/8453252739');
    });

    test('interstitial service returns the configured production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(InterstitialAdService.adUnitId, AdUnitConfig.interstitial);
      expect(InterstitialAdService.adUnitId, '$vyroPublisher/8336693504');
    });

    test('native selector matches the iOS production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Test ads are off in this build, so native must be available and
      // equal to the shipped iOS unit.
      expect(AdUnitConfig.native, AdUnitConfig.productionNative);
      expect(AdUnitConfig.native, '$vyroPublisher/7462595539');
    });
  });

  group('ad unit id hygiene', () {
    test('every production id is well formed and belongs to VYRO', () {
      final ids = <String>[
        ...AdUnitConfig.productionIdsFor(
          platform: TargetPlatform.android,
        ).values,
        ...AdUnitConfig.productionIdsFor(platform: TargetPlatform.iOS).values,
      ];

      for (final id in ids) {
        expect(_unitId.hasMatch(id), isTrue, reason: 'malformed id: $id');
        expect(id.startsWith(vyroPublisher), isTrue);
      }
    });

    test('no two production slots share a unit id', () {
      final ids = <String>[
        ...AdUnitConfig.productionIdsFor(
          platform: TargetPlatform.android,
        ).values,
        ...AdUnitConfig.productionIdsFor(platform: TargetPlatform.iOS).values,
      ];

      expect(ids.toSet().length, ids.length);
    });
  });
}
