import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:majika/core/extensions/extension_runner.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/ui/reader/reader_screen.dart';

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
      // Load the Javascript text from the asset file
      final String extensionCode = await rootBundle.loadString('extensions/anilist_template.js');
      
      // Load it into the QuickJS engine
      await _runner.loadExtension(extensionCode);
      
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
          child: Text('Extension Error: $_error', style: const TextStyle(color: Colors.redAccent)),
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
                            Colors.black.withOpacity(0.9),
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
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  item.rating!.toStringAsFixed(1),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('AniList', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
