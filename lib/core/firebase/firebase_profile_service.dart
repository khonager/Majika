import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/firebase/firebase_bootstrap.dart';
import 'package:majika/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAuthUser {
  final String uid;
  final String email;
  final String? displayName;

  const AppAuthUser({required this.uid, required this.email, this.displayName});

  factory AppAuthUser.fromFirebaseUser(User user) {
    return AppAuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
    );
  }

  String get fallbackDisplayName {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    if (email.isNotEmpty) return email.split('@').first;
    return 'Majika user';
  }
}

class AppUserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? steamProfile;
  final String? huggingFaceToken;
  final DateTime? updatedAt;

  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.steamProfile,
    this.huggingFaceToken,
    this.updatedAt,
  });

  factory AppUserProfile.fromAuthUser(
    AppAuthUser user,
    Map<String, dynamic>? json,
  ) {
    final displayName = json?['displayName']?.toString().trim();
    final updatedAt = json?['updatedAt'];
    return AppUserProfile(
      uid: user.uid,
      email: user.email,
      displayName: displayName == null || displayName.isEmpty
          ? user.fallbackDisplayName
          : displayName,
      steamProfile: json?['linkedAccounts'] is Map
          ? (json!['linkedAccounts'] as Map)['steam']?.toString()
          : null,
      huggingFaceToken: json?['tokens'] is Map
          ? (json!['tokens'] as Map)['huggingFace']?.toString()
          : null,
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : updatedAt is DateTime
          ? updatedAt
          : null,
    );
  }
}

class FirebaseProfileService {
  const FirebaseProfileService();

  static final _restClient = _FirebaseRestProfileClient();

  bool get _useRest => FirebaseBootstrap.useRestFallback;

  bool get isConfigured => _useRest || FirebaseBootstrap.isConfigured;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<AppAuthUser?> authStateChanges() {
    if (_useRest) return _restClient.authStateChanges();
    if (!isConfigured) return Stream<AppAuthUser?>.value(null);
    return _auth.authStateChanges().map(
      (user) => user == null ? null : AppAuthUser.fromFirebaseUser(user),
    );
  }

  Future<AppUserProfile?> fetchProfile() async {
    if (_useRest) return _restClient.fetchProfile();
    if (!isConfigured) return null;
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    final user = AppAuthUser.fromFirebaseUser(firebaseUser);
    final doc = await _profileDoc(user.uid).get();
    return AppUserProfile.fromAuthUser(user, doc.data());
  }

  Future<void> signIn({required String email, required String password}) async {
    if (_useRest) {
      await _restClient.signIn(email: email, password: password);
      return;
    }
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (_useRest) {
      await _restClient.createAccount(
        email: email,
        password: password,
        displayName: displayName,
      );
      return;
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(displayName.trim());
      await saveProfile(displayName: displayName);
    }
  }

  Future<void> saveProfile({
    required String displayName,
    String? steamProfile,
  }) async {
    if (_useRest) {
      await _restClient.saveProfile(
        displayName: displayName,
        steamProfile: steamProfile,
      );
      return;
    }

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

  Future<bool> saveHuggingFaceTokenIfSignedIn(String token) async {
    final trimmed = token.trim();
    if (_useRest) {
      return _restClient.saveHuggingFaceTokenIfSignedIn(trimmed);
    }
    if (!isConfigured) return false;
    final user = _auth.currentUser;
    if (user == null) return false;

    await _profileDoc(user.uid).set({
      'tokens': {'huggingFace': trimmed},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<void> signOut() async {
    if (_useRest) {
      await _restClient.signOut();
      return;
    }
    await _auth.signOut();
  }

  Future<String?> currentIdToken() async {
    if (_useRest) return _restClient.currentIdToken();
    if (!FirebaseBootstrap.isConfigured) return null;
    return _auth.currentUser?.getIdToken();
  }

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) {
    return _db.collection('users').doc(uid);
  }
}

class _FirebaseRestProfileClient {
  static const _sessionKey = 'firebase.restSession';

  final _authController = StreamController<AppAuthUser?>.broadcast();
  _RestSession? _session;
  bool _loaded = false;

  Stream<AppAuthUser?> authStateChanges() {
    _ensureLoaded();
    return _authController.stream;
  }

  Future<AppUserProfile?> fetchProfile() async {
    final session = await _requireSessionOrNull();
    if (session == null) return null;

    final uri = _firestoreDocumentUri(session.uid);
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${await currentIdToken()}'},
    );
    if (response.statusCode == 404) {
      return AppUserProfile.fromAuthUser(session.user, null);
    }
    _throwForFirebaseError(response);

    return AppUserProfile.fromAuthUser(
      session.user,
      _decodeFirestoreFields(jsonDecode(response.body)['fields']),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    final decoded = await _identityPost('accounts:signInWithPassword', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    await _saveSession(_RestSession.fromIdentityResponse(decoded));
  }

  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final decoded = await _identityPost('accounts:signUp', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    final session = _RestSession.fromIdentityResponse(
      decoded,
      displayName: displayName.trim(),
    );
    await _saveSession(session);
    await saveProfile(displayName: displayName);
  }

  Future<void> saveProfile({
    required String displayName,
    String? steamProfile,
  }) async {
    final session = await _requireSession();
    final now = DateTime.now().toUtc();
    final trimmedSteam = steamProfile?.trim();
    final fields = {
      'email': _firestoreString(session.email),
      'displayName': _firestoreString(displayName.trim()),
      'linkedAccounts': {
        'mapValue': {
          'fields': {
            if (trimmedSteam != null && trimmedSteam.isNotEmpty)
              'steam': _firestoreString(trimmedSteam),
          },
        },
      },
      'updatedAt': {'timestampValue': now.toIso8601String()},
    };

    final response = await http.patch(
      _firestoreDocumentUri(session.uid),
      headers: {
        'Authorization': 'Bearer ${await currentIdToken()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': fields}),
    );
    _throwForFirebaseError(response);

    await _saveSession(
      session.copyWith(displayName: displayName.trim(), idToken: _sessionToken),
    );
  }

  Future<bool> saveHuggingFaceTokenIfSignedIn(String token) async {
    final session = await _requireSessionOrNull();
    if (session == null) return false;
    final now = DateTime.now().toUtc();
    final fields = {
      'tokens': {
        'mapValue': {
          'fields': {'huggingFace': _firestoreString(token)},
        },
      },
      'updatedAt': {'timestampValue': now.toIso8601String()},
    };

    final response = await http.patch(
      _firestoreDocumentUri(session.uid),
      headers: {
        'Authorization': 'Bearer ${await currentIdToken()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': fields}),
    );
    _throwForFirebaseError(response);
    return true;
  }

  Future<void> signOut() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _authController.add(null);
  }

  Future<String?> currentIdToken() async {
    var session = await _requireSessionOrNull();
    if (session == null) return null;
    if (!session.needsRefresh) return session.idToken;

    final response = await http.post(
      Uri.https('securetoken.googleapis.com', '/v1/token', {
        'key': DefaultFirebaseOptions.linux.apiKey,
      }),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': session.refreshToken,
      },
    );
    _throwForFirebaseError(response);
    final decoded = jsonDecode(response.body);
    session = session.copyWith(
      idToken: decoded['id_token']?.toString(),
      refreshToken: decoded['refresh_token']?.toString(),
      expiresAt: _expiresAt(decoded['expires_in']),
    );
    await _saveSession(session);
    return session.idToken;
  }

