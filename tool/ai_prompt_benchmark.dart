import 'dart:convert';
import 'dart:io';

const _defaultFixturePath = 'test/fixtures/ai_prompt_benchmarks.json';

void main(List<String> args) {
  final options = _BenchmarkOptions.parse(args);
  final fixture = _BenchmarkFixture.load(options.fixturePath);
  if (options.responsesPath == null) {
    stdout.writeln(
      'Loaded ${fixture.scenarios.length} prompt benchmark scenarios from ${options.fixturePath}.',
    );
    stdout.writeln(
      'Pass threshold: ${(fixture.passThreshold * 100).round()}%.',
    );
    stdout.writeln(
      'Provide --responses path/to/responses.json to score model outputs.',
    );
    stdout.writeln(
      'Export real app prompts with: AI_PROMPT_BENCHMARK_EXPORT=build/ai_prompt_benchmark_responses.json flutter test --no-pub test/ai_prompt_benchmark_export_test.dart',
    );
    stdout.writeln(
      'Collect model outputs with: AI_PROMPT_BENCHMARK_MODEL=model-name flutter pub run tool/run_ai_prompt_benchmark.dart --input build/ai_prompt_benchmark_responses.json',
    );
    return;
  }

  final run = _BenchmarkRun.load(options.responsesPath!);
  final scored = [
    for (final scenario in fixture.scenarios)
      _scoreScenario(scenario, run.responseFor(scenario.id)),
  ];
  final passed = scored.where((score) => score.passed).length;

  stdout.writeln('Model: ${run.modelName}');
  stdout.writeln('Prompt revision: ${run.promptRevision}');
  stdout.writeln('Passed $passed/${scored.length} scenarios.');
  stdout.writeln('');

  for (final score in scored) {
    final status = score.passed ? 'PASS' : 'FAIL';
    stdout.writeln(
      '$status ${score.scenarioId} ${(score.ratio * 100).round()}%',
    );
    for (final issue in score.issues) {
      stdout.writeln('  - $issue');
    }
  }
  stdout.writeln('');
  _writeGroupSummary(
    'Prompt tier suitability',
    scored,
    groupFor: (score) => score.promptTier,
    labelFor: (group) => switch (group) {
      'compact' => 'compact prompts / smallest local models',
      'balanced' => 'balanced prompts / medium local models',
      'rich' => 'rich prompts / manual and advanced cloud models',
      _ => group,
    },
  );
  stdout.writeln('');
  _writeGroupSummary(
    'Service coverage',
    scored,
    groupFor: (score) => score.service,
    labelFor: (group) => group,
  );
  stdout.writeln('');
  _writeModelVerdict(scored);

  if (scored.any((score) => !score.passed)) {
    exitCode = 1;
  }
}

void _writeGroupSummary(
  String title,
  List<_ScenarioScore> scored, {
  required String Function(_ScenarioScore score) groupFor,
  required String Function(String group) labelFor,
}) {
  stdout.writeln('$title:');
  final groups = <String, List<_ScenarioScore>>{};
  for (final score in scored) {
    groups.putIfAbsent(groupFor(score), () => []).add(score);
  }
  final names = groups.keys.toList()..sort();
  for (final name in names) {
    final scores = groups[name]!;
    final passed = scores.where((score) => score.passed).length;
    final usable = passed == scores.length;
    stdout.writeln(
      '  ${usable ? 'PASS' : 'FAIL'} ${labelFor(name)}: $passed/${scores.length}',
    );
  }
}

void _writeModelVerdict(List<_ScenarioScore> scored) {
  final byTier = <String, List<_ScenarioScore>>{};
  for (final score in scored) {
    byTier.putIfAbsent(score.promptTier, () => []).add(score);
  }
  bool tierPassed(String tier) {
    final scores = byTier[tier];
    return scores != null &&
        scores.isNotEmpty &&
        scores.every((score) => score.passed);
  }

  stdout.writeln('Model suitability:');
  stdout.writeln(
    '  ${tierPassed('compact') ? 'PASS' : 'FAIL'} smallest local model gate: compact scenarios must all pass before a tiny model is treated as usable for AI search.',
  );
  stdout.writeln(
    '  ${tierPassed('balanced') ? 'PASS' : 'FAIL'} medium local model gate: balanced scenarios must all pass before a medium local model is a quality default.',
  );
  stdout.writeln(
    '  ${tierPassed('rich') ? 'PASS' : 'FAIL'} advanced/manual/cloud gate: rich scenarios must all pass before recommending the model for full-context prompts.',
  );
}

