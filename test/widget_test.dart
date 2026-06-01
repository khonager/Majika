import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/main.dart';
import 'package:majika/ui/home/home_screen.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('mobile home uses anchored liquid rail and mini player', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    expect(find.byKey(const ValueKey('mobile-liquid-rail')), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-liquid-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-current-activity-glass')),
      findsOneWidget,
    );
    expect(find.text('Seen Mystery'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(find.text('Best Match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile rail settings button opens settings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Tune the reading space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('Steam service switch imports a game profile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), _FakeSteamMediaService()],
        ),
      ),
    );

    await tester.tap(find.byTooltip('Steam'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Steam'), findsOneWidget);
    expect(find.text('Build game profile'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'steamtester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('@Steam Tester · RPG + Strategy'), findsOneWidget);
    expect(find.text('Steam Tester'), findsWidgets);
    expect(find.text('Strategy RPG Match'), findsOneWidget);
    expect(find.byTooltip('Open on Steam'), findsWidgets);
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
    expect(find.text('AI mode'), findsOneWidget);
    expect(find.text('Provider'), findsNothing);
    expect(find.text('FastVLM 0.5B'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
    expect(find.text('Local server endpoint'), findsNothing);
    expect(find.text('Local server model'), findsNothing);

    await tester.tap(find.text('Fallback rules only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic on-device').last);
    await tester.pumpAndSettle();

    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    expect(find.text('586 MB · Balanced public text model'), findsOneWidget);
    expect(find.text('FunctionGemma 270M'), findsNothing);

    expect(find.text('Use local model when available'), findsNothing);
    expect(find.text('AI search interpretation'), findsOneWidget);
    expect(find.text('Advanced model choice'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recommendation context items'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Recommendation context items'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Qwen3 0.6B'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen3 0.6B'));
    await tester.pumpAndSettle();
    expect(find.text('FunctionGemma 270M'), findsOneWidget);
    expect(find.text('DeepSeek R1 Distill Qwen 1.5B'), findsOneWidget);
    expect(find.text('Qwen 2.5 1.5B Instruct'), findsOneWidget);
    expect(find.text('Phi-4 Mini Instruct'), findsOneWidget);
    await tester.tap(find.text('Qwen 2.5 1.5B Instruct').last);
    await tester.pumpAndSettle();
    expect(find.text('1.6 GB · Advanced public text model'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Advanced model choice'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final advancedTile = find.widgetWithText(ListTile, 'Advanced model choice');
    await tester.tap(
      find.descendant(of: advancedTile, matching: find.byType(Switch)).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Import custom model file'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-recommended-ai-model')),
      findsOneWidget,
    );
    expect(find.text('Current AI path'), findsOneWidget);
  });

  testWidgets('settings shows local server fields only for external mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Local AI'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Local server endpoint'), findsNothing);
    await tester.tap(find.text('Fallback rules only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('External local server').last);
    await tester.pumpAndSettle();

    expect(find.text('Local server endpoint'), findsOneWidget);
    expect(find.text('Server model preset'), findsOneWidget);
    expect(find.text('gemma3:4b'), findsWidgets);
    expect(find.text('Local server model'), findsOneWidget);
    expect(find.text('Qwen3 0.6B'), findsNothing);
  });

  testWidgets('settings persists recommendation context items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Recommendation context items'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('24'), findsOneWidget);

    await tester.drag(find.byType(Slider).last, const Offset(300, 0));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final savedContextItems = prefs.getDouble('settings.aiContextItems');
    expect(savedContextItems, isNotNull);
    expect(savedContextItems, isNot(equals(24)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Recommendation context items'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(savedContextItems!.round().toString()), findsOneWidget);
  });

  testWidgets('settings points Steam API key storage to Firebase Functions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Steam key location'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('STEAM_WEB_API_KEY'), findsOneWidget);
    expect(find.byKey(const ValueKey('steam-api-key')), findsNothing);
  });
}

class _FakeMediaService implements MediaService {
  @override
  String get displayName => 'AniList';

  @override
  String get id => 'com.majika.service.anilist';

  @override
  String get connectTitle => 'Connect AniList';

  @override
  String get connectDescription => 'Enter a public AniList username.';

  @override
  String get userNameHint => 'AniList username';

  @override
  String get userNameEmptyMessage => 'Enter an AniList username first.';

  @override
  String get importButtonLabel => 'Build profile';

  @override
  String get searchPlaceholder => 'Search a vibe, tag, format, or request';

  @override
  String get openTooltipLabel => 'Open on AniList';

  @override
  List<String> get supportedMediaTypes => RecommendationQuery.aniListMediaTypes;

  @override
  List<String> get supportedFormats => RecommendationQuery.aniListFormats;

  @override
  bool get supportsAdultContent => true;

  @override
  Future<ServiceUserProfile?> fetchUserProfile(String userName) async {
    return ServiceUserProfile(userName: userName);
  }

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
    final tags = query.effectiveTags(await fetchAvailableTags());
    return [
      if (tags.contains('Time Manipulation'))
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

class _FakeSteamMediaService implements MediaService {
  @override
  String get displayName => 'Steam';

  @override
  String get id => 'com.majika.service.steam';

  @override
  String get connectTitle => 'Connect Steam';

  @override
  String get connectDescription => 'Enter a public Steam profile.';

  @override
  String get userNameHint => 'Steam profile, vanity name, or SteamID64';

  @override
  String get userNameEmptyMessage => 'Enter a Steam profile first.';

  @override
  String get importButtonLabel => 'Build game profile';

  @override
  String get searchPlaceholder => 'Search a genre, mode, game, or vibe';

  @override
  String get openTooltipLabel => 'Open on Steam';

  @override
  List<String> get supportedMediaTypes => RecommendationQuery.steamMediaTypes;

  @override
  List<String> get supportedFormats => RecommendationQuery.steamFormats;

  @override
  bool get supportsAdultContent => false;

  @override
  Future<ServiceUserProfile?> fetchUserProfile(String userName) async {
    return const ServiceUserProfile(
      userName: '76561198000000000',
      displayName: 'Steam Tester',
      avatarUrl: '',
      profileUrl: 'https://steamcommunity.com/id/steamtester',
    );
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    return [
      MediaItem(
        id: 'steam_1',
        title: 'Played RPG',
        coverUrl: '',
        tags: const ['RPG', 'Strategy'],
        rating: 9,
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        status: 'RECENTLY_PLAYED',
        sourceId: id,
        siteUrl: 'https://store.steampowered.com/app/1',
        playtimeMinutes: 6000,
        recentPlaytimeMinutes: 120,
        lastPlayedAt: 200,
      ),
    ];
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    return UserTasteSignals.empty;
  }

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) async {
    return [
      MediaItem(
        id: 'steam_2',
        title: 'Strategy RPG Match',
        coverUrl: '',
        tags: const ['RPG', 'Strategy', 'Single-player'],
        rating: 8.8,
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        sourceId: id,
        siteUrl: 'https://store.steampowered.com/app/2',
        popularity: 90000,
      ),
    ];
  }

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    return fetchRecommendationCandidates();
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    return const ['RPG', 'Strategy', 'Single-player', 'Controller Support'];
  }
}
