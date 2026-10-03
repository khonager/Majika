import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/ui/home/home_screen.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/storage/local_profile_store.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_media_service.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
const _captureDir = String.fromEnvironment(
  'CAPTURE_DIR',
  defaultValue: 'build/ux',
);
const _fontPath = String.fromEnvironment('CAPTURE_FONT');
final _screenKey = GlobalKey();

Future<void> _screenshot(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.pumpAndSettle();
  final boundary =
      _screenKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_captureDir).create(recursive: true);
    await File(
      '$_captureDir/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  testWidgets('phone connect, recommendations and settings flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (_fontPath.isNotEmpty) {
      final bytes = await tester.runAsync(() => File(_fontPath).readAsBytes());
      await (FontLoader(
        'CaptureFont',
      )..addFont(Future.value(ByteData.sublistView(bytes!)))).load();
    }
    if (_capture) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: _fontPath.isEmpty ? null : 'CaptureFont',
            ),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFE7ECEF),
              secondary: Color(0xFF89D6B3),
              surface: Color(0xFF171A20),
            ),
          ),
          home: HomeScreen(
            mediaService: TestMediaService(),
            aiService: const DeterministicLocalAiService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, '01-connect');
    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Build profile'));
    await tester.pumpAndSettle();
    await _screenshot(tester, '02-recommendations');
    await tester.ensureVisible(find.text('Why this pick?').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why this pick?').first);
    await tester.pumpAndSettle();
    expect(find.text('Open on AniList'), findsOneWidget);
    await _screenshot(tester, '03-details');
    await tester.tap(find.text('Save for later').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Best Match'), findsOneWidget);
    await _screenshot(tester, '04-saved');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Hide Best Match'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide Best Match'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Saved'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden picks'));
    await tester.pumpAndSettle();
    await _screenshot(tester, '05-hidden');
    await tester.tap(find.byTooltip('Restore Best Match'));
    await tester.pumpAndSettle();
    expect(find.text('No hidden picks'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _screenshot(tester, '06-settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved and hidden picks survive restarting offline', (
    tester,
  ) async {
    final service = _MutableService();
    await _import(tester, service);
    await tester.ensureVisible(find.text('Save for later').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for later').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide Best Match'));
    await tester.pumpAndSettle();
    expect(find.text('Best Match'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.failLibrary = true;
    await _pumpHome(tester, service);
    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
    expect(find.text('Best Match'), findsNothing);
    expect(service.libraryRequests, 1);
    await tester.tap(find.byTooltip('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Best Match'), findsOneWidget);
    await tester.tap(find.text('Hidden picks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restore Best Match'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Best Match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh keeps the imported library and can retry', (
    tester,
  ) async {
    final service = _MutableService();
    await _import(tester, service);
    service.failLibrary = true;
    await tester.tap(find.byTooltip('Refresh library'));
    await tester.pumpAndSettle();
    expect(find.text('Best Match'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(
      (await const LocalProfileStore().loadSessions())
          .values
          .single
          .profile
          .userName,
      'tester',
    );
    service.failLibrary = false;
    await tester.tap(find.byTooltip('Refresh library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(service.libraryRequests, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional catalog failures do not block library import', (
    tester,
  ) async {
    final service = _MutableService()..failExtras = true;
    await _import(tester, service);
    expect(find.text('@tester · Mystery + Drama'), findsOneWidget);
    expect(find.textContaining('Your library is ready.'), findsOneWidget);
    expect(find.byTooltip('Refresh library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out during refresh ignores late import results', (
    tester,
  ) async {
    final service = _MutableService();
    await _import(tester, service);
    service.pendingLibrary = Completer<List<MediaItem>>();
    await tester.tap(find.byTooltip('Refresh library'));
    await tester.pump();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    service.pendingLibrary!.complete(
      await TestMediaService().fetchUserLibrary('tester'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect AniList'), findsOneWidget);
    expect(find.text('Best Match'), findsNothing);
    expect(await const LocalProfileStore().loadSessions(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'content preference applies to restored recommendations immediately',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.allowExplicitContent: true,
      });
      await _import(tester, TestMediaService());
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Search a vibe, tag, format, or request',
        ),
        'hentai romance ova',
      );
      await tester.tap(find.byTooltip('Search recommendations'));
      await tester.pumpAndSettle();
      expect(find.text('Adult Match'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Adult Match'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('main flow fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHome(tester, TestMediaService(), textScale: 1.8);
      await tester.ensureVisible(find.text('Build profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'tester');
      await tester.ensureVisible(find.text('Build profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save for later').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Keep your next favorite here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  TestMediaService service, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(
        mediaService: service,
        aiService: const DeterministicLocalAiService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _import(WidgetTester tester, TestMediaService service) async {
  await _pumpHome(tester, service);
  await tester.enterText(find.byType(TextField).first, 'tester');
  await tester.tap(find.text('Build profile'));
  await tester.pumpAndSettle();
}

class _MutableService extends TestMediaService {
  bool failLibrary = false;
  bool failExtras = false;
  int libraryRequests = 0;
  Completer<List<MediaItem>>? pendingLibrary;
  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    libraryRequests++;
    if (failLibrary) throw TimeoutException('Offline');
    if (pendingLibrary != null) return pendingLibrary!.future;
    return super.fetchUserLibrary(userName);
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    if (failExtras) throw TimeoutException('Favorites unavailable');
    return super.fetchTasteSignals(userName);
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    if (failExtras) throw TimeoutException('Tags unavailable');
    return super.fetchAvailableTags();
  }
}
