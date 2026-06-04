import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/main.dart';
import 'package:majika/ui/home/home_screen.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
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
        expect(find.textContaining('A distinct mystery drama'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('failed import handles parallel service errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FailingImportMediaService())),
    );

    await tester.enterText(find.byType(TextField), 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('FormatException: sign in first'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit-content permission waits for an adult request', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.allowExplicitContent: true,
    });
    final service = _TrackingAdultMediaService();

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: service)),
    );
    await tester.enterText(find.byType(TextField), 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.includeAdultRequests, isNot(contains(true)));
    expect(find.byKey(const ValueKey('filter-adult')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('mobile rail stays within short viewports', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), _FakeSteamMediaService()],
          mediaService: _FakeMediaService(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-liquid-rail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search request and chips refill recommendations', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.allowExplicitContent: true,
    });
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

    await tester.tap(find.byKey(const ValueKey('filter-format-manga')));
    await tester.pumpAndSettle();

    expect(find.text('Adult Match'), findsNothing);
    expect(find.textContaining('No matches'), findsOneWidget);
  });

  testWidgets('AniList exposes broad content format filters', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pumpAndSettle();

    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(find.text('Manga'), findsWidgets);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Type'), findsNothing);
    expect(find.byKey(const ValueKey('filter-type-anime')), findsNothing);
    expect(find.byKey(const ValueKey('filter-adult')), findsNothing);
    expect(find.text('OVA'), findsNothing);
    expect(find.text('ONA'), findsNothing);
    expect(find.text('Special'), findsNothing);
  });

  testWidgets('hidden explicit content overrides an adult search', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.allowExplicitContent: false,
    });
    final service = _TrackingAdultMediaService();

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: service)),
    );
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'hentai romance ova',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pumpAndSettle();

    expect(service.includeAdultRequests, isNot(contains(true)));
    expect(find.text('Adult Match'), findsNothing);
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
    expect(find.textContaining('time travel changes'), findsOneWidget);
    expect(find.text('Romance'), findsWidgets);
    expect(find.text('Time Manipulation'), findsWidgets);
  });

  testWidgets('direct AI pick can resolve a title outside fetched candidates', (
    WidgetTester tester,
  ) async {
    final mediaService = _DirectPickMediaService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaService: mediaService,
          aiService: const _DirectSuggestionAiService(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'find a deeply personal mystery recommendation',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(mediaService.searchRequests, contains('AI Outside Pick'));
    await tester.scrollUntilVisible(
      find.text('AI Outside Pick'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('AI Outside Pick'), findsOneWidget);
    expect(find.text('AI recommendation'), findsOneWidget);
    expect(
      find.text('A personal recommendation beyond the fetched tag results.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid direct AI pick falls back to ranked recommendations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaService: _FakeMediaService(),
          aiService: const _InvalidDirectSuggestionAiService(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'anime recommendation for beginners',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pumpAndSettle();

    expect(find.text('Best Match'), findsOneWidget);
    expect(find.textContaining('No matches'), findsNothing);
  });

  testWidgets('manual AI mode prompts for pasted search responses', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeManual,
      LocalAiSettingsKeys.useLocalAi: true,
    });

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
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Manual AI response'), findsOneWidget);
    expect(find.textContaining('Return JSON only'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('manual-ai-response')), '''
{"tags":["Romance","Time Manipulation"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"romance movie"}
''');
    await tester.tap(find.text('Use response'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Manual AI response'), findsOneWidget);
    expect(
      find.textContaining('Personally recommend exactly one real anime'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-ai-response')),
      '{"title":"Time Travel Movie","reason":"Manual pick."}',
    );
    await tester.tap(find.text('Use response'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Time Travel Movie'), findsOneWidget);
    expect(find.text('Manual pick.'), findsOneWidget);
  });

  testWidgets('unsent recommendation search edits survive rebuilds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    final searchField = find.widgetWithText(
      TextField,
      'Search a vibe, tag, format, or request',
    );
    await tester.enterText(searchField, 'romance movie about time travel');
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'unsent draft');
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );
    await tester.pump();

    expect(find.text('unsent draft'), findsOneWidget);
    expect(find.text('romance movie about time travel'), findsNothing);
  });

  testWidgets('Steam controller language selects controller mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeSteamMediaService())),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a genre, mode, game, or vibe'),
      'fun game to play with two players on one pc with controllers',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    final controllerChip = tester.widget<FilterChip>(
      find.descendant(
        of: find.byKey(const ValueKey('filter-format-controller')),
        matching: find.byType(FilterChip),
      ),
    );
    expect(controllerChip.selected, isTrue);
    expect(find.text('Couch Co-op Controller Game'), findsOneWidget);
    expect(find.text('Funny PC Game'), findsNothing);
  });

  testWidgets('cancelled recommendation search ignores late results', (
    WidgetTester tester,
  ) async {
    final service = _SlowSearchMediaService();
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: service)),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a vibe, tag, format, or request'),
      'slow search',
    );
    await tester.tap(find.byTooltip('Search recommendations'));
    await tester.pump();

    expect(find.byTooltip('Cancel recommendation search'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel recommendation search'));
    await tester.pump();

    service.completeSearch();
    await tester.pumpAndSettle();

    expect(find.text('Canceled Search Result'), findsNothing);
    expect(find.byTooltip('Search recommendations'), findsOneWidget);
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

  testWidgets('service switching keeps imported profiles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), _FakeSteamMediaService()],
        ),
      ),
    );

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);

    await tester.tap(find.byTooltip('Steam'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'steamtester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('@Steam Tester · RPG + Strategy'), findsOneWidget);

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();

    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
    expect(find.text('Best Match'), findsOneWidget);
  });

  testWidgets('saved profile restores after HomeScreen restart', (
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(mediaService: _FakeMediaService())),
    );
    await tester.pumpAndSettle();

    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
    expect(find.text('Best Match'), findsOneWidget);
  });

  testWidgets('home aggregates services and AI-style query prefers PC games', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), _FakeSteamMediaService()],
        ),
      ),
    );

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Steam'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'steamtester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();

    expect(
      find.text('One local feed across your imported services.'),
      findsOneWidget,
    );
    expect(find.text('Best Match'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Strategy RPG Match'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Strategy RPG Match'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-recommendation-query')),
      -350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('home-recommendation-query')),
      'I want something entertaining where I can laugh a lot and do it on my PC',
    );
    await tester.tap(find.byTooltip('Search Home recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Funny PC Game'), findsWidgets);
  });

  testWidgets('direct Home AI pick resolves through its chosen service', (
    WidgetTester tester,
  ) async {
    final steamService = _DirectPickSteamMediaService();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), steamService],
          aiService: const _DirectHomeSuggestionAiService(),
        ),
      ),
    );

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Steam'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'steamtester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('home-recommendation-query')),
      'find a game from outside the usual results',
    );
    await tester.tap(find.byTooltip('Search Home recommendations'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(steamService.searchRequests, contains('AI Outside Steam Pick'));
    await tester.scrollUntilVisible(
      find.text('AI Outside Steam Pick'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('AI Outside Steam Pick'), findsWidgets);
    expect(find.text('Direct cross-service personal pick.'), findsWidgets);
  });

  testWidgets('sign out clears only the active saved service', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          mediaServices: [_FakeMediaService(), _FakeSteamMediaService()],
        ),
      ),
    );

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Steam'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'steamtester');
    await tester.tap(find.text('Build game profile'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Steam'), findsOneWidget);

    await tester.tap(find.byTooltip('AniList'));
    await tester.pumpAndSettle();

    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
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
    expect(find.text('Hugging Face token'), findsNothing);
    expect(find.text('Resolved AI context window'), findsOneWidget);
    expect(find.text('Local server endpoint'), findsNothing);
    expect(find.text('Local server model'), findsNothing);

    await tester.tap(find.text('Fallback rules only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic on-device').last);
    await tester.pumpAndSettle();

    expect(find.text('Gemma 3n E2B IT'), findsOneWidget);
    expect(
      find.text(
        '3.1 GB · Benchmark candidate · Advanced Google multimodal model',
      ),
      findsOneWidget,
    );
    expect(find.text('FunctionGemma 270M'), findsNothing);
    expect(find.text('Hugging Face token'), findsOneWidget);
    expect(find.byKey(const ValueKey('hugging-face-token')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hugging-face-access-model')),
      findsOneWidget,
    );

    expect(find.text('Use local model when available'), findsNothing);
    expect(find.text('AI search interpretation'), findsOneWidget);
    expect(find.text('Advanced model choice'), findsOneWidget);
    expect(find.text('On-device backend'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('AI context window override'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('AI context window override'), findsOneWidget);
    expect(find.text('Resolved AI context window'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Gemma 3n E2B IT'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemma 3n E2B IT'));
    await tester.pumpAndSettle();
    expect(find.text('Gemma 3 1B IT'), findsOneWidget);
    expect(find.text('Gemma 3n E4B IT'), findsOneWidget);
    expect(find.text('DeepSeek R1 Distill Qwen 1.5B'), findsNothing);
    expect(find.text('Qwen 2.5 1.5B Instruct'), findsNothing);
    await tester.tap(find.text('Gemma 3n E2B IT').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        '3.1 GB · Benchmark candidate · Advanced Google multimodal model',
      ),
      findsOneWidget,
    );
    expect(find.text('Hugging Face token'), findsOneWidget);
    expect(
      find.textContaining('Before downloading Gemma 3n E2B IT'),
      findsOneWidget,
    );

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

  testWidgets('settings local model card fits on phone widths', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
      LocalAiSettingsKeys.useLocalAi: true,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('AI mode'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Gemma 3n E2B IT'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-recommended-ai-model')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings shows delete control for downloaded local model', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeRulesOnly,
      LocalAiSettingsKeys.useLocalAi: false,
      LocalAiSettingsKeys.selectedModelId: 'gemma3_1b_it',
      LocalAiSettingsKeys.selectedModelName: 'Gemma 3 1B IT',
      LocalAiSettingsKeys.downloadedModelId: 'gemma3_1b_it',
      LocalAiSettingsKeys.downloadedModelName: 'Gemma 3 1B IT',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('AI mode'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Downloaded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('delete-downloaded-ai-model')),
      findsOneWidget,
    );
  });

  testWidgets('settings persists Hugging Face token locally', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Local AI'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fallback rules only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic on-device').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('hugging-face-token')),
      'hf_test_token',
    );
    await tester.pump(const Duration(milliseconds: 800));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(LocalAiSettingsKeys.huggingFaceToken),
      'hf_test_token',
    );
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
    expect(find.text('qwen3:4b-instruct'), findsWidgets);
    expect(find.text(defaultLocalAiEndpoint), findsWidgets);
    expect(find.text('Local server model'), findsOneWidget);
    expect(find.text('Serve a local model'), findsOneWidget);
    expect(find.textContaining('flm serve llama3.2:1b'), findsOneWidget);
    expect(find.text('Gemma 3 1B IT'), findsNothing);
  });

  testWidgets('settings can switch external server defaults to FastFlowLM', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeExternalServer,
      LocalAiSettingsKeys.useLocalAi: true,
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Serve a local model'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Use FastFlowLM settings'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(LocalAiSettingsKeys.localEndpoint),
      'http://127.0.0.1:52625/v1/chat/completions',
    );
    expect(
      prefs.getString(LocalAiSettingsKeys.localServerModel),
      'llama3.2:1b',
    );
    expect(
      find.text('http://127.0.0.1:52625/v1/chat/completions'),
      findsOneWidget,
    );
    expect(find.text('llama3.2:1b'), findsWidgets);
  });

  testWidgets('settings keeps a custom local server endpoint', (
    WidgetTester tester,
  ) async {
    const customEndpoint = 'http://127.0.0.1:52625/v1/chat/completions';
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeExternalServer,
      LocalAiSettingsKeys.useLocalAi: true,
      LocalAiSettingsKeys.localEndpoint: customEndpoint,
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Local AI'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final endpointFinder = find.byKey(const ValueKey('local-ai-endpoint'));
    expect(endpointFinder, findsOneWidget);
    expect(find.text(customEndpoint), findsOneWidget);

    const changedEndpoint = 'http://192.168.1.8:8080';
    await tester.enterText(endpointFinder, changedEndpoint);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalAiSettingsKeys.localEndpoint), changedEndpoint);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Local AI'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(changedEndpoint), findsOneWidget);
  });

  testWidgets('settings can configure cloud AI providers', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalAiSettingsKeys.localAiMode: localAiModeExternalCloud,
      LocalAiSettingsKeys.useLocalAi: true,
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Cloud AI provider'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cloud API key'), findsOneWidget);
    expect(find.text('Google Gemini · gemini-3.1-flash-lite'), findsOneWidget);
    expect(find.text('Cloud endpoint'), findsOneWidget);
    expect(find.text('Cloud model'), findsOneWidget);
    expect(find.textContaining('Cloud privacy note'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('cloud-ai-api-key')),
      'gemini_test_key',
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalAiSettingsKeys.cloudApiKey), 'gemini_test_key');

    await tester.tap(find.text('Google Gemini · gemini-3.1-flash-lite'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('OpenRouter · meta-llama/llama-3.2-3b-instruct:free').last,
    );
    await tester.pumpAndSettle();

    expect(prefs.getString(LocalAiSettingsKeys.cloudAiProvider), 'OpenRouter');
    expect(
      prefs.getString(LocalAiSettingsKeys.cloudEndpoint),
      'https://openrouter.ai/api/v1',
    );
    expect(
      prefs.getString(LocalAiSettingsKeys.cloudModel),
      'meta-llama/llama-3.2-3b-instruct:free',
    );
  });

  testWidgets('settings can select manual copy paste AI mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('AI mode'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fallback rules only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual copy/paste').last);
    await tester.pumpAndSettle();

    expect(find.text('Manual AI prompt handoff'), findsOneWidget);
    expect(
      find.textContaining('Paste it into ChatGPT or another AI'),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalAiSettingsKeys.localAiMode), localAiModeManual);
    expect(prefs.getBool(LocalAiSettingsKeys.useLocalAi), isTrue);
  });

  testWidgets('progress toast expands logs and copies prompt response text', (
    WidgetTester tester,
  ) async {
    final log = AiConsoleLog();
    late AppProgressToast toast;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  toast = showProgressToast(
                    context,
                    'AI loading...',
                    consoleLog: log,
                  );
                  log.addSection('Prompt', 'Prompt body');
                  toast.update('Waiting for model...');
                  log.addSection('Response', 'Response body');
                },
                child: const Text('Start toast'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start toast'));
    await tester.pump(const Duration(milliseconds: 250));

    final toastFinder = find.byKey(const ValueKey('app-progress-toast'));
    expect(toastFinder, findsOneWidget);
    expect(find.text('Prompt body'), findsNothing);

    await tester.tap(toastFinder);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Prompt body'), findsOneWidget);
    expect(find.textContaining('Response body'), findsOneWidget);

    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final data = methodCall.arguments as Map<dynamic, dynamic>;
          copiedText = data['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final copyButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Copy AI log',
      ),
    );
    copyButton.onPressed?.call();
    await tester.pump(const Duration(milliseconds: 250));
    expect(copiedText, contains('Prompt body'));
    expect(copiedText, contains('Response body'));

    toast.dismiss();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('AI log complete. Swipe to dismiss.'), findsOneWidget);

    toast.forceDismiss();
    await tester.pump(const Duration(milliseconds: 250));
    expect(toastFinder, findsNothing);
  });

  testWidgets('settings supports downloadable on-device AI on Linux', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
        LocalAiSettingsKeys.useLocalAi: true,
      });

      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

      await tester.scrollUntilVisible(
        find.text('Local AI'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Automatic on-device'), findsWidgets);
      expect(find.text('Gemma 3n E2B IT'), findsOneWidget);
      expect(find.text('Gemma 3 1B IT'), findsNothing);

      await tester.tap(find.text('Gemma 3n E2B IT'));
      await tester.pumpAndSettle();

      expect(find.text('Gemma 3 1B IT'), findsOneWidget);
      expect(find.text('Gemma 3n E4B IT'), findsOneWidget);
      expect(find.text('Qwen3 0.6B'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('settings persists AI context window override', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AI context window override'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-context-window-tokens')),
      '32768',
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(LocalAiSettingsKeys.aiContextWindowTokens), 32768);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AI context window override'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ai-context-window-tokens')),
          )
          .controller
          ?.text,
      '32768',
    );
    expect(find.textContaining('32K tokens'), findsOneWidget);
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
        description: 'A distinct mystery drama about one tense case.',
      ),
      MediaItem(
        id: 'anilist_3',
        title: 'Another Match',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 8,
        format: 'MOVIE',
        siteUrl: 'https://anilist.co/anime/3',
        description: 'A separate movie mystery with its own premise.',
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
          description:
              'A romance movie where time travel changes the relationship.',
        ),
      ...await fetchRecommendationCandidates(includeAdult: query.allowsAdult),
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

