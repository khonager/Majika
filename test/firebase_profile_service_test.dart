import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/firebase/firebase_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each account subscription receives the restored session', () async {
    _session();
    final service = FirebaseProfileService.rest(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect((await service.authStateChanges().first)?.uid, 'test-user');
    expect((await service.authStateChanges().first)?.uid, 'test-user');
    expect(await service.currentIdToken(), 'test-token');
    await service.signOut();
    expect(await service.authStateChanges().first, isNull);
  });

  test('corrupt saved authentication falls back to signed out', () async {
    SharedPreferences.setMockInitialValues({
      'firebase.restSession': '{damaged',
    });
    final service = FirebaseProfileService.rest(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(await service.authStateChanges().first, isNull);
    expect(await service.currentIdToken(), isNull);
  });

  test('REST profile updates preserve unrelated cloud fields', () async {
    _session();
    final requests = <http.Request>[];
    final fields = <String, dynamic>{
      'displayName': {'stringValue': 'Tester'},
      'linkedAccounts': {
        'mapValue': {
          'fields': {
            'steam': {'stringValue': 'steamtester'},
          },
        },
      },
      'cloudApiKeysJson': {'stringValue': '{"provider":"existing-key"}'},
      'tokens': {
        'mapValue': {
          'fields': {
            'huggingFace': {'stringValue': 'existing-token'},
          },
        },
      },
    };
    final service = FirebaseProfileService.rest(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          requests.add(request);
          final mask = request.url.queryParametersAll['updateMask.fieldPaths'];
          expect(
            mask,
            isNotEmpty,
            reason: 'Unmasked PATCH replaces the document.',
          );
          final updates = jsonDecode(request.body)['fields'] as Map;
          for (final name in mask!) {
            fields[name] = updates[name];
          }
        }
        return http.Response(jsonEncode({'fields': fields}), 200);
      }),
    );
    await service.saveProfile(displayName: 'New name');
    var profile = await service.fetchProfile();
    expect(profile!.displayName, 'New name');
    expect(profile.steamProfile, 'steamtester');
    expect(profile.huggingFaceToken, 'existing-token');
    expect(profile.cloudApiKeys['provider'], 'existing-key');
    await service.saveHuggingFaceTokenIfSignedIn('new-token');
    await service.saveCloudApiKeysIfSignedIn({'provider': 'new-key'});
    profile = await service.fetchProfile();
    expect(profile!.displayName, 'New name');
    expect(profile.steamProfile, 'steamtester');
    expect(profile.huggingFaceToken, 'new-token');
    expect(profile.cloudApiKeys['provider'], 'new-key');
    expect(requests, hasLength(3));
  });

  test('concurrent expired-token requests share one refresh', () async {
    _session(expired: true);
    var refreshes = 0;
    final service = FirebaseProfileService.rest(
      client: MockClient((request) async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response(
          jsonEncode({
            'id_token': 'refreshed',
            'refresh_token': 'next-refresh',
            'expires_in': '3600',
          }),
          200,
        );
      }),
    );
    final tokens = await Future.wait([
      service.currentIdToken(),
      service.currentIdToken(),
      service.currentIdToken(),
    ]);
    expect(tokens, everyElement('refreshed'));
    expect(refreshes, 1);
  });

  test('a late token refresh cannot sign the user back in', () async {
    _session(expired: true);
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final service = FirebaseProfileService.rest(
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final pending = service.currentIdToken();
    await started.future;
    await service.signOut();
    response.complete(
      http.Response(
        jsonEncode({
          'id_token': 'late',
          'refresh_token': 'late-refresh',
          'expires_in': '3600',
        }),
        200,
      ),
    );
    expect(await pending, isNull);
    expect(await service.currentIdToken(), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('firebase.restSession'),
      isNull,
    );
  });

  test('slow account requests time out and can be retried', () async {
    var fail = true;
    final service = FirebaseProfileService.rest(
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) {
        if (fail) return Completer<http.Response>().future;
        return Future.value(
          http.Response(
            jsonEncode({
              'localId': 'test-user',
              'email': 'tester@example.com',
              'idToken': 'test-token',
              'refreshToken': 'refresh',
              'expiresIn': '3600',
            }),
            200,
          ),
        );
      }),
    );
    await expectLater(
      service.signIn(email: 'tester@example.com', password: 'test-password'),
      throwsA(isA<TimeoutException>()),
    );
    fail = false;
    await service.signIn(
      email: 'tester@example.com',
      password: 'test-password',
    );
    expect(await service.currentIdToken(), 'test-token');
  });
}

void _session({bool expired = false}) {
  SharedPreferences.setMockInitialValues({
    'firebase.restSession': jsonEncode({
      'uid': 'test-user',
      'email': 'tester@example.com',
      'displayName': 'Tester',
      'idToken': 'test-token',
      'refreshToken': 'test-refresh',
      'expiresAt': DateTime.now()
          .add(Duration(hours: expired ? -1 : 1))
          .toIso8601String(),
    }),
  });
}
