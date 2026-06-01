import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:majika/core/firebase/firebase_bootstrap.dart';

class AppUserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? steamProfile;
  final DateTime? updatedAt;

  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.steamProfile,
    this.updatedAt,
  });

  factory AppUserProfile.fromUser(User user, Map<String, dynamic>? json) {
    final displayName = json?['displayName']?.toString().trim();
    final updatedAt = json?['updatedAt'];
    return AppUserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName == null || displayName.isEmpty
          ? user.displayName ?? user.email?.split('@').first ?? 'Majika user'
          : displayName,
      steamProfile: json?['linkedAccounts'] is Map
          ? (json!['linkedAccounts'] as Map)['steam']?.toString()
          : null,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }
}

class FirebaseProfileService {
  const FirebaseProfileService();

  bool get isConfigured => FirebaseBootstrap.isConfigured;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<User?> authStateChanges() {
    if (!isConfigured) return Stream<User?>.value(null);
    return _auth.authStateChanges();
  }

  Future<AppUserProfile?> fetchProfile() async {
    if (!isConfigured) return null;
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _profileDoc(user.uid).get();
    return AppUserProfile.fromUser(user, doc.data());
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(displayName.trim());
      await saveProfile(displayName: displayName);
    }
    return credential;
  }

  Future<void> saveProfile({
    required String displayName,
    String? steamProfile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before saving your profile.');

    final trimmedSteam = steamProfile?.trim();
    await _profileDoc(user.uid).set({
      'email': user.email,
      'displayName': displayName.trim(),
      'linkedAccounts': {
        if (trimmedSteam != null && trimmedSteam.isNotEmpty)
          'steam': trimmedSteam,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (displayName.trim().isNotEmpty) {
      await user.updateDisplayName(displayName.trim());
    }
  }

  Future<void> signOut() => _auth.signOut();

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) {
    return _db.collection('users').doc(uid);
  }
}
