import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

abstract class LocalAiService {
  bool get isConfigured;

  Future<String> summarizeProfile(TasteProfile profile);

  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  });

  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  );
}

class DeterministicLocalAiService implements LocalAiService {
  const DeterministicLocalAiService();

  @override
  bool get isConfigured => false;

  @override
  Future<String> summarizeProfile(TasteProfile profile) async {
    return profile.summary;
  }

  @override
  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  }) async {
    return query.withInferredSelections(availableTags);
  }

  @override
  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  ) async {
    return recommendation.reason;
  }
}

class FlutterGemmaLocalAiService implements LocalAiService {
  final String modelPath;

  const FlutterGemmaLocalAiService({required this.modelPath});

  @override
  bool get isConfigured => modelPath.isNotEmpty;

  @override
  Future<String> summarizeProfile(TasteProfile profile) {
    throw UnimplementedError(
      'flutter_gemma model execution is the next step after model import UX.',
    );
  }

  @override
  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  }) {
    throw UnimplementedError(
      'flutter_gemma query interpretation is planned for local model execution.',
    );
  }

  @override
  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  ) {
    throw UnimplementedError(
      'flutter_gemma model execution is the next step after model import UX.',
    );
  }
}
