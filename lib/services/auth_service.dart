import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import 'google_sign_in_config.dart';

/// Central authentication service for VYRO.
///
/// Guest users keep their anonymous Firebase UID. When they later choose
/// Google Sign-In, we link the Google credential to that same Firebase user
/// whenever possible so their credits and backend records stay attached.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _initialized = false;
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('AuthService: Google Sign-In stage=initialize');
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _googleSignIn.initialize(
          clientId: DefaultFirebaseOptions.ios.iosClientId,
          serverClientId: GoogleSignInConfig.serverClientId,
        );
      } else {
        // Keep Android's existing google-services.json based configuration.
        await _googleSignIn.initialize();
      }
      _initialized = true;
      debugPrint('AuthService: Google Sign-In stage=initialize result=ready');
    } on GoogleSignInException catch (error) {
      debugPrint(
        'AuthService: Google Sign-In stage=initialize '
        'code=${error.code.name}',
      );
      rethrow;
    } on PlatformException catch (error) {
      debugPrint(
        'AuthService: Google Sign-In stage=initialize code=${error.code}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Google Sign-In stage=initialize '
        'errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isGuest => currentUser?.isAnonymous ?? false;

  /// True when this platform can present a Google sign-in flow at all.
  bool get supportsGoogleSignIn => _googleSignIn.supportsAuthenticate();

  Future<User> continueAsGuest() async {
    final existing = currentUser;
    if (existing != null) return existing;
    final result = await _firebaseAuth.signInAnonymously();
    final user = result.user;
    if (user == null) throw StateError('Guest authentication failed.');
    return user;
  }

  Future<UserCredential> signInWithGoogle() async {
    var stage = 'initialize';
    try {
      await initialize();

      stage = 'availability_check';
      if (!_googleSignIn.supportsAuthenticate()) {
        throw StateError('Google Sign-In is not supported on this platform.');
      }

      stage = 'google_authenticate';
      debugPrint('AuthService: Google Sign-In stage=$stage');
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;

      stage = 'id_token_check';
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint(
          'AuthService: Google Sign-In stage=$stage code=missing_id_token',
        );
        throw StateError('Google Sign-In did not return an ID token.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final firebaseUser = _firebaseAuth.currentUser;
      stage = firebaseUser?.isAnonymous == true
          ? 'firebase_link_credential'
          : 'firebase_sign_in_credential';

      if (firebaseUser != null && firebaseUser.isAnonymous) {
        try {
          // Preserve the anonymous Firebase UID whenever possible.
          return await firebaseUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (error) {
          // Preserve the prior recovery behavior when Google already belongs
          // to another Firebase user.
          if (error.code == 'credential-already-in-use' ||
              error.code == 'provider-already-linked') {
            stage = 'firebase_sign_in_existing_credential';
            return await _firebaseAuth.signInWithCredential(credential);
          }
          rethrow;
        }
      }

      return await _firebaseAuth.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      // Do not log exception descriptions/details; they can contain user data.
      debugPrint(
        'AuthService: Google Sign-In stage=$stage code=${error.code.name}',
      );
      rethrow;
    } on FirebaseAuthException catch (error) {
      debugPrint('AuthService: Google Sign-In stage=$stage code=${error.code}');
      rethrow;
    } on PlatformException catch (error) {
      debugPrint('AuthService: Google Sign-In stage=$stage code=${error.code}');
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Google Sign-In stage=$stage '
        'errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase is already signed out; Google cache cleanup is best effort.
    }
  }

  Future<String> freshIdToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('Firebase user is not authenticated.');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Firebase ID token is unavailable.');
    }
    return token;
  }
}
