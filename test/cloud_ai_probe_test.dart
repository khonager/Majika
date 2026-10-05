import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/ai/cloud_ai_probe.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/ui/settings/cloud_ai_test_card.dart';

LocalAiRuntimeSettings settings({
  String key = 'test-secret',
  String endpoint = 'https://openrouter.ai/api/v1',
}) => LocalAiRuntimeSettings(
  useLocalAi: true,
  useAiForSearch: true,
  provider: externalCloudAiProvider,
  mode: localAiModeExternalCloud,
  endpoint: defaultLocalAiEndpoint,
  serverModel: defaultLocalAiModel,
  cloudProvider: 'OpenRouter',
  cloudModel: 'openrouter/free',
  cloudEndpoint: endpoint,
  cloudApiKey: key,
  contextItems: 24,
);

http.Response reply(Map<String, dynamic> message) => http.Response(
  jsonEncode({
    'choices': [
      {'message': message},
    ],
  }),
  200,
);

http.Response successfulReply(http.Request request) {
  final body = jsonDecode(request.body);
  final messages = body['messages'] as List;
  if (body['tools'] == null) {
    return reply({'content': '{"ids":["sample-2"]}'});
  }
  if (messages.last['role'] == 'tool') {
    return reply({'content': messages.last['content']});
  }
  return reply({
    'tool_calls': [
      {
        'id': 'call_1',
        'type': 'function',
        'function': {
          'name': 'lookup_catalog',
          'arguments': '{"id":"sample-2"}',
        },
      },
    ],
  });
}

void main() {
  test(
    'verifies JSON, tool arguments and grounded result with bounded free requests',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return successfulReply(request);
      });
      final result = await CloudAiProbe(client).run(settings());
      expect(result.passed, isTrue);
      expect(requests, hasLength(3));
      for (final request in requests) {
        final body = jsonDecode(request.body);
        expect(body['max_tokens'], 256);
        expect(body['provider']['max_price'], {
          'prompt': 0,
          'completion': 0,
          'request': 0,
        });
        expect(body['provider']['require_parameters'], isTrue);
        expect(request.url.path, '/api/v1/chat/completions');
        expect(request.headers['Authorization'], 'Bearer test-secret');
      }
      final last = jsonDecode(requests.last.body)['messages'] as List;
      expect(last.last['tool_call_id'], 'call_1');
      expect(last.last['role'], 'tool');
    },
  );

  test('missing key and insecure endpoints never send a request', () async {
    final client = MockClient((_) async => throw StateError('Must not send'));
    for (final config in [
      settings(key: ''),
      settings(endpoint: 'http://example.com'),
      settings(endpoint: 'not a URL'),
    ]) {
      expect((await CloudAiProbe(client).run(config)).passed, isFalse);
    }
  });

  for (final code in [401, 403, 402, 404, 429, 500]) {
    test('HTTP $code gives safe actionable feedback without retry', () async {
      var calls = 0;
      final result = await CloudAiProbe(
        MockClient((_) async {
          calls++;
          return http.Response('test-secret private response', code);
        }),
      ).run(settings());
      expect(result.passed, isFalse);
      expect(result.message, isNot(contains('test-secret')));
      expect(calls, 1);
    });
  }

  test(
    'valid HTTP is insufficient without correct structured content',
    () async {
      for (final content in [
        'hello',
        '{"ids":["wrong"]}',
        '{"ids":"sample-2"}',
      ]) {
        final result = await CloudAiProbe(
          MockClient((_) async => reply({'content': content})),
        ).run(settings());
        expect(result.structuredResponses, isFalse);
        expect(result.passed, isFalse);
      }
    },
  );

  test('text-only model is not marked tool capable', () async {
    final result = await CloudAiProbe(
      MockClient((request) async {
        if (jsonDecode(request.body)['tools'] != null) {
          return reply({'content': 'I cannot call tools'});
        }
        return successfulReply(request);
      }),
    ).run(settings());
    expect(result.structuredResponses, isTrue);
    expect(result.toolCalling, isFalse);
  });

  test('fabricated tool result does not pass', () async {
    final result = await CloudAiProbe(
      MockClient((request) async {
        final messages = jsonDecode(request.body)['messages'] as List;
        if (messages.last['role'] == 'tool') {
          return reply({'content': '{"title":"guess"}'});
        }
        return successfulReply(request);
      }),
    ).run(settings());
    expect(result.passed, isFalse);
    expect(result.message, contains('did not use its result'));
  });

  test('timeout is bounded and does not retry', () async {
    final pending = Completer<http.Response>();
    final result = await CloudAiProbe(
      MockClient((_) => pending.future),
      timeout: const Duration(milliseconds: 1),
    ).run(settings());
    expect(result.message, contains('timed out'));
    pending.complete(http.Response('', 500));
  });

  testWidgets(
    'setup disables missing-key test and invalidates result on edits',
    (tester) async {
      final endpoint = TextEditingController(
        text: 'https://openrouter.ai/api/v1',
      );
      final model = TextEditingController(text: 'openrouter/free');
      final key = TextEditingController();
      addTearDown(endpoint.dispose);
      addTearDown(model.dispose);
      addTearDown(key.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudAiTestCard(
              provider: 'OpenRouter',
              endpoint: endpoint,
              model: model,
              apiKey: key,
              clientFactory: () =>
                  MockClient((request) async => successfulReply(request)),
            ),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      key.text = 'key';
      await tester.pump();
      await tester.tap(find.text('Test AI capabilities'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready: Passed'), findsOneWidget);
      model.text = 'another-model';
      await tester.pump();
      expect(find.textContaining('Ready: Passed'), findsNothing);
    },
  );

  testWidgets('editing configuration discards an in-flight result', (
    tester,
  ) async {
    final endpoint = TextEditingController(
      text: 'https://openrouter.ai/api/v1',
    );
    final model = TextEditingController(text: 'openrouter/free');
    final key = TextEditingController(text: 'key');
    addTearDown(endpoint.dispose);
    addTearDown(model.dispose);
    addTearDown(key.dispose);
    final pending = Completer<http.Response>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudAiTestCard(
            provider: 'OpenRouter',
            endpoint: endpoint,
            model: model,
            apiKey: key,
            clientFactory: () => MockClient((_) => pending.future),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Test AI capabilities'));
    await tester.pump();
    expect(find.text('Testing capabilities…'), findsOneWidget);
    key.text = 'new-key';
    pending.complete(http.Response('denied', 401));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not verified:'), findsNothing);
    expect(find.text('Test AI capabilities'), findsOneWidget);
  });
}
