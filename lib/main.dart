import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:majika/core/firebase/firebase_bootstrap.dart';
import 'package:majika/ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  await FlutterGemma.initialize();
  runApp(const MajikaApp());
}

class MajikaApp extends StatelessWidget {
  const MajikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Majika',
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
      home: const HomeScreen(),
    );
  }
}
