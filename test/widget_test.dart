import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
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
    expect(find.text('Model path'), findsOneWidget);
    expect(find.text('Local server endpoint'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('local-ai-model-path')),
      '/tmp/gemma-4-e2b-it.litertlm',
    );
    await tester.pumpAndSettle();

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
      ),
      MediaItem(
        id: 'anilist_3',
        title: 'Another Match',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 8,
        format: 'MOVIE',
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
      ),
    ];
  }
}
