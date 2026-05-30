import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/main.dart';
import 'package:majika/ui/home/home_screen.dart';

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
}

class _FakeMediaService implements MediaService {
  @override
  String get displayName => 'AniList';

  @override
  String get id => 'com.majika.service.anilist';

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates() async {
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
