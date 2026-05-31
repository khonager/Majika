// ignore_for_file: avoid_print, depend_on_referenced_packages, use_null_aware_elements

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/desktop/generated/litertlm.pbgrpc.dart';
import 'package:grpc/grpc.dart';

class BenchmarkModel {
  final String name;
  final String path;

  const BenchmarkModel(this.name, this.path);
}

class BenchmarkPrompt {
  final String name;
  final String prompt;
  final bool Function(Map<String, dynamic> json) passes;

  const BenchmarkPrompt(this.name, this.prompt, this.passes);
}

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final bundle = '$root/build/linux/x64/debug/bundle';
  final java = '$bundle/lib/jre/bin/java';
  final jar = '$bundle/data/litertlm-server.jar';
  final natives = '$bundle/lib/litertlm';

  if (!Platform.isLinux) {
    stderr.writeln(
      'This benchmark currently targets the Linux desktop bundle.',
    );
    exitCode = 64;
    return;
  }
  if (!await File(java).exists() ||
      !await File(jar).exists() ||
      !await Directory(natives).exists()) {
    stderr.writeln(
      'Desktop bundle not found. Run `flutter build linux --debug` first.',
    );
    exitCode = 66;
    return;
  }

  final home = Platform.environment['HOME'] ?? '';
  final models = _modelsFromArgs(args, home);
  final prompts = _benchmarkPrompts();

  for (final model in models) {
    if (!await File(model.path).exists()) {
      print(
        jsonEncode({
          'model': model.name,
          'path': model.path,
          'status': 'missing',
        }),
      );
      continue;
    }
    await _runModelBenchmark(
      model: model,
      prompts: prompts,
      java: java,
      jar: jar,
      natives: natives,
    );
  }
}

List<BenchmarkModel> _modelsFromArgs(List<String> args, String home) {
  if (args.isEmpty) {
    return [
      BenchmarkModel(
        'FunctionGemma 270M',
        '$home/Documents/functiongemma-270M-it.litertlm',
      ),
      BenchmarkModel('Qwen3 0.6B', '$home/Documents/Qwen3-0.6B.litertlm'),
      BenchmarkModel(
        'Qwen 2.5 1.5B Instruct',
        '$home/Documents/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      ),
    ];
  }

  return [
    for (var i = 0; i < args.length; i++)
      BenchmarkModel('Custom ${i + 1}', args[i]),
  ];
}

Future<void> _runModelBenchmark({
  required BenchmarkModel model,
  required List<BenchmarkPrompt> prompts,
  required String java,
  required String jar,
  required String natives,
}) async {
  final port = await _freePort();
  final process = await Process.start(
    java,
    ['-Djava.library.path=$natives', '-Xmx4096m', '-jar', jar, '$port'],
    environment: {'LD_LIBRARY_PATH': natives},
  );
  final startup = Completer<void>();
  final logs = StringBuffer();

  void collectLog(String data) {
    logs.write(data);
    if (data.contains('started on port') && !startup.isCompleted) {
      startup.complete();
    }
  }

  process.stdout.transform(utf8.decoder).listen(collectLog);
  process.stderr.transform(utf8.decoder).listen(collectLog);

  ClientChannel? channel;
  try {
    await startup.future.timeout(const Duration(seconds: 45));
    channel = ClientChannel(
      'localhost',
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    final client = LiteRtLmServiceClient(channel);
    final initWatch = Stopwatch()..start();
    final init = await client
        .initialize(
          InitializeRequest()
            ..modelPath = model.path
            ..backend = 'cpu'
            ..maxTokens = 2048
            ..enableVision = false
            ..enableAudio = false
            ..maxNumImages = 0,
        )
        .timeout(const Duration(minutes: 3));
    initWatch.stop();

    print(
      jsonEncode({
        'model': model.name,
        'path': model.path,
        'status': init.success ? 'initialized' : 'init_failed',
        'initMs': initWatch.elapsedMilliseconds,
        if (init.error.isNotEmpty) 'error': init.error,
      }),
    );
    if (!init.success) return;

    for (final prompt in prompts) {
      print(jsonEncode(await _runPrompt(client, model.name, prompt)));
    }
    await client
        .shutdown(ShutdownRequest())
        .timeout(const Duration(seconds: 10));
  } catch (error) {
    print(
      jsonEncode({
        'model': model.name,
        'path': model.path,
        'status': 'error',
        'error': error.toString(),
        'logsTail': _tail(logs.toString()),
      }),
    );
  } finally {
    await channel?.shutdown();
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}

Future<Map<String, Object?>> _runPrompt(
  LiteRtLmServiceClient client,
  String model,
  BenchmarkPrompt prompt,
) async {
  final conversation = await client.createConversation(
    CreateConversationRequest(),
  );
  final watch = Stopwatch()..start();
  final output = StringBuffer();
  String? error;

  try {
    final stream = client.chat(
      ChatRequest()
        ..conversationId = conversation.conversationId
        ..text = prompt.prompt,
    );
    await for (final response in stream.timeout(const Duration(minutes: 2))) {
      if (response.hasError() && response.error.isNotEmpty) {
        error = response.error;
        break;
      }
      if (response.hasText()) output.write(response.text);
      if (response.done) break;
    }
  } catch (caught) {
    error = caught.toString();
  } finally {
    watch.stop();
    await client.closeConversation(
      CloseConversationRequest()..conversationId = conversation.conversationId,
    );
  }

  final text = output.toString().trim();
  final jsonText = _extractJsonObject(text);
  var validJson = false;
  var passed = false;
  if (jsonText != null) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        validJson = true;
        passed = prompt.passes(decoded);
      }
    } catch (_) {
      validJson = false;
    }
  }

  return {
    'model': model,
    'prompt': prompt.name,
    'latencyMs': watch.elapsedMilliseconds,
    'chars': text.length,
    'validJson': validJson,
    'passed': passed,
    if (error != null) 'error': error,
    'output': text.length > 500 ? '${text.substring(0, 500)}...' : text,
  };
}