_ScenarioScore _scoreScenario(
  _BenchmarkScenario scenario,
  _BenchmarkResponse? response,
) {
  final checks = <bool>[];
  final issues = <String>[];

  void check(bool condition, String issue) {
    checks.add(condition);
    if (!condition) issues.add(issue);
  }

  if (response == null) {
    return _ScenarioScore(
      scenarioId: scenario.id,
      service: scenario.service,
      promptTier: scenario.promptTier,
      task: scenario.task,
      ratio: 0,
      passed: false,
      issues: const ['Missing response for scenario.'],
    );
  }

  for (final expected in scenario.mustContainPromptText) {
    check(
      response.prompt.contains(expected),
      'Prompt missing required text: "$expected".',
    );
  }
  for (final forbidden in scenario.mustNotContainPromptText) {
    check(
      !response.prompt.contains(forbidden),
      'Prompt contains forbidden text: "$forbidden".',
    );
  }

  final decoded = _firstJsonObject(response.rawResponse);
  check(decoded != null, 'Response did not contain a JSON object.');
  if (decoded != null) {
    for (final entry in scenario.expectedJson.entries) {
      final key = entry.key;
      final expected = entry.value;
      if (key == 'reasonContains') {
        final reason = decoded['reason']?.toString().toLowerCase() ?? '';
        for (final token in _stringList(expected)) {
          check(
            reason.contains(token.toLowerCase()),
            'Reason did not mention "$token".',
          );
        }
      } else if (expected is List) {
        final actual = _stringList(decoded[key]);
        for (final value in _stringList(expected)) {
          check(
            actual.any((item) => _canonical(item) == _canonical(value)),
            '$key did not include "$value".',
          );
        }
      } else if (expected is bool) {
        check(decoded[key] == expected, '$key was not $expected.');
      } else if (expected is String) {
        final actual = decoded[key]?.toString() ?? '';
        check(
          _stringLooksCompatible(actual, expected),
          '$key was "$actual" instead of matching "$expected".',
        );
      }
    }
  }

  final ratio = checks.isEmpty
      ? 1.0
      : checks.where((passed) => passed).length / checks.length;
  return _ScenarioScore(
    scenarioId: scenario.id,
    service: scenario.service,
    promptTier: scenario.promptTier,
    task: scenario.task,
    ratio: ratio,
    passed: ratio >= scenario.passThreshold,
    issues: issues,
  );
}

bool _stringLooksCompatible(String actual, String expected) {
  final actualWords = _canonicalWords(actual);
  final expectedWords = _canonicalWords(expected);
  if (expectedWords.isEmpty) return actual.trim().isEmpty;
  final hits = expectedWords.where(actualWords.contains).length;
  return hits / expectedWords.length >= 0.6;
}

Set<String> _canonicalWords(String value) {
  return value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toSet();
}

String _canonical(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

Map<String, dynamic>? _firstJsonObject(String text) {
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;

  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      if (depth == 0) start = index;
      depth++;
    } else if (char == '}' && depth > 0) {
      depth--;
      if (depth == 0 && start != -1) {
        final candidate = text.substring(start, index + 1);
        try {
          final decoded = jsonDecode(candidate);
          return decoded is Map<String, dynamic> ? decoded : null;
        } catch (_) {
          start = -1;
        }
      }
    }
  }
  return null;
}

class _BenchmarkOptions {
  final String fixturePath;
  final String? responsesPath;

  const _BenchmarkOptions({
    required this.fixturePath,
    required this.responsesPath,
  });

  factory _BenchmarkOptions.parse(List<String> args) {
    var fixturePath = _defaultFixturePath;
    String? responsesPath;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--fixture':
          fixturePath = args[++index];
          break;
        case '--responses':
          responsesPath = args[++index];
          break;
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: dart run tool/ai_prompt_benchmark.dart '
            '[--fixture path] [--responses path]',
          );
          exit(0);
        default:
          stderr.writeln('Unknown argument: ${args[index]}');
          exit(64);
      }
    }
    return _BenchmarkOptions(
      fixturePath: fixturePath,
      responsesPath: responsesPath,
    );
  }
}

