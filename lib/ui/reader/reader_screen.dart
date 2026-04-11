import 'package:flutter/material.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';

class ReaderScreen extends StatelessWidget {
  final String imageUrl;

  const ReaderScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () => showFeatureComingSoon(context, 'Chapter list'),
            icon: const Icon(Icons.toc_rounded),
          ),
          IconButton(
            onPressed: () => showFeatureComingSoon(context, 'Reader tools'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The Manga / Comic Page Placeholder
          InteractiveViewer(
            // allows pinch to zoom
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(20),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'This page could not be loaded.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Subtle grey semi-transparent page counter at bottom left
          Positioned(
            left: 20,
            bottom: 40,
            child: GlassPanel(
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.black.withValues(alpha: 0.3),
              child: const Text(
                '15 / 75',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 32,
            child: GlassPanel(
              borderRadius: BorderRadius.circular(24),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              color: Colors.black.withValues(alpha: 0.28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: () =>
                        showFeatureComingSoon(context, 'Previous page'),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bookmark page',
                    onPressed: () =>
                        showFeatureComingSoon(context, 'Bookmarks'),
                    icon: const Icon(
                      Icons.bookmark_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: () =>
                        showFeatureComingSoon(context, 'Next page'),
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