List<BenchmarkPrompt> _benchmarkPrompts() {
  return [
    BenchmarkPrompt(
      'search romance time travel movie',
      '''
You turn recommendation search text into structured AniList filters.
Return JSON only. No markdown. No explanation.
Allowed mediaTypes: ANIME, MANGA
Allowed formats: TV, TV_SHORT, MOVIE, SPECIAL, OVA, ONA, MUSIC, MANGA, NOVEL, ONE_SHOT
Allowed tags: Romance, Time Manipulation, Thriller, Mystery, Psychological, Supernatural, Comedy, Drama, Action, Adventure, Yandere
Schema:
{"tags":["Romance"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"optional leftover search terms"}
User request: romance movie about time travel
Currently selected tags:
Previously AI selected tags:
Currently selected formats:
Currently selected media types:
Adult content selected: false
''',
      (json) =>
          json.toString().contains('Romance') &&
          json.toString().contains('Time Manipulation') &&
          json.toString().contains('MOVIE'),
    ),
    BenchmarkPrompt(
      'search obsessed character thriller',
      '''
You turn recommendation search text into structured AniList filters.
Return JSON only. No markdown. No explanation.
Allowed mediaTypes: ANIME, MANGA
Allowed formats: TV, MOVIE, MANGA, NOVEL, ONE_SHOT
Allowed tags: Romance, Time Manipulation, Thriller, Mystery, Psychological, Supernatural, Comedy, Drama, Action, Adventure, Yandere
Schema:
{"tags":["Thriller"],"formats":[],"mediaTypes":[],"includeAdult":false,"searchText":"optional leftover search terms"}
User request: obsessed character thriller
Currently selected tags:
Previously AI selected tags:
Currently selected formats:
Currently selected media types:
Adult content selected: false
''',
      (json) =>
          json.toString().contains('Thriller') &&
          (json.toString().contains('Yandere') ||
              json.toString().contains('Psychological')),
    ),
    BenchmarkPrompt('top pick from candidates', '''
Pick the single best recommendation for this user from the options.
Return JSON only with this schema: {"id":"anilist_123","reason":"short reason"}
User taste: moody psychological mystery with supernatural tension
Favorite tags: Mystery, Psychological, Supernatural
Favorite characters:
Favorite studios:
Search request: moody mystery with a clever twist
User-selected tags: Mystery
AI-selected tags: Psychological
Options: [{"id":"anilist_1","title":"Bright Sports Comedy","score":62,"tags":["Comedy","Sports"],"format":"TV","signals":["popular"]},{"id":"anilist_2","title":"Shadow Puzzle","score":88,"tags":["Mystery","Psychological","Supernatural"],"format":"TV","signals":["matches Mystery","matches Psychological"]},{"id":"anilist_3","title":"Soft Romance","score":70,"tags":["Romance","Drama"],"format":"MOVIE","signals":["high score"]}]
''', (json) => json['id'] == 'anilist_2'),
  ];
}

String? _extractJsonObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  return text.substring(start, end + 1);
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String _tail(String text) {
  if (text.length <= 1200) return text;
  return text.substring(text.length - 1200);
}
