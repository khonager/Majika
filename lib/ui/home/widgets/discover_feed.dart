import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class DiscoverFeed extends StatelessWidget {
  final ScrollController scrollController;

  const DiscoverFeed({super.key, required this.scrollController});

  // Placeholder data mapping user's drawing of a 2-column image gallery
  final List<String> dummyImages = const [
    'https://picsum.photos/400/600',
    'https://picsum.photos/400/400',
    'https://picsum.photos/400/700',
    'https://picsum.photos/400/500',
    'https://picsum.photos/400/800',
    'https://picsum.photos/400/450',
    'https://picsum.photos/400/650',
    'https://picsum.photos/400/550',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Padding to account for the animated nav bar area at the top
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: MasonryGridView.count(
        controller: scrollController,
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        padding: const EdgeInsets.only(top: 130, bottom: 40), // Room for nav
        itemCount: dummyImages.length,
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Image.network(
                  dummyImages[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // loading builder to prevent layout jumps
                  loadingBuilder: (context, child, p) {
                    if (p == null) return child;
                    return AspectRatio(
                      aspectRatio: index % 2 == 0 ? 0.7 : 0.9,
                      child: Container(color: Colors.white10),
                    );
                  },
                ),
                // Gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        'Item ${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
