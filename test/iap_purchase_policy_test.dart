import 'package:ai_photo_studio/services/iap_purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Apple credit packs', () {
    test('maps the requested Apple SKUs to the correct credits', () {
      expect(
        IapPurchaseService.creatorProductIdFor(apple: true),
        'com.agdevelops.vyro.credits250',
      );
      expect(
        IapPurchaseService.proProductIdFor(apple: true),
        'com.agdevelops.vyro.credits800',
      );
      expect(IapPurchaseService.creatorCreditsFor(apple: true), 250);
      expect(IapPurchaseService.proCreditsFor(apple: true), 800);
    });

    test('binds the Apple account token to a stable UUID', () {
      final token = IapPurchaseService.appleAccountToken('test-user');
      expect(token, '75a1e99e-8c2b-569e-abb4-15ed2093444f');
      expect(token, IapPurchaseService.appleAccountToken('test-user'));
      expect(token, isNot(IapPurchaseService.appleAccountToken('other-user')));
    });
  });

  group('Google Play compatibility', () {
    test('preserves existing product IDs and credit grants', () {
      expect(
        IapPurchaseService.creatorProductIdFor(apple: false),
        'vyro_creator_150',
      );
      expect(IapPurchaseService.proProductIdFor(apple: false), 'vyro_pro_500');
      expect(IapPurchaseService.creatorCreditsFor(apple: false), 150);
      expect(IapPurchaseService.proCreditsFor(apple: false), 500);
    });
  });
}
