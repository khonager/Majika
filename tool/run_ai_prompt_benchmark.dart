import 'dart:convert';
import 'dart:io';

const _defaultInputPath = 'build/ai_prompt_benchmark_responses.json';
const _defaultOutputPath = 'build/ai_prompt_benchmark_model_responses.json';
const _defaultEndpoint = 'http://127.0.0.1:11434/v1/chat/completions';

Future<void> main(List<String> args) async {
  final options = _RunOptions.parse(args);
  final run = _BenchmarkRun.load(options.inputPath);
  final model = options.model ?? run.modelName;

  if (options.dryRun) {
    stdout.writeln(
      'Loaded ${run.responses.length} prompts from ${options.inputPath}.',
    );
    stdout.writeln('Model: $model');
    stdout.writeln('Endpoint: ${options.endpoint}');
    stdout.writeln(
      'Dry run only. Remove --dry-run to request model responses.',
    );
    return;
  }

  if (model.trim().isEmpty || model == 'manual-model-under-test') {
    stderr.writeln(
      'Provide --model or AI_PROMPT_BENCHMARK_MODEL for the model under test.',
    );
    exit(64);
  }

  final client = HttpClient();
  final updatedResponses = <Map<String, dynamic>>[];
  try {
    for (final response in run.responses) {
      final existingResponse = response.response.trim();
      if (existingResponse.isNotEmpty && !options.force) {
        stdout.writeln('SKIP ${response.scenarioId} already has a response.');
        updatedResponses.add(response.toJson());
        continue;
      }
      if (response.prompt.trim().isEmpty) {
        stderr.writeln('Missing prompt for ${response.scenarioId}.');
        exitCode = 65;
        updatedResponses.add(response.toJson());
        continue;
      }

      stdout.writeln('RUN  ${response.scenarioId}');
      final rawResponse = await _requestModel(
        client,
        endpoint: options.endpoint,
        apiKey: options.apiKey,
        model: model,
        prompt: response.prompt,
        temperature: options.temperature,
        maxTokens: options.maxTokens,
      );
      updatedResponses.add(response.copyWith(response: rawResponse).toJson());
    }
  } finally {
    client.close(force: true);
  }

  final output = {
    ...run.root,
    'model': model,
    'promptRevision': options.promptRevision ?? run.promptRevision,
    'responses': updatedResponses,
  };
  final file = File(options.outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
  stdout.writeln('Wrote model responses to ${options.outputPath}.');
  stdout.writeln(
    'Score with: flutter pub run tool/ai_prompt_benchmark.dart --responses ${options.outputPath}',
  );
}

Future<String> _requestModel(
  HttpClient client, {
  required Uri endpoint,
  required String apiKey,
  required String model,
  required String prompt,
  required double temperature,
  required int maxTokens,
}) async {
  final request = await client.postUrl(endpoint);
  request.headers.contentType = ContentType.json;
  if (apiKey.trim().isNotEmpty) {
    request.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
  }
  if (endpoint.host.contains('openrouter.ai')) {
    request.headers.set('HTTP-Referer', 'https://majika.local');
    request.headers.set('X-OpenRouter-Title', 'Majika AI Prompt Benchmark');
  }
  request.write(
    jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    }),
  );

  final response = await request.close().timeout(const Duration(seconds: 90));
  final body = await utf8.decodeStream(response);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      'Model endpoint returned HTTP ${response.statusCode}: $body',
    );
  }

  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Model response was not a JSON object.');
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    throw const FormatException('Model response did not include choices.');
  }
  final first = choices.first;
  if (first is! Map<String, dynamic>) {
    throw const FormatException('First model choice was not an object.');
  }
  final message = first['message'];
  if (message is Map<String, dynamic> && message['content'] != null) {
    return message['content'].toString();
  }
  if (first['text'] != null) return first['text'].toString();
  throw const FormatException('Model response did not include text content.');
}

Uri _chatCompletionsUri(String value) {
  final parsed = Uri.parse(value.trim());
  final path = parsed.path.endsWith('/')
      ? parsed.path.substring(0, parsed.path.length - 1)
      : parsed.path;
  if (path.endsWith('/chat/completions')) return parsed;
  if (path.endsWith('/v1')) {
    return parsed.replace(path: '$path/chat/completions');
  }
  if (path.endsWith('/openai')) {
    return parsed.replace(path: '$path/chat/completions');
  }
  return parsed.replace(path: '$path/v1/chat/completions');
}

class _RunOptions {
  final String inputPath;
  final String outputPath;
  final Uri endpoint;
  final String apiKey;
  final String? model;
  final String? promptRevision;
  final double temperature;
  final int maxTokens;
  final bool force;
  final bool dryRun;

