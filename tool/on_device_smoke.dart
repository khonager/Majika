// Run with an isolated application data directory. Downloads a real public
// model and checks native loading/generation using the production installer.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:majika/core/ai/model_download_manager.dart';
import 'package:majika/core/ai/on_device_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final manager = ModelDownloadManager.instance;
  var lastStep = -1;
  manager.addListener(() {
    final step = ((manager.progress ?? 0) * 10).floor();
    if (step != lastStep ||
        !manager.busy ||
        manager.phase == ModelDownloadPhase.checking) {
      debugPrint('MODEL_SETUP ${manager.status}');
      lastStep = step;
    }
  });
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Testing on-device model setup…')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    const id = String.fromEnvironment('MODEL_ID', defaultValue: 'qwen3_0_6b');
    await manager.download(
      downloadableAiModels.firstWhere((model) => model.id == id),
    );
    debugPrint('MODEL_SETUP_RESULT ${manager.phase.name}');
    exit(manager.phase == ModelDownloadPhase.ready ? 0 : 1);
  });
}
