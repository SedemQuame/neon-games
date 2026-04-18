import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  FirebaseAuthService() : _auth = FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<String> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    return _signInWithProvider(provider);
  }

  Future<String> signInWithApple() {
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    return _signInWithProvider(provider);
  }

  Future<String> signInWithX() {
    final provider = TwitterAuthProvider();
    return _signInWithProvider(provider);
  }

  Future<String> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return _extractIdToken(credential);
  }

  Future<void> signOut() {
    return _auth.signOut();
  }

  Future<String> _signInWithProvider(AuthProvider provider) async {
    final UserCredential credential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);
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
