import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:majika/core/ai/on_device_models.dart';
import 'package:majika/core/ai/runtime_architecture.dart';

/// Hardware guidance is conservative. Successful model loading is checked
/// separately; RAM alone cannot establish inference speed or answer quality.
class DeviceCapacity {
  final TargetPlatform platform;
  final int? ramMb;
  final int? freeStorageBytes;
  final bool supportedArchitecture;

  const DeviceCapacity({
    required this.platform,
    this.ramMb,
    this.freeStorageBytes,
    this.supportedArchitecture = true,
  });

  static Future<DeviceCapacity> detect() async {
    final platform = defaultTargetPlatform;
    try {
      final info = DeviceInfoPlugin();
      if (platform == TargetPlatform.android) {
        final d = await info.androidInfo;
        return DeviceCapacity(
          platform: platform,
          ramMb: d.physicalRamSize,
          freeStorageBytes: d.freeDiskSize,
          supportedArchitecture: d.supportedAbis.contains('arm64-v8a'),
        );
      }
      if (platform == TargetPlatform.iOS) {
        final d = await info.iosInfo;
        return DeviceCapacity(
          platform: platform,
          ramMb: d.physicalRamSize,
          freeStorageBytes: d.freeDiskSize,
          supportedArchitecture: d.isPhysicalDevice,
        );
      }
      if (platform == TargetPlatform.macOS) {
        final d = await info.macOsInfo;
        return DeviceCapacity(
          platform: platform,
          ramMb: d.memorySize ~/ (1024 * 1024),
          supportedArchitecture: d.arch == 'arm64',
        );
      }
      if (platform == TargetPlatform.windows) {
        final d = await info.windowsInfo;
        return DeviceCapacity(
          platform: platform,
          ramMb: d.systemMemoryInMegabytes,
          supportedArchitecture: supportsBundledAiArchitecture,
        );
      }
      if (platform == TargetPlatform.linux && Platform.isLinux) {
        final raw = await File('/proc/meminfo').readAsString();
        final kb = int.tryParse(
          RegExp(r'MemTotal:\s+(\d+)').firstMatch(raw)?.group(1) ?? '',
        );
        return DeviceCapacity(
          platform: platform,
          ramMb: kb == null ? null : kb ~/ 1024,
          supportedArchitecture: supportsBundledAiArchitecture,
        );
      }
    } catch (_) {
      // Unknown capacity must not be presented as a measured recommendation.
    }
    return DeviceCapacity(platform: platform);
  }

  String? blockingReason(DownloadableAiModel model) {
    if (!supportedArchitecture ||
        !model.supportedPlatforms.contains(platform)) {
      return 'This model is not supported on this device.';
    }
    if (ramMb != null && ramMb! > 0 && ramMb! * 1.1 < model.minimumRamMb) {
      return 'Needs about ${(model.minimumRamMb / 1000).toStringAsFixed(0)} GB RAM. Use rules only on this device.';
    }
    // Leave room for temporary installation files and the rest of the app.
    if (freeStorageBytes != null &&
        freeStorageBytes! < model.downloadBytes * 2) {
      return 'Free about ${(model.downloadBytes * 2 / 1e9).toStringAsFixed(1)} GB of storage before downloading.';
    }
    return null;
  }

  DownloadableAiModel? get recommended {
    final candidates = downloadableAiModels
        .where(
          (m) =>
              !m.needsHuggingFaceToken &&
              !m.isAdvanced &&
              blockingReason(m) == null,
        )
        .toList();
    if (candidates.isEmpty) return null;
    if (ramMb != null && ramMb! >= 5500) {
      for (final m in candidates) {
        if (m.id == 'qwen25_1_5b_instruct') return m;
      }
    }
    candidates.sort((a, b) => a.downloadBytes.compareTo(b.downloadBytes));
    return candidates.first;
  }

  String guidance(DownloadableAiModel model) {
    final blocked = blockingReason(model);
    if (blocked != null) return blocked;
    if (ramMb == null || ramMb! <= 0) {
      return 'Memory could not be checked. Allow at least ${(model.minimumRamMb / 1000).toStringAsFixed(0)} GB RAM and ${(model.downloadBytes * 2 / 1e9).toStringAsFixed(1)} GB free storage.';
    }
    final prefix = recommended?.id == model.id
        ? 'Suggested for this device'
        : 'Fits the memory guidance';
    return '$prefix · ${(ramMb! / 1024).toStringAsFixed(1)} GB RAM detected. Speed varies by device.';
  }
}