  String get _sessionToken {
    final token = _session?.idToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sign in before saving your profile.');
    }
    return token;
  }

  Future<_RestSession> _requireSession() async {
    final session = await _requireSessionOrNull();
    if (session == null) {
      throw StateError('Sign in before saving your profile.');
    }
    return session;
  }

  Future<_RestSession?> _requireSessionOrNull() async {
    await _ensureLoaded();
    return _session;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      _session = _RestSession.fromJson(jsonDecode(raw));
    }
    _authController.add(_session?.user);
  }

  Future<void> _saveSession(_RestSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    _authController.add(session.user);
  }

  Future<Map<String, dynamic>> _identityPost(
    String method,
    Map<String, Object?> body,
  ) async {
    final response = await http.post(
      Uri.https('identitytoolkit.googleapis.com', '/v1/$method', {
        'key': DefaultFirebaseOptions.linux.apiKey,
      }),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    _throwForFirebaseError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uri _firestoreDocumentUri(String uid) {
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/${DefaultFirebaseOptions.linux.projectId}/databases/(default)/documents/users/$uid',
    );
  }

  Map<String, dynamic> _decodeFirestoreFields(Object? fields) {
    if (fields is! Map) return const {};
    return {
      for (final entry in fields.entries)
        entry.key.toString(): _decodeFirestoreValue(entry.value),
    };
  }

  Object? _decodeFirestoreValue(Object? value) {
    if (value is! Map) return null;
    if (value['stringValue'] != null) return value['stringValue'].toString();
    if (value['timestampValue'] != null) {
      return DateTime.tryParse(value['timestampValue'].toString());
    }
    final mapValue = value['mapValue'];
    if (mapValue is Map) return _decodeFirestoreFields(mapValue['fields']);
    return null;
  }

  Map<String, String> _firestoreString(String value) {
    return {'stringValue': value};
  }

  void _throwForFirebaseError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw FirebaseRestException(message);
        }
      }
    } catch (error) {
      if (error is FirebaseRestException) rethrow;
    }
    throw FirebaseRestException(
      'Firebase returned HTTP ${response.statusCode}.',
    );
  }
}

class _RestSession {
  final String uid;
  final String email;
  final String? displayName;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  const _RestSession({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory _RestSession.fromIdentityResponse(
    Map<String, dynamic> json, {
    String? displayName,
  }) {
    return _RestSession(
      uid: json['localId']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: displayName ?? json['displayName']?.toString(),
      idToken: json['idToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      expiresAt: _expiresAt(json['expiresIn']),
    );
  }

  factory _RestSession.fromJson(Map<String, dynamic> json) {
    return _RestSession(
      uid: json['uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      idToken: json['idToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AppAuthUser get user {
    return AppAuthUser(uid: uid, email: email, displayName: displayName);
  }

  bool get needsRefresh {
    return DateTime.now().toUtc().isAfter(
      expiresAt.subtract(const Duration(minutes: 5)),
    );
  }

  _RestSession copyWith({
    String? displayName,
    String? idToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) {
    return _RestSession(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }
}

DateTime _expiresAt(Object? seconds) {
  final parsed = int.tryParse(seconds?.toString() ?? '') ?? 3600;
  return DateTime.now().toUtc().add(Duration(seconds: parsed));
}

class FirebaseRestException implements Exception {
  final String message;

  const FirebaseRestException(this.message);

  @override
  String toString() => message;
}
