import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/storage/local_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'local profile session round trips through shared preferences',
    () async {
      const store = LocalProfileStore();
      final session = LocalProfileSession(
        serviceId: 'com.majika.service.anilist',
        profile: _profile(),
        candidates: [
          MediaItem(
            id: 'anilist_2',
            title: 'Candidate',
            coverUrl: '',
            tags: const ['Comedy'],
            format: 'TV',
            mediaType: 'ANIME',
          ),
        ],
        serviceTags: const ['Comedy', 'Mystery'],
        query: const RecommendationQuery(
          request: 'funny tv',
          selectedTags: {'Comedy'},
          mediaTypes: {'ANIME'},
        ),
        adultCandidatesLoaded: true,
        userNameDraft: 'tester',
      );

      await store.saveSession(session);
      final restored = await store.loadSessions();
      final saved = restored['com.majika.service.anilist'];

      expect(saved, isNotNull);
      expect(saved!.profile.userName, 'tester');
      expect(saved.profile.favoriteGenres, contains('Mystery'));
      expect(saved.candidates.single.title, 'Candidate');
      expect(saved.serviceTags, contains('Comedy'));
      expect(saved.query.request, 'funny tv');
      expect(saved.query.selectedTags, contains('Comedy'));
      expect(saved.adultCandidatesLoaded, isTrue);
    },
  );

  test('removeSession clears one saved service', () async {
    const store = LocalProfileStore();
    await store.saveSession(
      LocalProfileSession(
        serviceId: 'one',
        profile: _profile(serviceId: 'one'),
        candidates: const [],
        serviceTags: const [],
        query: const RecommendationQuery(),
        adultCandidatesLoaded: false,
        userNameDraft: 'one',
      ),
    );
    await store.saveSession(
      LocalProfileSession(
        serviceId: 'two',
        profile: _profile(serviceId: 'two'),
        candidates: const [],
        serviceTags: const [],
        query: const RecommendationQuery(),
        adultCandidatesLoaded: false,
        userNameDraft: 'two',
      ),
    );

    await store.removeSession('one');
    final restored = await store.loadSessions();

    expect(restored.containsKey('one'), isFalse);
    expect(restored.containsKey('two'), isTrue);
  });
}

TasteProfile _profile({String serviceId = 'com.majika.service.anilist'}) {
  return TasteProfile(
    userName: 'tester',
    library: [
      MediaItem(
        id: '${serviceId}_1',
        title: 'Seen Mystery',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 9,
      ),
    ],
    favoriteGenres: const ['Mystery'],
    tagWeights: const {'Mystery': 2},
    formatWeights: const {'TV': 1},
    formatCounts: const {'TV': 1},
    favoriteCharacters: const ['Odokawa'],
    favoriteStaff: const [],
    favoriteStudios: const ['OLM'],
    highRatedItems: const [],
    recentActivity: null,
    completedCount: 1,
    currentCount: 0,
    importedAt: DateTime(2026),
    serviceId: serviceId,
    serviceName: 'AniList',
  );
}
