import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/firebase/firebase_bootstrap.dart';
import 'package:majika/core/firebase/firebase_profile_service.dart';
import 'package:majika/core/services/steam_service.dart';
import 'package:majika/firebase_options.dart';

class FirebaseSteamProtectedApi implements SteamProtectedApi {
  FirebaseSteamProtectedApi({FirebaseFunctions? functions})
    : _functions = functions;

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _client =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  Future<Map<String, dynamic>> resolveVanityUrl(String vanity) {
    return _call('resolveVanityUrl', {'vanity': vanity});
  }

  @override
  Future<Map<String, dynamic>> getPlayerSummaries(String steamId) {
    return _call('getPlayerSummaries', {'steamId': steamId});
  }

  @override
  Future<Map<String, dynamic>> getOwnedGames(String steamId) {
    return _call('getOwnedGames', {'steamId': steamId});
  }

  @override
  Future<Map<String, dynamic>> getRecentlyPlayedGames(String steamId) {
    return _call('getRecentlyPlayedGames', {'steamId': steamId});
  }

  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, Object?> payload,
  ) async {
    if (FirebaseBootstrap.useRestFallback) {
      return _callRest(action, payload);
    }

    if (!FirebaseBootstrap.isConfigured) {
      throw const SteamException(
        'Firebase is not configured yet. Finish Firebase setup before importing Steam.',
      );
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw const SteamException(
        'Sign in on the Profile page before importing a Steam library.',
      );
    }

    final callable = _client.httpsCallable('steamApi');
    final result = await callable.call<Map<String, dynamic>>({
      'action': action,
      ...payload,
    });
    return _deepStringMap(result.data);
  }

  Future<Map<String, dynamic>> _callRest(
    String action,
    Map<String, Object?> payload,
  ) async {
    final idToken = await const FirebaseProfileService().currentIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const SteamException(
        'Sign in on the Profile page before importing a Steam library.',
      );
    }

    final response = await http.post(
      Uri.https(
        'us-central1-${DefaultFirebaseOptions.linux.projectId}.cloudfunctions.net',
        '/steamApi',
      ),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'data': {'action': action, ...payload},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamException(
        'Steam backend returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['error'] != null) {
      final error = decoded['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw SteamException(message ?? 'Steam backend rejected the request.');
    }
    final result = decoded is Map ? decoded['result'] : null;
    return _deepStringMap(result);
  }

  Map<String, dynamic> _deepStringMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.map((key, value) => MapEntry(key, _deepConvert(value)));
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _deepConvert(entry.value),
      };
    }
    throw const FormatException(
      'Steam backend response was not a JSON object.',
    );
  }

  Object? _deepConvert(Object? value) {
    if (value is Map) return _deepStringMap(value);
    if (value is List) return value.map(_deepConvert).toList();
    return value;
  }
}
