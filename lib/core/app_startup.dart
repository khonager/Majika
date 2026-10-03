import 'package:flutter/foundation.dart';

/// Optional integrations initialize together with a bounded wait. The local
/// app remains usable when an integration fails or the device is offline.
Future<void> initializeOptionalServices(
  List<Future<void> Function()> initializers, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await Future.wait(
    initializers.map((initialize) async {
      try {
        await Future<void>.sync(initialize).timeout(timeout);
      } catch (error) {
        debugPrint('Optional service unavailable: ${error.runtimeType}');
      }
    }),
  );
}