  const _RunOptions({
    required this.inputPath,
    required this.outputPath,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.promptRevision,
    required this.temperature,
    required this.maxTokens,
    required this.force,
    required this.dryRun,
  });

  factory _RunOptions.parse(List<String> args) {
    var inputPath = _env('AI_PROMPT_BENCHMARK_INPUT') ?? _defaultInputPath;
    var outputPath = _env('AI_PROMPT_BENCHMARK_OUTPUT') ?? _defaultOutputPath;
    var endpoint = _env('AI_PROMPT_BENCHMARK_ENDPOINT') ?? _defaultEndpoint;
    var apiKey = _env('AI_PROMPT_BENCHMARK_API_KEY') ?? '';
    var model = _env('AI_PROMPT_BENCHMARK_MODEL');
    var promptRevision = _env('AI_PROMPT_BENCHMARK_REVISION');
    var temperature = 0.1;
    var maxTokens = 1024;
    var force = false;
    var dryRun = false;

    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--input':
          inputPath = args[++index];
          break;
        case '--output':
          outputPath = args[++index];
          break;
        case '--endpoint':
          endpoint = args[++index];
          break;
        case '--api-key':
          apiKey = args[++index];
          break;
        case '--model':
          model = args[++index];
          break;
        case '--prompt-revision':
          promptRevision = args[++index];
          break;
        case '--temperature':
          temperature = double.parse(args[++index]);
          break;
        case '--max-tokens':
          maxTokens = int.parse(args[++index]);
          break;
        case '--force':
          force = true;
          break;
        case '--dry-run':
          dryRun = true;
          break;
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: flutter pub run tool/run_ai_prompt_benchmark.dart '
            '[--input path] [--output path] [--endpoint url] [--api-key key] '
            '[--model name] [--prompt-revision label] [--temperature n] '
            '[--max-tokens n] [--force] [--dry-run]',
          );
          stdout.writeln('');
          stdout.writeln(
            'Environment aliases: AI_PROMPT_BENCHMARK_INPUT, OUTPUT, ENDPOINT, API_KEY, MODEL, REVISION.',
          );
          stdout.writeln(
            'Endpoint must be OpenAI-compatible. Examples: Ollama /v1, Google Gemini OpenAI endpoint, OpenRouter.',
          );
          exit(0);
        default:
          stderr.writeln('Unknown argument: ${args[index]}');
          exit(64);
      }
    }

    return _RunOptions(
      inputPath: inputPath,
      outputPath: outputPath,
      endpoint: _chatCompletionsUri(endpoint),
      apiKey: apiKey,
      model: model,
      promptRevision: promptRevision,
      temperature: temperature,
      maxTokens: maxTokens,
      force: force,
      dryRun: dryRun,
    );
  }
}

class _BenchmarkRun {
  final Map<String, dynamic> root;
  final String modelName;
  final String promptRevision;
  final List<_BenchmarkResponse> responses;

  const _BenchmarkRun({
    required this.root,
    required this.modelName,
    required this.promptRevision,
    required this.responses,
  });

  factory _BenchmarkRun.load(String path) {
    final decoded = _readJsonMap(path);
    final responses = decoded['responses'];
    if (responses is! List) {
      throw const FormatException('Benchmark input needs responses.');
    }
    return _BenchmarkRun(
      root: decoded,
      modelName: decoded['model']?.toString() ?? '',
      promptRevision: decoded['promptRevision']?.toString() ?? 'unknown',
      responses: [
        for (final response in responses)
          _BenchmarkResponse.fromJson(
            Map<String, dynamic>.from(response as Map),
          ),
      ],
    );
  }
}

class _BenchmarkResponse {
  final Map<String, dynamic> json;
  final String scenarioId;
  final String prompt;
  final String response;

  const _BenchmarkResponse({
    required this.json,
    required this.scenarioId,
    required this.prompt,
    required this.response,
  });

  factory _BenchmarkResponse.fromJson(Map<String, dynamic> json) {
    return _BenchmarkResponse(
      json: json,
      scenarioId: json['scenarioId'] as String,
      prompt: json['prompt']?.toString() ?? '',
      response: json['response']?.toString() ?? '',
    );
  }

  _BenchmarkResponse copyWith({String? response}) {
    return _BenchmarkResponse(
      json: json,
      scenarioId: scenarioId,
      prompt: prompt,
      response: response ?? this.response,
    );
  }

  Map<String, dynamic> toJson() {
    return {...json, 'prompt': prompt, 'response': response};
  }
}

String? _env(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

Map<String, dynamic> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) throw ArgumentError('File does not exist: $path');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}
