import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/main.dart';
import 'package:majika/ui/home/home_screen.dart';
import 'package:majika/ui/settings/settings_screen.dart';

void main() {
  testWidgets('app renders AniList connect prompt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MajikaApp());

    expect(find.text('Majika'), findsOneWidget);
    expect(find.text('Connect AniList'), findsOneWidget);
    expect(find.text('Build profile'), findsOneWidget);
  });

  testWidgets(
    'imported profile renders recommendations with semantics enabled',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
        );

        await tester.enterText(find.byType(TextField), 'tester');
        await tester.tap(find.text('Build profile'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
        expect(find.text('Top recommendation'), findsOneWidget);
        expect(find.text('Best Match'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('search request and chips refill recommendations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'hentai romance ova',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Adult Match'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filter-type-manga')));
    await tester.pumpAndSettle();

    expect(find.text('Adult Match'), findsNothing);
    expect(find.textContaining('No matches'), findsOneWidget);
  });

  testWidgets('natural language search fetches matching candidates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'romance movie about time travel',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Time Travel Movie'), findsOneWidget);
    expect(find.text('Romance'), findsWidgets);
    expect(find.text('Time Manipulation'), findsWidgets);
  });

  testWidgets('tag picker keeps the long tag list out of the main feed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('browse-tags-button')), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('browse-tags-button')));
    await tester.pumpAndSettle();

    expect(find.text('Choose tags'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-picker-search')), findsOneWidget);
    expect(find.text('Yandere'), findsOneWidget);
  });

  testWidgets('recommendation results expose AniList links', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open on AniList'), findsWidgets);
  });

  testWidgets(
    'switch user returns to the import form without layout overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
      );

      await tester.enterText(find.byType(TextField).first, 'tester');
      await tester.tap(find.text('Build profile'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Top recommendation'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch user'));
      await tester.pumpAndSettle();

      expect(find.text('Connect AniList'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('sign out clears the imported AniList profile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Connect AniList'), findsOneWidget);
    expect(find.text('@tester · Mystery + Drama'), findsNothing);
  });

  testWidgets('settings exposes local AI management controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Local AI'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Local AI'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('FunctionGemma 270M'), findsOneWidget);
    expect(find.text('284 MB · Gemma .litertlm'), findsOneWidget);
    expect(find.text('Local server endpoint'), findsOneWidget);

    expect(find.text('Use local model when available'), findsOneWidget);
    expect(find.text('AI search interpretation'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recommendation context items'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Recommendation context items'), findsOneWidget);
    expect(find.text('Import Gemma model'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-recommended-ai-model')),
      findsOneWidget,
    );
    expect(find.text('Current provider'), findsOneWidget);
  });
}

class _FakeMediaService implements MediaService {
  @override
  String get displayName => 'AniList';

  @override
  String get id => 'com.majika.service.anilist';

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) async {
    return [
      MediaItem(
        id: 'anilist_2',
        title: 'Best Match',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 8.5,
        format: 'TV',
        popularity: 50000,
        startYear: DateTime.now().year,
        siteUrl: 'https://anilist.co/anime/2',
      ),
      MediaItem(
        id: 'anilist_3',
        title: 'Another Match',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 8,
        format: 'MOVIE',
        siteUrl: 'https://anilist.co/anime/3',
      ),
      if (includeAdult)
        MediaItem(
          id: 'anilist_4',
          title: 'Adult Match',
          coverUrl: '',
          tags: const ['Romance'],
          rating: 7.8,
          format: 'OVA',
          mediaType: 'ANIME',
          isAdult: true,
          siteUrl: 'https://anilist.co/anime/4',
        ),
    ];
  }

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    return [
      if (query.selectedTags.contains('Time Manipulation'))
        MediaItem(
          id: 'anilist_5',
          title: 'Time Travel Movie',
          coverUrl: '',
          tags: const ['Romance', 'Time Manipulation'],
          rating: 8.4,
          format: 'MOVIE',
          mediaType: 'ANIME',
          siteUrl: 'https://anilist.co/anime/5',
        ),
      ...await fetchRecommendationCandidates(
        includeAdult: query.includeAdult || query.infersAdult,
      ),
    ];
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    return const [
      'Drama',
      'Mystery',
      'Romance',
      'Time Manipulation',
      'Yandere',
    ];
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    return const UserTasteSignals(
      favoriteCharacters: ['Odokawa'],
      favoriteStudios: ['OLM'],
    );
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    return [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen Mystery',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 9,
        format: 'TV',
        status: 'CURRENT',
        updatedAt: 100,
        characters: const ['Odokawa'],
        studios: const ['OLM'],
        siteUrl: 'https://anilist.co/anime/1',
      ),
    ];
  }
}
