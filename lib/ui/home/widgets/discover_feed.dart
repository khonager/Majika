import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:majika/core/extensions/extension_runner.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/ui/reader/reader_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';

class DiscoverFeed extends StatefulWidget {
  final ScrollController scrollController;

  const DiscoverFeed({super.key, required this.scrollController});

  @override
  State<DiscoverFeed> createState() => _DiscoverFeedState();
}

class _DiscoverFeedState extends State<DiscoverFeed> {
  final ExtensionRunner _runner = ExtensionRunner();
  List<MediaItem> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAndRunExtension();
  }

  Future<void> _loadAndRunExtension() async {
    try {
      // Load the Lua text from the asset file
      final String extensionCode = await rootBundle.loadString(
        'extensions/anilist_template.lua',
      );

      // Load it into the Lua engine
      _runner.loadExtension(extensionCode);

      // Execute the fetchDiscoverFeed function!
      final items = await _runner.runFetchDiscoverFeed();

      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Colors.redAccent,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'Extension Error: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadAndRunExtension();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_mosaic_rounded,
                color: Colors.white54,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nothing showed up in Discover yet.',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Try reloading the extension feed.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadAndRunExtension();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reload'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      // Padding to account for the animated nav bar area at the top
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: MasonryGridView.count(
        controller: widget.scrollController,
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        padding: const EdgeInsets.only(top: 130, bottom: 40), // Room for nav
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReaderScreen(imageUrl: item.coverUrl),
                  ),
                );
              },
              child: Stack(
                children: [
                  Image.network(
                    item.coverUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (context, child, p) {
                      if (p == null) return child;
                      return AspectRatio(
                        aspectRatio: index % 2 == 0 ? 0.7 : 0.9,
                        child: Container(color: Colors.white10),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return AspectRatio(
                        aspectRatio: index % 2 == 0 ? 0.7 : 0.9,
                        child: Container(
                          color: Colors.white10,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 34,
                          ),
                        ),
                      );
                    },
                  ),
                  // Gradient overlay at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.9),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (item.rating != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Source Pill at top right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => showInfoToast(
                          context,
                          'Loaded from AniList via extension.',
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'AniList',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
