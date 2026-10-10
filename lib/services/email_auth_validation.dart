import 'package:firebase_auth/firebase_auth.dart';

abstract final class EmailAuthValidation {
  static String? email(String? value) {
    final address = value?.trim() ?? '';
    if (address.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String? value, {required bool forRegistration}) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (forRegistration && password.length < 8) {
      return 'Use at least 8 characters.';
    }
    if (forRegistration && !RegExp(r'\d').hasMatch(password)) {
      return 'Add at least one number.';
    }
    return null;
  }

  static String? confirmation(String? value, String password) =>
      value == password ? null : 'Passwords do not match.';

  static String messageForError(Object error) {
    if (error is! FirebaseAuthException) {
      return 'Could not connect. Check your internet and try again.';
    }
    switch (error.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'This email belongs to another account. Sign in to that account; its credits are kept separate.';
      case 'weak-password':
        return 'Choose a stronger password with at least 8 characters and one number.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a little, then try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled for this app yet.';
      case 'user-disabled':
        return 'This account is disabled. Contact support for help.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
