import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:majika/core/firebase/firebase_bootstrap.dart';
import 'package:majika/core/app_startup.dart';
import 'package:majika/core/ai/model_download_manager.dart';
import 'package:majika/ui/shared/model_download_notice.dart';
import 'package:majika/ui/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final initialization = initializeOptionalServices([
    () async {
      await FirebaseBootstrap.initialize();
    },
    () async {
      await FlutterGemma.initialize();
      await ModelDownloadManager.instance.restoreInstalledModel();
    },
  ]);
  unawaited(
    initialization
        .then((_) => ModelDownloadManager.instance.restorePendingDownload())
        .catchError((Object error) {
          debugPrint('Model recovery unavailable: ${error.runtimeType}');
        }),
  );
  runApp(MajikaApp(initialization: initialization));
}

class MajikaApp extends StatelessWidget {
  final Future<void>? initialization;
  const MajikaApp({super.key, this.initialization});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Majika',
      builder: (context, child) => ModelDownloadNotice(child: child!),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFFB9C4C9),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE7ECEF),
          secondary: Color(0xFF89D6B3),
          surface: Color(0xFF171A20),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: FutureBuilder<void>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Majika',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    CircularProgressIndicator(
                      semanticsLabel: 'Starting Majika',
                    ),
                    SizedBox(height: 16),
                    Text('Getting your space ready…'),
                  ],
                ),
              ),
            );
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
