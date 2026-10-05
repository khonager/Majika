import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';

class CloudAiProbeResult {
  final bool structuredResponses;
  final bool toolCalling;
  final String message;

  const CloudAiProbeResult({
    this.structuredResponses = false,
    this.toolCalling = false,
    required this.message,
  });

  bool get passed => structuredResponses && toolCalling;
}

/// A bounded, synthetic check. Never sends library data or executes real tools.
class CloudAiProbe {
  final http.Client client;
  final Duration timeout;

  const CloudAiProbe(this.client, {this.timeout = const Duration(seconds: 30)});

  Future<CloudAiProbeResult> run(LocalAiRuntimeSettings settings) async {
    var structured = false;
    try {
      final uri = settings.cloudChatCompletionsUri;
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return const CloudAiProbeResult(
          message: 'Enter a valid HTTPS cloud endpoint.',
        );
      }
      if (settings.cloudApiKey.trim().isEmpty ||
          settings.cloudModel.trim().isEmpty) {
        return const CloudAiProbeResult(
          message: 'Paste an API key and choose a model first.',
        );
      }
      final model = normalizedFreeCloudAiModel(
        provider: settings.cloudProvider,
        model: settings.cloudModel,
      );
      Future<Map<String, dynamic>> send(
        List<Map<String, dynamic>> messages, {
        bool tools = false,
      }) async {
        final response = await client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${settings.cloudApiKey.trim()}',
              },
              body: jsonEncode({
                'model': model,
                'messages': messages,
                'temperature': 0.1,
                'max_tokens': 256,
                'stream': false,
                ...cloudAiRoutingOptions(settings.cloudProvider),
                if (tools) ...{
                  'tools': [
                    {
                      'type': 'function',
                      'function': {
                        'name': 'lookup_catalog',
                        'description':
                            'Look up a synthetic catalog record by ID.',
                        'parameters': {
                          'type': 'object',
                          'properties': {
                            'id': {'type': 'string'},
                          },
                          'required': ['id'],
                        },
                      },
                    },
                  ],
                  'tool_choice': 'auto',
                },
              }),
            )
            .timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Do not surface raw provider bodies, which may echo credentials.
          throw _ProbeFailure(switch (response.statusCode) {
            401 || 403 =>
              'Key rejected or model access denied. Check your key and permissions.',
            402 =>
              'Provider credits or spending limit reached. Check billing; no paid retry was made.',
            404 =>
              'Model or endpoint unavailable. Choose another model or check the endpoint.',
            429 =>
              'Free quota or rate limit reached. Wait and retry, or choose another provider.',
            _ =>
              'Provider returned HTTP ${response.statusCode}. Check model compatibility and account limits.',
          });
        }
        final decoded = jsonDecode(response.body);
        final message = decoded['choices'][0]['message'];
        if (message is! Map<String, dynamic>) throw const FormatException();
        return message;
      }

      final jsonMessage = await send([
        {
          'role': 'user',
          'content':
              'Return only a JSON object with key "ids" containing ["sample-2"]. No markdown or extra keys.',
        },
      ]);
      final data = jsonDecode(jsonMessage['content'] as String);
      if (data is! Map ||
          data.length != 1 ||
          jsonEncode(data['ids']) != '["sample-2"]') {
        throw const _ProbeFailure(
          'Connected, but the model did not follow the structured-response instructions. Try another model.',
        );
      }
      structured = true;
      final messages = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content':
              'Call lookup_catalog with id "sample-2". After receiving the tool result, return only JSON with its "title" value. Do not guess the title.',
        },
      ];
      final toolMessage = await send(messages, tools: true);
      final calls = toolMessage['tool_calls'];
      if (calls is! List || calls.length != 1) {
        throw const _ProbeFailure(
          'Structured responses passed, but the model did not call the tool. Try another model for search tools.',
        );
      }
      final call = calls.single;
      final args = jsonDecode(call['function']['arguments'] as String);
      if (call['id'] is! String ||
          (call['id'] as String).isEmpty ||
          call['function']['name'] != 'lookup_catalog' ||
          args is! Map ||
          args['id'] != 'sample-2') {
        throw const _ProbeFailure(
          'The model returned an invalid tool call. Try another model.',
        );
      }
      // Generated after the call so the answer must come from the tool result.
      final title = 'Catalog-${DateTime.now().microsecondsSinceEpoch}';
      messages.add({
        'role': 'assistant',
        if (toolMessage['content'] != null) 'content': toolMessage['content'],
        'tool_calls': calls,
      });
      messages.add({
        'role': 'tool',
        'tool_call_id': call['id'],
        'content': jsonEncode({'title': title}),
      });
      final finalMessage = await send(messages, tools: true);
      final grounded = jsonDecode(finalMessage['content'] as String);
      if (grounded is! Map || grounded['title'] != title) {
        throw const _ProbeFailure(
          'The model called a tool but did not use its result correctly. Try another model.',
        );
      }
      return const CloudAiProbeResult(
        structuredResponses: true,
        toolCalling: true,
        message:
            'Passed: structured responses and tool calling with a grounded result. This is a basic compatibility check, not a recommendation-quality benchmark. Free routers can change models between requests.',
      );
    } on _ProbeFailure catch (error) {
      return CloudAiProbeResult(
        structuredResponses: structured,
        message: error.message,
      );
    } on TimeoutException {
      return CloudAiProbeResult(
        structuredResponses: structured,
        message: 'Provider timed out. Retry or choose a faster model.',
      );
    } on http.ClientException {
      return CloudAiProbeResult(
        structuredResponses: structured,
        message:
            'Could not reach the provider. Check your connection and endpoint.',
      );
    } catch (_) {
      return CloudAiProbeResult(
        structuredResponses: structured,
        message:
            'The response did not match the required JSON or tool format. Try another model.',
      );
    }
  }
}

class _ProbeFailure implements Exception {
  final String message;
  const _ProbeFailure(this.message);
}