class _FailingImportMediaService extends _FakeMediaService {
  @override
  Future<ServiceUserProfile?> fetchUserProfile(String userName) async {
    await Future<void>.delayed(Duration.zero);
    throw const FormatException('sign in first');
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    await Future<void>.delayed(Duration.zero);
    throw const FormatException('sign in first');
  }
}

class _DirectPickMediaService extends _FakeMediaService {
  final List<String> searchRequests = [];

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    searchRequests.add(query.request);
    if (query.request == 'AI Outside Pick') {
      return [
        MediaItem(
          id: 'anilist_direct_pick',
          title: 'AI Outside Pick',
          coverUrl: '',
          tags: const ['Mystery', 'Psychological'],
          rating: 8.9,
          format: 'TV',
          mediaType: 'ANIME',
          siteUrl: 'https://anilist.co/anime/direct-pick',
          description: 'A unique resolved title absent from the fetched pool.',
        ),
      ];
    }
    return super.searchRecommendationCandidates(query);
  }
}

class _DirectSuggestionAiService extends DeterministicLocalAiService {
  const _DirectSuggestionAiService();

  @override
  Future<AiRecommendationSuggestion?> suggestRecommendation(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    if (!query.isActive) return null;
    return const AiRecommendationSuggestion(
      title: 'AI Outside Pick',
      serviceName: 'AniList',
      reason: 'A personal recommendation beyond the fetched tag results.',
    );
  }
}

