import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/services/firebase_steam_backend.dart';
import 'package:majika/core/services/steam_service.dart';

void main() {
  test(
    'Steam rejects signed-out requests before contacting the backend',
    () async {
      final api = FirebaseSteamProtectedApi(
        idTokenProvider: () async => null,
        restClient: MockClient((_) => throw StateError('Must not send')),
      );
      await expectLater(
        api.getOwnedGames('12345678901234567'),
        throwsA(
          isA<SteamException>().having(
            (e) => e.toString(),
            'message',
            contains('Sign in'),
          ),
        ),
      );
    },
  );

  test('Steam forwards authentication and decodes callable results', () async {
    final api = FirebaseSteamProtectedApi(
      idTokenProvider: () async => 'test-token',
      restClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body), {
          'data': {'action': 'getOwnedGames', 'steamId': '12345678901234567'},
        });
        return http.Response(
          '{"result":{"response":{"game_count":0,"games":[]}}}',
          200,
        );
      }),
    );
    expect(
      (await api.getOwnedGames('12345678901234567'))['response']['games'],
      isEmpty,
    );
  });

  test(
    'Steam shows callable error messages instead of raw response bodies',
    () async {
      final api = FirebaseSteamProtectedApi(
        idTokenProvider: () async => 'test-token',
        restClient: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Sign in again.","status":"UNAUTHENTICATED"}}',
            401,
          ),
        ),
      );
      await expectLater(
        api.getOwnedGames('12345678901234567'),
        throwsA(
          isA<SteamException>().having(
            (e) => e.toString(),
            'message',
            'Sign in again.',
          ),
        ),
      );
    },
  );

  test('Steam handles non-JSON outages and bounded network waits', () async {
    final api = FirebaseSteamProtectedApi(
      idTokenProvider: () async => 'test-token',
      restClient: MockClient(
        (_) async => http.Response('<html>gateway error</html>', 502),
      ),
    );
    await expectLater(
      api.getOwnedGames('12345678901234567'),
      throwsA(
        isA<SteamException>().having(
          (e) => e.toString(),
          'message',
          contains('try again'),
        ),
      ),
    );
    final slow = FirebaseSteamProtectedApi(
      requestTimeout: const Duration(milliseconds: 10),
      idTokenProvider: () async => 'test-token',
      restClient: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      slow.getOwnedGames('12345678901234567'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
