import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class FirebaseAuthService {
  FirebaseAuthService() : _auth = FirebaseAuth.instance {
    if (!kIsWeb) {
      GoogleSignIn.instance.initialize();
    }
  }

  final FirebaseAuth _auth;

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  Future<String> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
      return _signInWithProvider(provider);
    } else {
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        throw StateError('Google Sign-In cancelled by user.');
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return _extractIdToken(userCredential);
    }
  }

  Future<String> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No user is currently signed in to link.');
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
      return _linkWithProvider(provider);
    } else {
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        throw StateError('Google Sign-In cancelled by user.');
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await user.linkWithCredential(credential);
      return _extractIdToken(userCredential);
    }
  }

  Future<String> signInWithApple() async {
    if (kIsWeb) {
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
      return _signInWithProvider(provider);
    } else {
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider provider = OAuthProvider('apple.com');
      final AuthCredential credential = provider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return _extractIdToken(userCredential);
    }
  }

  Future<String> linkWithApple() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No user is currently signed in to link.');
    if (kIsWeb) {
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
      return _linkWithProvider(provider);
    } else {
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider provider = OAuthProvider('apple.com');
      final AuthCredential credential = provider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final UserCredential userCredential = await user.linkWithCredential(credential);
      return _extractIdToken(userCredential);
    }
  }

  Future<String> signInWithX() {
    final provider = TwitterAuthProvider();
    return _signInWithProvider(provider);
  }

  Future<String> signInAnonymously({String? displayName}) async {
    final credential = await _auth.signInAnonymously();
    if (displayName != null && displayName.trim().isNotEmpty) {
      await credential.user?.updateDisplayName(displayName.trim());
      await credential.user?.reload();
    }
    return _extractIdToken(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    return _auth.signOut();
  }

  Future<String> _signInWithProvider(AuthProvider provider) async {
    final UserCredential credential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);
    return _extractIdToken(credential);
  }

  Future<String> _linkWithProvider(AuthProvider provider) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No user is currently signed in to link.');
    final UserCredential credential = kIsWeb
        ? await user.linkWithPopup(provider)
        : await user.linkWithProvider(provider);
    return _extractIdToken(credential);
  }

  Future<String> _extractIdToken(UserCredential credential) async {
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase authentication completed without a user.');
    }
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Firebase authentication did not return an ID token.');
    }
    return idToken;
  }
}
