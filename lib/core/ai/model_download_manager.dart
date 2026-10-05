import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/core/ai/device_capacity.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/on_device_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ModelInstaller =
    Future<void> Function(
      DownloadableAiModel model,
      CancelToken cancellation,
      void Function(double) progress,
      String? token,
    );

enum ModelDownloadPhase { idle, downloading, checking, ready, failed, canceled }

/// Owns installation independently of navigation. Only a successful load and
/// generation check activates AI in persisted settings.
class ModelDownloadManager extends ChangeNotifier {
  ModelDownloadManager({
    ModelInstaller? installer,
    Future<void> Function(DownloadableAiModel)? validator,
    Future<DeviceCapacity> Function()? capacityLoader,
    Future<bool> Function(DownloadableAiModel)? restorer,
  }) : _usesNativeRuntime = installer == null,
       _installer = installer ?? _install,
       _validator = validator ?? _validate,
       _restorer = restorer ?? _restoreInstalled,
       _capacityLoader = capacityLoader ?? DeviceCapacity.detect;

  static final instance = ModelDownloadManager();
  static const pendingModelKey = 'ai.pendingModelDownload';
  final bool _usesNativeRuntime;
  final ModelInstaller _installer;
  final Future<bool> Function(DownloadableAiModel) _restorer;
  final Future<void> Function(DownloadableAiModel) _validator;
  final Future<DeviceCapacity> Function() _capacityLoader;
  CancelToken? _cancellation;
  ModelDownloadPhase phase = ModelDownloadPhase.idle;
  DownloadableAiModel? model;
  double? progress;
  String? error;
  bool dismissed = false;
  bool get busy =>
      phase == ModelDownloadPhase.downloading ||
      phase == ModelDownloadPhase.checking;

  String get status => switch (phase) {
    ModelDownloadPhase.downloading =>
      'Downloading ${model?.name} · ${progress == null ? 'starting…' : '${(progress! * 100).round()}%'}',
    ModelDownloadPhase.checking => 'Checking ${model?.name} on this device…',
    ModelDownloadPhase.ready => '${model?.name} is ready to use',
    ModelDownloadPhase.failed => error ?? 'Download failed. Retry in Settings.',
    ModelDownloadPhase.canceled => 'Model download canceled',
    ModelDownloadPhase.idle => '',
  };

