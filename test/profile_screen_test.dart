import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/firebase/firebase_profile_service.dart';
import 'package:majika/ui/profile/profile_screen.dart';

void main() {
  testWidgets(
    'profile edits survive rebuilds and repeated auth notifications',
    (tester) async {
      final service = _ProfileService();
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(service: service)),
      );
      await tester.pumpAndSettle();
      service.changes.add(_user);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Display name'),
        'Edited name',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Steam profile URL, vanity name, or SteamID64',
        ),
        'newsteam',
      );
      service.changes.add(_user);
      await tester.pumpAndSettle();
      expect(find.text('Edited name'), findsOneWidget);
      expect(find.text('newsteam'), findsOneWidget);
      expect(service.fetches, 1);
      await tester.ensureVisible(find.text('Save profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(service.savedName, 'Edited name');
      expect(service.savedSteam, 'newsteam');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await service.changes.close();
    },
  );

  testWidgets('profile fetch failure is visible and can be retried', (
    tester,
  ) async {
    final service = _ProfileService()..failFetch = true;
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(service: service)));
    await tester.pumpAndSettle();
    service.changes.add(_user);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your profile'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save profile'),
    );
    expect(save.onPressed, isNull);
    service.failFetch = false;
    await tester.ensureVisible(find.text('Retry profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your profile'), findsNothing);
    expect(service.fetches, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await service.changes.close();
  });

  testWidgets('account form fits a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _ProfileService();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: ProfileScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Create one instead'), 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await service.changes.close();
  });
}

const _user = AppAuthUser(
  uid: 'test',
  email: 'test@example.com',
  displayName: 'Tester',
);

class _ProfileService extends FirebaseProfileService {
  final changes = StreamController<AppAuthUser?>.broadcast();
  int fetches = 0;
  bool failFetch = false;
  String? savedName;
  String? savedSteam;
  @override
  bool get isConfigured => true;
  @override
  Stream<AppAuthUser?> authStateChanges() async* {
    yield null;
    yield* changes.stream;
  }

  @override
  Future<AppUserProfile?> fetchProfile() async {
    fetches++;
    if (failFetch) throw StateError('Offline');
    return AppUserProfile(
      uid: 'test',
      email: 'test@example.com',
      displayName: savedName ?? 'Tester',
      steamProfile: savedSteam ?? 'oldsteam',
    );
  }

  @override
  Future<void> saveProfile({
    required String displayName,
    String? steamProfile,
  }) async {
    savedName = displayName;
    savedSteam = steamProfile;
    changes.add(_user);
  }
}
