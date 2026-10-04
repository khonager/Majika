import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/device_capacity.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/model_download_manager.dart';
import 'package:majika/core/ai/on_device_models.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/shared/model_download_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final balanced = downloadableAiModels.firstWhere(
    (m) => m.id == 'qwen25_1_5b_instruct',
  );
  const capacity = DeviceCapacity(
    platform: TargetPlatform.android,
    ramMb: 8000,
    freeStorageBytes: 10000000000,
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('public recommendations use platform, RAM and available storage', () {
    expect(capacity.recommended, balanced);
    const modestDesktop = DeviceCapacity(
      platform: TargetPlatform.linux,
      ramMb: 4000,
    );
    expect(modestDesktop.recommended?.id, 'qwen3_0_6b');
    const lowMemory = DeviceCapacity(
      platform: TargetPlatform.android,
      ramMb: 2000,
    );
    expect(lowMemory.recommended, isNull);
    expect(lowMemory.blockingReason(balanced), contains('RAM'));
    const fullDisk = DeviceCapacity(
      platform: TargetPlatform.android,
      ramMb: 8000,
      freeStorageBytes: 500,
    );
    expect(fullDisk.blockingReason(balanced), contains('storage'));
    expect(
      const DeviceCapacity(platform: TargetPlatform.iOS).guidance(balanced),
      contains('could not be checked'),
    );
  });

  test(
    'download activates only after device generation check succeeds',
    () async {
      final downloaded = Completer<void>();
      final checked = Completer<void>();
      late void Function(double) report;
      final manager = ModelDownloadManager(
        capacityLoader: () async => capacity,
        installer: (_, cancellation, progress, token) {
          report = progress;
          return downloaded.future;
        },
        validator: (_) => checked.future,
      );
      final pending = manager.download(balanced);
      await Future<void>.delayed(Duration.zero);
      report(.5);
      expect(manager.progress, .5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LocalAiSettingsKeys.useLocalAi), isNull);
      downloaded.complete();
      await Future<void>.delayed(Duration.zero);
      expect(manager.phase, ModelDownloadPhase.checking);
      expect(prefs.getString(LocalAiSettingsKeys.downloadedModelId), isNull);
      checked.complete();
      await pending;
      expect(manager.phase, ModelDownloadPhase.ready);
      expect(
        prefs.getString(LocalAiSettingsKeys.downloadedModelId),
        balanced.id,
      );
      expect(
        prefs.getString(LocalAiSettingsKeys.localAiMode),
        localAiModeOnDevice,
      );
      expect(prefs.getString(ModelDownloadManager.pendingModelKey), isNull);
      manager.dispose();
    },
  );

  test(
    'cancellation cannot activate a late download and blocks duplicates',
    () async {
      final completed = Completer<void>();
      var installs = 0;
      var checks = 0;
      final manager = ModelDownloadManager(
        capacityLoader: () async => capacity,
        installer: (_, cancellation, progress, token) {
          installs++;
          return completed.future;
        },
        validator: (_) async {
          checks++;
        },
      );
      final pending = manager.download(balanced);
      await Future<void>.delayed(Duration.zero);
      await manager.download(balanced);
      manager.cancel();
      completed.complete();
      await pending;
      expect(installs, 1);
      expect(checks, 0);
      expect(manager.phase, ModelDownloadPhase.canceled);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocalAiSettingsKeys.downloadedModelId), isNull);
      expect(prefs.getString(ModelDownloadManager.pendingModelKey), isNull);
      manager.dispose();
    },
  );

  test(
    'a failed load preserves the previous AI mode and can be retried',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.localAiMode: localAiModeExternalCloud,
      });
      var fail = true;
      final manager = ModelDownloadManager(
        capacityLoader: () async => capacity,
        installer: (_, cancellation, progress, token) async {},
        validator: (_) async {
          if (fail) throw StateError('Not enough memory');
        },
      );
      await manager.download(balanced);
      expect(manager.phase, ModelDownloadPhase.failed);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LocalAiSettingsKeys.localAiMode),
        localAiModeExternalCloud,
      );
      expect(prefs.getString(LocalAiSettingsKeys.downloadedModelId), isNull);
      fail = false;
      await manager.download(balanced);
      expect(manager.phase, ModelDownloadPhase.ready);
      manager.dispose();
    },
  );

  test('relaunch recovers the persisted model installation intent', () async {
    SharedPreferences.setMockInitialValues({
      ModelDownloadManager.pendingModelKey: balanced.id,
    });
    String? installedId;
    final manager = ModelDownloadManager(
      capacityLoader: () async => capacity,
      installer: (m, cancellation, progress, token) async {
        installedId = m.id;
      },
      validator: (_) async {},
    );
    await manager.restorePendingDownload();
    expect(installedId, balanced.id);
    expect(manager.phase, ModelDownloadPhase.ready);
    manager.dispose();
  });

  test(
    'installed model is re-registered on restart without a new transfer',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.downloadedModelId: balanced.id,
        LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
      });
      var restores = 0;
      final manager = ModelDownloadManager(
        restorer: (model) async {
          restores++;
          expect(model.id, balanced.id);
          return true;
        },
        installer: (_, cancellation, progress, token) async {
          fail('Must not download');
        },
      );
      await manager.restoreInstalledModel();
      expect(restores, 1);
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalAiSettingsKeys.downloadedModelId,
        ),
        balanced.id,
      );
      manager.dispose();
    },
  );

  test(
    'a missing installed file offers download again without erasing cloud setup',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.downloadedModelId: balanced.id,
        LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
        LocalAiSettingsKeys.cloudApiKey: 'retained-key',
      });
      final manager = ModelDownloadManager(restorer: (_) async => false);
      await manager.restoreInstalledModel();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocalAiSettingsKeys.downloadedModelId), isNull);
      expect(
        prefs.getString(LocalAiSettingsKeys.localAiMode),
        localAiModeRulesOnly,
      );
      expect(prefs.getString(LocalAiSettingsKeys.cloudApiKey), 'retained-key');
      expect(manager.phase, ModelDownloadPhase.failed);
      manager.dispose();
    },
  );

  test(
    'on-device mode does not use a stored cloud key without opting in',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
        LocalAiSettingsKeys.cloudApiKey: 'existing-key',
      });
      expect((await LocalAiRuntimeSettings.load()).hasCloudFallback, isFalse);
      await (await SharedPreferences.getInstance()).setBool(
        LocalAiSettingsKeys.allowCloudFallback,
        true,
      );
      expect((await LocalAiRuntimeSettings.load()).hasCloudFallback, isTrue);
    },
  );

  test(
    'old Gemini preferences migrate while custom endpoints retain model IDs',
    () async {
      for (final old in ['gemini-2.5-flash-lite', 'gemini-3.1-flash-lite']) {
        SharedPreferences.setMockInitialValues({
          LocalAiSettingsKeys.cloudModel: old,
        });
        final settings = await LocalAiRuntimeSettings.load();
        expect(settings.cloudModel, 'gemini-3.5-flash-lite');
        expect(
          (await SharedPreferences.getInstance()).getString(
            LocalAiSettingsKeys.cloudModel,
          ),
          settings.cloudModel,
        );
      }
      expect(
        normalizedFreeCloudAiModel(
          provider: 'Custom OpenAI-compatible',
          model: 'my-model',
        ),
        'my-model',
      );
      final failure = AiProviderException.fromResponse(
        http.Response('[{"error":{"message":"model retired"}}]', 404),
        provider: 'Google Gemini',
        model: defaultCloudAiModel,
      );
      expect(failure.toString(), contains('Choose a current cloud model'));
      expect(failure.toString(), isNot(contains('Bad state')));
    },
  );

  testWidgets(
    'download survives closing settings and reports ready across routes',
    (tester) async {
      final completed = Completer<void>();
      final manager = ModelDownloadManager(
        capacityLoader: () async => capacity,
        installer: (_, cancellation, progress, token) async {
          progress(.4);
          await completed.future;
        },
        validator: (_) async {},
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          builder: (context, child) =>
              ModelDownloadNotice(manager: manager, child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            downloadManager: manager,
            deviceCapacity: capacity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final download = find.byKey(
        const ValueKey('download-recommended-ai-model'),
      );
      await tester.scrollUntilVisible(
        download,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(download);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(manager.busy, isTrue);
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.textContaining('40%'), findsOneWidget);
      completed.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('is ready to use'), findsOneWidget);
      expect(
        (await LocalAiRuntimeSettings.load()).deviceModelName,
        balanced.name,
      );
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
    },
  );
}