  Future<void> restoreInstalledModel() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(LocalAiSettingsKeys.downloadedModelId);
    if (id == null) return;
    final matches = downloadableAiModels.where(
      (m) => m.id == id && m.supportsCurrentPlatform,
    );
    try {
      if (matches.isNotEmpty && await _restorer(matches.first)) return;
    } catch (_) {
      // A removed or incompatible local file should offer Download again.
    }
    await prefs.remove(LocalAiSettingsKeys.downloadedModelId);
    await prefs.remove(LocalAiSettingsKeys.downloadedModelName);
    if (prefs.getString(LocalAiSettingsKeys.localAiMode) ==
        localAiModeOnDevice) {
      await prefs.setBool(LocalAiSettingsKeys.useLocalAi, false);
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeRulesOnly,
      );
    }
    model = matches.isEmpty ? null : matches.first;
    phase = ModelDownloadPhase.failed;
    error =
        'Your downloaded AI could not be restored. Open Settings to download it again.';
    notifyListeners();
  }

  static Future<bool> _restoreInstalled(DownloadableAiModel model) async {
    if (!await FlutterGemma.isModelInstalled(model.storageFileName)) {
      return false;
    }
    // install() re-registers the existing file without a network transfer.
    await FlutterGemma.installModel(
      modelType: model.modelType,
      fileType: model.fileType,
    ).fromNetwork(model.url).install();
    return true;
  }

  Future<void> restorePendingDownload() async {
    if (busy) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(pendingModelKey);
    if (id == null) return;
    final matches = downloadableAiModels.where((m) => m.id == id);
    if (matches.isEmpty) {
      await prefs.remove(pendingModelKey);
      return;
    }
    // Reattach to native work, or retry the interrupted transfer. Hugging Face
    // transfers may restart from zero when byte-range resume is unavailable.
    await download(
      matches.first,
      token: prefs.getString(LocalAiSettingsKeys.huggingFaceToken),
    );
  }

  Future<void> download(DownloadableAiModel next, {String? token}) async {
    if (busy) return;
    final cancellation = CancelToken();
    _cancellation = cancellation;
    model = next;
    phase = ModelDownloadPhase.downloading;
    progress = null;
    error = null;
    dismissed = false;
    notifyListeners();
    SharedPreferences? prefs;
    ModelSpec? previousModel;
    Map<String, Object?>? previousSettings;
    try {
      final capacity = await _capacityLoader().timeout(
        const Duration(seconds: 5),
      );
      final reason = capacity.blockingReason(next);
      if (reason != null) throw StateError(reason);
      if (next.needsHuggingFaceToken &&
          (token == null || token.trim().isEmpty)) {
        throw StateError(
          'This model requires a Hugging Face token. Choose a public model for setup without an account.',
        );
      }
      cancellation.throwIfCancelled();
      prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(pendingModelKey, next.id)) {
        throw StateError('Could not save download progress. Please retry.');
      }
      if (_usesNativeRuntime) {
        await FlutterGemma.initialize(huggingFaceToken: token);
        previousModel =
            FlutterGemmaPlugin.instance.modelManager.activeInferenceModel;
      }
      await _installer(next, cancellation, (value) {
        if (cancellation.isCancelled) return;
        progress = value.clamp(0, 1);
        notifyListeners();
      }, next.needsHuggingFaceToken ? token : null);
      cancellation.throwIfCancelled();
      phase = ModelDownloadPhase.checking;
      progress = 1;
      notifyListeners();
      await _validator(next);
      cancellation.throwIfCancelled();
      final values = <String, Object>{
        LocalAiSettingsKeys.downloadedModelId: next.id,
        LocalAiSettingsKeys.downloadedModelName: next.name,
        LocalAiSettingsKeys.selectedModelId: next.id,
        LocalAiSettingsKeys.selectedModelName: next.name,
        LocalAiSettingsKeys.localAiMode: localAiModeOnDevice,
        LocalAiSettingsKeys.localAiProvider: next.providerLabel,
        LocalAiSettingsKeys.localBackend: localAiBackendCpu,
        LocalAiSettingsKeys.useLocalAi: true,
      };
      previousSettings = {for (final key in values.keys) key: prefs.get(key)};
      for (final entry in values.entries) {
        final saved = entry.value is bool
            ? await prefs.setBool(entry.key, entry.value as bool)
            : await prefs.setString(entry.key, entry.value as String);
        if (!saved) {
          throw StateError(
            'Model installed, but settings could not be saved. Retry to activate it.',
          );
        }
      }
      // Old overrides can exceed the context baked into a newly installed file.
      await prefs.remove(LocalAiSettingsKeys.aiContextWindowTokens);
      await prefs.remove(pendingModelKey);
      phase = ModelDownloadPhase.ready;
    } catch (failure) {
      if (_usesNativeRuntime && previousModel != null) {
        FlutterGemmaPlugin.instance.modelManager.setActiveModel(previousModel);
      }
      if (prefs != null && previousSettings != null) {
        for (final entry in previousSettings.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else {
            await prefs.setString(entry.key, entry.value as String);
          }
        }
      }
      if (cancellation.isCancelled || CancelToken.isCancel(failure)) {
        await prefs?.remove(pendingModelKey);
        phase = ModelDownloadPhase.canceled;
      } else {
        // Persist intent so a process restart can recover an interrupted install.
        // Explicit failures require Retry, avoiding an endless startup retry loop.
        await prefs?.remove(pendingModelKey);
        phase = ModelDownloadPhase.failed;
        error = 'Could not prepare ${next.name}. ${_friendlyError(failure)}';
      }
    } finally {
      _cancellation = null;
      notifyListeners();
    }
  }

  void cancel() {
    if (phase != ModelDownloadPhase.downloading) return;
    _cancellation?.cancel('Canceled by user');
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('401') || message.contains('403')) {
      return 'The model host denied access. Try a public model or check its license access.';
    }
    if (message.contains('404')) {
      return 'The download is no longer available. Choose another model.';
    }
    if (error is TimeoutException) {
      return 'The device check took too long. Try a smaller model.';
    }
    if (message.contains('SocketException') ||
        message.contains('HandshakeException') ||
        message.contains('ClientException') ||
        message.contains('Network error')) {
      return 'Check your connection and retry.';
    }
    return message.replaceFirst('Bad state: ', '');
  }

  static Future<void> _install(
    DownloadableAiModel model,
    CancelToken cancellation,
    void Function(double) progress,
    String? token,
  ) async {
    await FlutterGemma.initialize(huggingFaceToken: token);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final downloader = FileDownloader();
      downloader.configureNotificationForGroup(
        'smart_downloads',
        running: TaskNotification(
          'Downloading ${model.name}',
          '{progress} · Majika AI',
        ),
        complete: TaskNotification(
          '${model.name} downloaded',
          'Open Majika to finish checking the model.',
        ),
        error: const TaskNotification(
          'Model download interrupted',
          'Open Majika to retry.',
        ),
        progressBar: true,
      );
      // Declining notifications does not prevent downloading or in-app progress.
      await downloader.permissions.request(PermissionType.notifications);
    }
    cancellation.throwIfCancelled();
    await FlutterGemma.installModel(
          modelType: model.modelType,
          fileType: model.fileType,
        )
        .fromNetwork(model.url, token: token, foreground: true)
        .withCancelToken(cancellation)
        .withProgress((percent) => progress(percent / 100))
        .install();
  }

  static Future<void> _validate(DownloadableAiModel choice) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.cpu,
    );
    try {
      final chat = await model.createChat(
        temperature: choice.id == 'qwen3_0_6b' ? 0.7 : 0.1,
        topK: choice.id == 'qwen3_0_6b' ? 20 : 1,
        tokenBuffer: 64,
        modelType: choice.modelType,
      );
      await chat.addQueryChunk(
        Message.text(
          text: onDevicePrompt(
            choice.name,
            'Reply with the single word Ready.',
          ),
          isUser: true,
        ),
      );
      final response = await chat.generateChatResponse().timeout(
        const Duration(minutes: 2),
      );
      if (response is! TextResponse || response.token.trim().isEmpty) {
        throw StateError('The model did not return text. Try another model.');
      }
    } finally {
      await model.close();
    }
  }
}
