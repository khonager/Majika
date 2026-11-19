import 'dart:async';
import 'dart:convert';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:majika/core/models/recommendation_query.dart';
// Run with an isolated application data directory. Downloads a real public
// model and checks native loading/generation using the production installer.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:majika/core/ai/model_download_manager.dart';
import 'package:majika/core/ai/on_device_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final manager = ModelDownloadManager.instance;
  var lastStep = -1;
  manager.addListener(() {
    final step = ((manager.progress ?? 0) * 10).floor();
    if (step != lastStep ||
        !manager.busy ||
        manager.phase == ModelDownloadPhase.checking) {
      debugPrint('MODEL_SETUP ${manager.status}');
      lastStep = step;
    }
  });
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Testing on-device model setup…')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    const id = String.fromEnvironment('MODEL_ID', defaultValue: 'qwen3_0_6b');
    const restoreOnly = bool.fromEnvironment('RESTORE_ONLY');
    const nicheRequest = String.fromEnvironment('NICHE_REQUEST');
    const nicheExpectedTerms = String.fromEnvironment('NICHE_EXPECT_TERMS');
    const nicheExpectNoTags = bool.fromEnvironment('NICHE_EXPECT_NO_TAGS');
    if (restoreOnly) {
      await FlutterGemma.initialize();
      await manager.restoreInstalledModel();
      if (!FlutterGemma.hasActiveModel()) {
        debugPrint('MODEL_RESTORE_RESULT failed');
        exit(1);
      }
      debugPrint('MODEL_RESTORE_RESULT ready');
    } else {
      await manager.download(
        downloadableAiModels.firstWhere((model) => model.id == id),
      );
      debugPrint('MODEL_SETUP_RESULT ${manager.phase.name}');
      if (manager.phase != ModelDownloadPhase.ready) exit(1);
    }
    final log = AiConsoleLog();
    final watch = Stopwatch()..start();
    final query = await runZoned(
      () => FlutterGemmaLocalAiService().interpretRecommendationRequest(
        const RecommendationQuery(
          request: nicheRequest == ''
              ? 'romance movie about time travel'
              : nicheRequest,
        ),
        availableTags: const [
          'Romance',
          'Time Manipulation',
          'Mystery',
          'Comedy',
          'Drama',
          'Music',
        ],
      ),
      zoneValues: {localAiConsoleLogZoneKey: log},
    );
    debugPrint(
      'MODEL_SEARCH_RESULT ${jsonEncode({'ms': watch.elapsedMilliseconds, 'tags': query.aiSelectedTags.toList(), 'formats': query.formats.toList(), 'includeAdult': query.includeAdult, 'interpretedRequest': query.interpretedRequest})}',
    );
    debugPrint(log.value);
    final passed = nicheRequest.isEmpty
        ? query.aiSelectedTags.contains('Romance') &&
              query.aiSelectedTags.contains('Time Manipulation') &&
              query.formats.contains('MOVIE') &&
              !query.includeAdult
        : (!nicheExpectNoTags || query.aiSelectedTags.isEmpty) &&
              nicheExpectedTerms.trim().isNotEmpty &&
              nicheExpectedTerms
                  .split('|')
                  .where((term) => term.trim().isNotEmpty)
                  .every(
                    (term) => query.interpretedRequest.toLowerCase().contains(
                      term.trim().toLowerCase(),
                    ),
                  );
    debugPrint('MODEL_SEARCH_CHECK ${passed ? 'passed' : 'failed'}');
    exit(passed ? 0 : 1);
  });
}
