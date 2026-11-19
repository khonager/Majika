// Run the Linux bundle with FLM_MODEL set to a served model, or unset for the
// installed model. Expected titles are used only after candidate generation.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/desktop/server_process_manager.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/model_download_manager.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/services/steam_service.dart';
import 'package:majika/core/recommendations/taste_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = Platform.environment['FLM_MODEL'];
  final int result;
  try {
    result = await runBenchmark(model);
  } finally {
    if (model == null) await ServerProcessManager.instance.stop();
  }
  exit(result);
}

Future<int> runBenchmark(String? model) async {
  final LocalAiRuntimeSettings settings;
  if (model == null) {
    await FlutterGemma.initialize();
    await ModelDownloadManager.instance.restoreInstalledModel();
    if (!FlutterGemma.hasActiveModel()) throw StateError('No installed model');
    settings = LocalAiRuntimeSettings(
      useLocalAi: true,
      useAiForSearch: true,
      mode: localAiModeOnDevice,
      provider: 'Qwen',
      deviceModelName:
          FlutterGemmaPlugin.instance.modelManager.activeInferenceModel!.name,
      backend: localAiBackendCpu,
      endpoint: '',
      serverModel: '',
      contextItems: 12,
    );
  } else {
    settings = LocalAiRuntimeSettings(
      useLocalAi: true,
      useAiForSearch: true,
      mode: localAiModeExternalServer,
      provider: externalLocalAiProvider,
      endpoint: 'http://127.0.0.1:52625',
      serverModel: model,
      contextItems: 12,
    );
  }
  final ai = FlutterGemmaLocalAiService(settingsLoader: () async => settings);
  final query = await ai.interpretRecommendationRequest(
    const RecommendationQuery(request: 'rick and morty vibes but in vr'),
    serviceName: 'Steam',
    availableTags: RecommendationQuery.steamBrowsableTags,
    allowedFormats: RecommendationQuery.steamFormats,
    allowedMediaTypes: RecommendationQuery.steamMediaTypes,
  );
  final steam = SteamService();
  final catalog = await steam.searchRecommendationCandidates(query);
  final profile = TasteProfile.fromJson({
    'serviceName': 'Steam',
    'serviceId': steam.id,
  });
  final engine = TasteEngine();
  final picks = await ai.suggestRecommendationCandidates(
    profile,
    engine.rankCandidates(profile, catalog, query: query),
    query: query,
    limit: 10,
  );
  final titles = picks.map((p) => p.title).toList();
  final key = MediaItem.titleKey;
  final verified = {for (final item in catalog) item.id: item};
  for (final title in titles) {
    if (verified.values.any((item) => key(item.title) == key(title))) continue;
    final matches = await steam.searchRecommendationCandidates(
      RecommendationQuery(request: title),
    );
    for (final item in matches.where((item) => key(item.title) == key(title))) {
      verified[item.id] = item;
    }
  }
  final suggestedKeys = titles.map(key).toSet();
  final verifiedVrSuggestions = [
    for (final item in verified.values)
      if (suggestedKeys.contains(key(item.title)) && item.tags.contains('VR'))
        item.title,
  ];
  final ranked = engine
      .rankCandidates(
        profile,
        verified.values.where((item) => item.tags.contains('VR')).toList(),
        query: query,
      )
      .take(10)
      .map((r) => r.item.title)
      .toList();
  final keys = ranked.map(key).toSet();
  const expected = [
    'Vertigo',
    'Vertigo 2',
    'Rick and Morty: Virtual Rick-ality',
    'Trover Saves the Universe',
  ];
  final missing = expected.where((s) => !keys.contains(key(s))).toList();
  stdout.writeln(
    'VR_RESULT ${jsonEncode({'model': settings.activeModelName, 'query': query.toJson(), 'catalog': catalog.map((item) => item.title).toList(), 'suggestions': titles, 'verifiedVrSuggestions': verifiedVrSuggestions, 'missingFromDiscovery': expected.where((s) => !suggestedKeys.contains(key(s))).toList(), 'ranked': ranked, 'missing': missing})}',
  );
  return missing.isEmpty ? 0 : 1;
}
