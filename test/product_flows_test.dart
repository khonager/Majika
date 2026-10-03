import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/ui/home/home_screen.dart';
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _screenshot(tester, '03-settings');
    expect(tester.takeException(), isNull);
  });
}