class _BenchmarkFixture {
  final double passThreshold;
  final List<_BenchmarkScenario> scenarios;

  const _BenchmarkFixture({
    required this.passThreshold,
    required this.scenarios,
  });

  factory _BenchmarkFixture.load(String path) {
    final decoded = _readJsonMap(path);
    final threshold =
        (decoded['scoring'] as Map<String, dynamic>?)?['passThreshold'];
    final scenarios = decoded['scenarios'];
    if (threshold is! num || scenarios is! List) {
      throw const FormatException('Invalid benchmark fixture shape.');
    }
    return _BenchmarkFixture(
      passThreshold: threshold.toDouble(),
      scenarios: [
        for (final scenario in scenarios)
          _BenchmarkScenario.fromJson(
            Map<String, dynamic>.from(scenario as Map),
            threshold.toDouble(),
          ),
      ],
    );
  }
}

class _BenchmarkScenario {
  final String id;
  final String service;
  final String promptTier;
  final String task;
  final double passThreshold;
  final List<String> mustContainPromptText;
  final List<String> mustNotContainPromptText;
  final Map<String, dynamic> expectedJson;

  const _BenchmarkScenario({
    required this.id,
    required this.service,
    required this.promptTier,
    required this.task,
    required this.passThreshold,
    required this.mustContainPromptText,
    required this.mustNotContainPromptText,
    required this.expectedJson,
  });

  factory _BenchmarkScenario.fromJson(
    Map<String, dynamic> json,
    double passThreshold,
  ) {
    return _BenchmarkScenario(
      id: json['id'] as String,
      service: json['service']?.toString() ?? 'Unknown',
      promptTier: json['promptTier']?.toString() ?? 'balanced',
      task: json['task']?.toString() ?? 'search_filter',
      passThreshold: passThreshold,
      mustContainPromptText: _stringList(json['mustContainPromptText']),
      mustNotContainPromptText: _stringList(json['mustNotContainPromptText']),
      expectedJson: Map<String, dynamic>.from(
        json['expectedJsonShape'] as Map? ?? const {},
      ),
    );
  }
}

class _BenchmarkRun {
  final String modelName;
  final String promptRevision;
  final Map<String, _BenchmarkResponse> responses;

  const _BenchmarkRun({
    required this.modelName,
    required this.promptRevision,
    required this.responses,
  });

  factory _BenchmarkRun.load(String path) {
    final decoded = _readJsonMap(path);
    final responses = decoded['responses'];
    if (responses is! List) {
      throw const FormatException('Benchmark response file needs responses.');
    }
    final parsedResponses = [
      for (final response in responses)
        _BenchmarkResponse.fromJson(Map<String, dynamic>.from(response as Map)),
    ];
    return _BenchmarkRun(
      modelName: decoded['model']?.toString() ?? 'unknown model',
      promptRevision: decoded['promptRevision']?.toString() ?? 'unknown',
      responses: {
        for (final response in parsedResponses) response.scenarioId: response,
      },
    );
  }

  _BenchmarkResponse? responseFor(String scenarioId) {
    return responses[scenarioId];
  }
}

class _BenchmarkResponse {
  final String scenarioId;
  final String prompt;
  final String rawResponse;

  const _BenchmarkResponse({
    required this.scenarioId,
    required this.prompt,
    required this.rawResponse,
  });

  factory _BenchmarkResponse.fromJson(Map<String, dynamic> json) {
    return _BenchmarkResponse(
      scenarioId: json['scenarioId'] as String,
      prompt: json['prompt']?.toString() ?? '',
      rawResponse: json['response']?.toString() ?? '',
    );
  }
}

class _ScenarioScore {
  final String scenarioId;
  final String service;
  final String promptTier;
  final String task;
  final double ratio;
  final bool passed;
  final List<String> issues;

  const _ScenarioScore({
    required this.scenarioId,
    required this.service,
    required this.promptTier,
    required this.task,
    required this.ratio,
    required this.passed,
    required this.issues,
  });
}

Map<String, dynamic> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw ArgumentError('File does not exist: $path');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}
