import 'package:ai_photo_studio/services/email_auth_validation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email validation', () {
    test('accepts a valid address and rejects malformed addresses', () {
      expect(EmailAuthValidation.email(' person@example.com '), isNull);
      expect(EmailAuthValidation.email('not-an-email'), isNotNull);
      expect(EmailAuthValidation.email(''), isNotNull);
    });
  });

  group('password validation', () {
    test('registration requires eight characters and a number', () {
      expect(
        EmailAuthValidation.password('short', forRegistration: true),
        isNotNull,
      );
      expect(
        EmailAuthValidation.password('longpassword', forRegistration: true),
        isNotNull,
      );
      expect(
        EmailAuthValidation.password('longpass1', forRegistration: true),
        isNull,
      );
    });

    test('login leaves password policy enforcement to Firebase', () {
      expect(
        EmailAuthValidation.password('abc', forRegistration: false),
        isNull,
      );
    });

    test('registration confirmation must match', () {
      expect(EmailAuthValidation.confirmation('same1234', 'same1234'), isNull);
      expect(
        EmailAuthValidation.confirmation('different', 'same1234'),
        isNotNull,
      );
    });
  });

  group('Firebase authentication errors', () {
    test('maps common error codes to useful safe messages', () {
      expect(
        EmailAuthValidation.messageForError(
          FirebaseAuthException(code: 'invalid-credential'),
        ),
        'Email or password is incorrect.',
      );
      expect(
        EmailAuthValidation.messageForError(
          FirebaseAuthException(code: 'email-already-in-use'),
        ),
        contains('credits are kept separate'),
      );
      expect(
        EmailAuthValidation.messageForError(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        contains('internet connection'),
      );
      expect(
        EmailAuthValidation.messageForError(
          FirebaseAuthException(code: 'operation-not-allowed'),
        ),
        contains('not enabled'),
      );
    });
  });
}
