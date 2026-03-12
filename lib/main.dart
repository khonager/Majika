import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:majika/ui/home/home_screen.dart';

void main() {
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
        scaffoldBackgroundColor: const Color(0xFF121418), // Deep, elegant dark
        primaryColor: const Color(0xFF6B4EE6), // Vibrant purple accent
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6B4EE6),
          secondary: Color(0xFF00D2FF), // Neon cyan for secondary touches
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
