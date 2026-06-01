import 'package:firebase_core/firebase_core.dart';
import 'package:majika/firebase_options.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static bool _attempted = false;
  static Object? _lastError;

  static bool get isConfigured => Firebase.apps.isNotEmpty;

  static Object? get lastError => _lastError;

  static Future<bool> initialize() async {
    if (Firebase.apps.isNotEmpty) return true;
    if (_attempted) return Firebase.apps.isNotEmpty;

    _attempted = true;
    if (!DefaultFirebaseOptions.hasRequiredOptions) return false;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    } catch (error) {
      _lastError = error;
      return false;
    }
  }
}
