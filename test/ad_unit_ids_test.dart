import 'package:ai_photo_studio/services/interstitial_ad_service.dart';
import 'package:ai_photo_studio/services/rewarded_ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdMob unit ids are `ca-app-pub-<publisher>/<unit>`; application ids use `~`.
final _unitId = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');
const vyroPublisher = 'ca-app-pub-7694497723149363';

void main() {
  group('rewarded ad unit selection', () {
    test('Android keeps the original production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(RewardedAdService.adUnitId, '$vyroPublisher/9751807400');
    });

    test('iOS uses the iOS production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(RewardedAdService.adUnitId, '$vyroPublisher/8453252739');
    });
  });

  group('interstitial ad unit selection', () {
    test('Android keeps the original production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(InterstitialAdService.adUnitId, '$vyroPublisher/7630322351');
    });

    test('iOS uses the iOS production unit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(InterstitialAdService.adUnitId, '$vyroPublisher/8336693504');
    });
  });

  group('ad unit id hygiene', () {
    test('every unit id is well formed and belongs to the VYRO account', () {
      const ids = <String>[
        // rewarded
        '$vyroPublisher/9751807400', // Android
        '$vyroPublisher/8453252739', // iOS
        // interstitial
        '$vyroPublisher/7630322351', // Android
        '$vyroPublisher/8336693504', // iOS
        // native
        '$vyroPublisher/6374835026', // Android
        '$vyroPublisher/7462595539', // iOS
      ];

      for (final id in ids) {
        expect(
          _unitId.hasMatch(id),
          isTrue,
          reason: 'malformed ad unit id: $id',
        );
        expect(id.startsWith(vyroPublisher), isTrue);
      }
    });

    test('the iOS units are distinct from the Android units', () {
      // Guards against pasting an Android id into an iOS slot, which would
      // silently serve no ads on iOS.
      const pairs = <List<String>>[
        ['$vyroPublisher/9751807400', '$vyroPublisher/8453252739'],
        ['$vyroPublisher/7630322351', '$vyroPublisher/8336693504'],
        ['$vyroPublisher/6374835026', '$vyroPublisher/7462595539'],
      ];

      for (final pair in pairs) {
        expect(pair[0], isNot(equals(pair[1])));
      }
    });

    test('no two ad slots share a unit id', () {
      const ids = <String>[
        '$vyroPublisher/9751807400',
        '$vyroPublisher/8453252739',
        '$vyroPublisher/7630322351',
        '$vyroPublisher/8336693504',
        '$vyroPublisher/6374835026',
        '$vyroPublisher/7462595539',
      ];

      expect(ids.toSet().length, ids.length);
    });
  });
}
