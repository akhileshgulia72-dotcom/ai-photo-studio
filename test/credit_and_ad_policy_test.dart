import 'package:flutter_test/flutter_test.dart';
import 'package:ai_photo_studio/services/account_profile_service.dart';
import 'package:ai_photo_studio/services/image_generation_service.dart';
import 'package:ai_photo_studio/services/interstitial_ad_service.dart';

void main() {
  group('template card interstitial policy', () {
    test('fires on every third card selection and resets each cycle', () {
      final counter = TemplateClickCounter();
      for (var cycle = 0; cycle < 4; cycle++) {
        for (var click = 1; click <= 3; click++) {
          expect(
            counter.recordSelection(),
            click == 3,
            reason: 'cycle $cycle click $click',
          );
        }
        expect(counter.count, 0);
      }
    });

    test('counter remains on the same object across UI rebuilds', () {
      final counter = TemplateClickCounter();
      for (var i = 0; i < 2; i++) {
        expect(counter.recordSelection(), isFalse);
      }
      // Rebuilding a widget does not construct/reset the service-owned counter.
      expect(counter.recordSelection(), isTrue);
    });
  });

  group('screen transition interstitial policy', () {
    test('fires on every third navigation and resets each cycle', () {
      final counter = ScreenTransitionCounter();
      for (var cycle = 0; cycle < 4; cycle++) {
        expect(counter.recordTransition(), isFalse);
        expect(counter.recordTransition(), isFalse);
        expect(counter.recordTransition(), isTrue);
        expect(counter.count, 0);
      }
    });

    test('template taps and screen moves keep independent counts', () {
      final clicks = TemplateClickCounter();
      final transitions = ScreenTransitionCounter();

      // Two template taps must not advance the navigation cadence.
      expect(clicks.recordSelection(), isFalse);
      expect(clicks.recordSelection(), isFalse);
      expect(transitions.count, 0);

      // So the very next screen move is still only the first of its cycle.
      expect(transitions.recordTransition(), isFalse);
      expect(transitions.recordTransition(), isFalse);
      expect(transitions.recordTransition(), isTrue);
    });

    test('the third transition is the only eligible one in its cycle', () {
      final counter = ScreenTransitionCounter();
      final due = <int>[];
      for (var i = 1; i <= 9; i++) {
        if (counter.recordTransition()) due.add(i);
      }
      expect(due, [3, 6, 9]);
    });
  });

  group('backend profile policy', () {
    test('profile mapper keeps the backend balance authoritative', () {
      final profile = AccountProfile.fromJson({
        'credits': 5,
        'plan': 'free',
        'totalGenerations': 0,
      });
      expect(profile.credits, 5);
      expect(profile.plan, 'free');
      expect(profile.isAdFree, isFalse);
    });

    test('Creator, Pro, and Premium are ad-free', () {
      expect(
        AccountProfile.fromJson({'credits': 0, 'plan': 'pro'}).isAdFree,
        isTrue,
      );
      expect(
        AccountProfile.fromJson({'credits': 0, 'plan': 'premium'}).isAdFree,
        isTrue,
      );
      expect(
        AccountProfile.fromJson({'credits': 0, 'plan': 'creator'}).isAdFree,
        isTrue,
      );
    });
  });

  test('HTTP 402 can be distinguished for in-place credit continuation', () {
    expect(
      GenerationException('low', insufficientCredits: true).insufficientCredits,
      isTrue,
    );
  });
}
