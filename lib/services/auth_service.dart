import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';
import 'api_config.dart';
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

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('AuthService: Email auth stage=sign_in');
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      debugPrint('AuthService: Email auth stage=sign_in result=success');
      return result;
    } on FirebaseAuthException catch (error) {
      debugPrint('AuthService: Email auth stage=sign_in code=${error.code}');
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Email auth stage=sign_in errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  /// Creates an email account or links it to the current Firebase user.
  /// Linking preserves the existing anonymous/Google UID and its backend data.
  Future<UserCredential> createEmailAccount({
    required String email,
    required String password,
  }) async {
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    try {
      debugPrint('AuthService: Email auth stage=create_or_link');
      final existingUser = _firebaseAuth.currentUser;
      final result = existingUser == null
          ? await _firebaseAuth.createUserWithEmailAndPassword(
              email: email.trim(),
              password: password,
            )
          : await existingUser.linkWithCredential(credential);
      debugPrint('AuthService: Email auth stage=create_or_link result=success');
      return result;
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'AuthService: Email auth stage=create_or_link code=${error.code}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Email auth stage=create_or_link '
        'errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      debugPrint('AuthService: Email auth stage=password_reset');
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      debugPrint('AuthService: Email auth stage=password_reset result=sent');
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'AuthService: Email auth stage=password_reset code=${error.code}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Email auth stage=password_reset '
        'errorType=${error.runtimeType}',
      );
      rethrow;
    }
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

      if (firebaseUser != null) {
        try {
          // Preserve the current Firebase UID for both guest upgrades and
          // authenticated accounts that add Google as another sign-in method.
          return await firebaseUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (error) {
          // Preserve the prior recovery behavior when Google already belongs
          // to another Firebase user. Do not silently switch a signed-in
          // account and risk attaching credits to a different UID.
          if (firebaseUser.isAnonymous &&
              (error.code == 'credential-already-in-use' ||
                  error.code == 'provider-already-linked')) {
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

  Future<UserCredential> signInWithApple() async {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    final rawNonce = List.generate(
      32,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    try {
      debugPrint('AuthService: Apple Sign-In stage=authorize');
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );
      final idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Apple Sign-In did not return an identity token.');
      }
      final credential = OAuthProvider(
        'apple.com',
      ).credential(idToken: idToken, rawNonce: rawNonce);
      final user = _firebaseAuth.currentUser;
      debugPrint(
        'AuthService: Apple Sign-In stage=${user == null ? 'sign_in' : 'link'}',
      );
      if (user != null) return await user.linkWithCredential(credential);
      return await _firebaseAuth.signInWithCredential(credential);
    } on SignInWithAppleAuthorizationException catch (error) {
      debugPrint(
        'AuthService: Apple Sign-In stage=authorize code=${error.code.name}',
      );
      rethrow;
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'AuthService: Apple Sign-In stage=firebase code=${error.code}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        'AuthService: Apple Sign-In stage=authorize '
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

  Future<void> deleteAccountAndData() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw StateError('No signed-in account is available.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Your secure session expired. Please sign in again.');
    }
    final response = await http
        .delete(
          Uri.parse('$generationApiBaseUrl/v1/account'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw StateError('Account deletion could not be completed.');
    }
    await _firebaseAuth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // The Firebase account and user data are already deleted.
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
