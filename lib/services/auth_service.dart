import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

    await _googleSignIn.initialize();
    _initialized = true;
  }

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isGuest => currentUser?.isAnonymous ?? false;

  Future<User> continueAsGuest() async {
    final existing = currentUser;
    if (existing != null) return existing;
    final result = await _firebaseAuth.signInAnonymously();
    final user = result.user;
    if (user == null) throw StateError('Guest authentication failed.');
    return user;
  }

  Future<UserCredential> signInWithGoogle() async {
    await initialize();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw StateError('Google Sign-In is not supported on this platform.');
    }

    final googleUser = await _googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;

    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google Sign-In did not return an ID token.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final firebaseUser = _firebaseAuth.currentUser;

    if (firebaseUser != null && firebaseUser.isAnonymous) {
      try {
        // Preserve the anonymous Firebase UID whenever possible.
        return await firebaseUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (error) {
        // The Google account may already belong to another Firebase user.
        // In that case sign into the existing account rather than silently
        // creating a third account.
        if (error.code == 'credential-already-in-use' ||
            error.code == 'provider-already-linked') {
          return _firebaseAuth.signInWithCredential(credential);
        }
        rethrow;
      }
    }

    return _firebaseAuth.signInWithCredential(credential);
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
