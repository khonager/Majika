import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/app_startup.dart';
import 'package:majika/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('startup paints while integrations load and survives a failure', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final slow = Completer<void>();
    var secondStarted = false;
    final initialization = initializeOptionalServices([
      () => slow.future,
      () async {
        secondStarted = true;
        throw StateError('Unavailable');
      },
    ], timeout: const Duration(seconds: 2));
    await tester.pumpWidget(MajikaApp(initialization: initialization));
    expect(secondStarted, isTrue);
    expect(find.text('Getting your space ready…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Connect AniList'), findsOneWidget);
    slow.completeError(StateError('Late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