class _InvalidDirectSuggestionAiService extends DeterministicLocalAiService {
  const _InvalidDirectSuggestionAiService();

  @override
  Future<AiRecommendationSuggestion?> suggestRecommendation(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    return const AiRecommendationSuggestion(
      title: 'Anya for Animals',
      serviceName: 'AniList',
      reason: 'A made-up title should not erase valid ranked results.',
    );
  }
}

class _DirectHomeSuggestionAiService extends DeterministicLocalAiService {
  const _DirectHomeSuggestionAiService();

  @override
  Future<AiRecommendationSuggestion?> suggestHomeRecommendation(
    List<TasteProfile> profiles,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    if (!query.isActive) return null;
    return const AiRecommendationSuggestion(
      title: 'AI Outside Steam Pick',
      serviceName: 'Steam',
      reason: 'Direct cross-service personal pick.',
    );
  }
}

class _TrackingAdultMediaService extends _FakeMediaService {
  final List<bool> includeAdultRequests = [];

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) {
    includeAdultRequests.add(includeAdult);
    return super.fetchRecommendationCandidates(includeAdult: includeAdult);
  }
}

class _SlowSearchMediaService extends _FakeMediaService {
  final Completer<List<MediaItem>> _searchCompleter = Completer();

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) {
    return _searchCompleter.future;
  }

  void completeSearch() {
    if (_searchCompleter.isCompleted) return;
    _searchCompleter.complete([
      MediaItem(
        id: 'anilist_cancelled',
        title: 'Canceled Search Result',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 10,
        format: 'TV',
        mediaType: 'ANIME',
        siteUrl: 'https://anilist.co/anime/cancelled',
      ),
    ]);
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
    final tags = query.effectiveTags(await fetchAvailableTags());
    final formats = query.effectiveFormats();
    return [
      if (formats.contains('CO_OP') && formats.contains('CONTROLLER'))
        MediaItem(
          id: 'steam_4',
          title: 'Couch Co-op Controller Game',
          coverUrl: '',
          tags: const [
            'Action',
            'Co-op',
            'Shared/Split Screen Co-op',
            'Controller Support',
          ],
          rating: 8.6,
          format: 'CO_OP',
          mediaType: 'GAME',
          sourceId: id,
          siteUrl: 'https://store.steampowered.com/app/4',
          popularity: 50000,
        ),
      if (tags.contains('Comedy') ||
          query.effectiveMediaTypes().contains('GAME'))
        MediaItem(
          id: 'steam_3',
          title: 'Funny PC Game',
          coverUrl: '',
          tags: const ['Comedy', 'Single-player'],
          rating: 8.5,
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: id,
          siteUrl: 'https://store.steampowered.com/app/3',
          popularity: 70000,
        ),
      ...await fetchRecommendationCandidates(),
    ];
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    return const [
      'Comedy',
      'RPG',
      'Strategy',
      'Single-player',
      'Co-op',
      'Controller Support',
    ];
  }
}

class _DirectPickSteamMediaService extends _FakeSteamMediaService {
  final List<String> searchRequests = [];

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    searchRequests.add(query.request);
    if (query.request == 'AI Outside Steam Pick') {
      return [
        MediaItem(
          id: 'steam_direct_pick',
          title: 'AI Outside Steam Pick',
          coverUrl: '',
          tags: const ['RPG', 'Strategy'],
          rating: 9,
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: id,
          siteUrl: 'https://store.steampowered.com/app/direct-pick',
          description: 'A resolved Steam title absent from the fetched pool.',
        ),
      ];
    }
    return super.searchRecommendationCandidates(query);
  }
}
