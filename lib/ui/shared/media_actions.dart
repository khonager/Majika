import 'package:flutter/material.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/storage/media_library.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:url_launcher/url_launcher.dart';

class MediaLibraryScope extends InheritedNotifier<MediaLibrary> {
  const MediaLibraryScope({
    super.key,
    required MediaLibrary library,
    required super.child,
  }) : super(notifier: library);

  static MediaLibrary of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MediaLibraryScope>()!
      .notifier!;
}

Future<void> openMediaPage(BuildContext context, MediaItem item) async {
  final url = item.siteUrl.isNotEmpty
      ? item.siteUrl
      : item.id.startsWith('anilist_')
      ? 'https://anilist.co/${item.mediaType.toLowerCase()}/${item.id.substring(8)}'
      : item.id.startsWith('steam_')
      ? 'https://store.steampowered.com/app/${item.id.substring(6)}'
      : '';
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    showErrorToast(
      context,
      'No ${item.serviceLabel} page is available for this item.',
    );
    return;
  }
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted)
      showErrorToast(
        context,
        'Could not open ${item.serviceLabel}. Please try again.',
      );
  } catch (_) {
    if (context.mounted)
      showErrorToast(
        context,
        'Could not open ${item.serviceLabel}. Please try again.',
      );
  }
}

Future<void> _save(
  BuildContext context,
  MediaLibrary library,
  MediaItem item,
) async {
  try {
    await library.toggleSaved(item);
    if (context.mounted)
      showInfoToast(
        context,
        library.isSaved(item)
            ? 'Saved for later on this device.'
            : 'Removed from saved items.',
      );
  } catch (_) {
    if (context.mounted)
      showErrorToast(context, 'Could not save this change. Please try again.');
  }
}

Future<void> _hide(
  BuildContext context,
  MediaLibrary library,
  MediaItem item,
  bool hidden,
) async {
  try {
    await library.setHidden(item, hidden);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hidden
              ? 'Hidden from recommendations.'
              : 'Restored to recommendations.',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _hide(context, library, item, !hidden),
        ),
      ),
    );
  } catch (_) {
    if (context.mounted)
      showErrorToast(context, 'Could not save this change. Please try again.');
  }
}

class RecommendationActions extends StatelessWidget {
  final Recommendation recommendation;
  const RecommendationActions({super.key, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final library = MediaLibraryScope.of(context);
    final item = recommendation.item;
    return Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => _save(context, library, item),
          icon: Icon(
            library.isSaved(item) ? Icons.bookmark : Icons.bookmark_border,
          ),
          label: Text(library.isSaved(item) ? 'Saved' : 'Save for later'),
        ),
        TextButton(
          onPressed: () =>
              showMediaDetails(context, item, recommendation: recommendation),
          child: const Text('Why this pick?'),
        ),
        IconButton(
          tooltip: 'Hide ${item.title}',
          onPressed: () => _hide(context, library, item, true),
          icon: const Icon(Icons.visibility_off_outlined),
        ),
      ],
    );
  }
}

Future<void> showMediaDetails(
  BuildContext context,
  MediaItem item, {
  Recommendation? recommendation,
}) {
  final library = MediaLibraryScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: library,
      builder: (context, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              [
                item.serviceLabel,
                if (item.subtitle.isNotEmpty) item.subtitle,
              ].join(' · '),
            ),
            const SizedBox(height: 16),
            if (recommendation != null) ...[
              Text(
                'Why this pick?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(recommendation.reason),
              const SizedBox(height: 16),
            ],
            if (item.description?.trim().isNotEmpty ?? false) ...[
              Text(
                item.description!
                    .replaceAll(RegExp(r'<[^>]*>'), ' ')
                    .replaceAll('&amp;', '&')
                    .replaceAll('&quot;', '"')
                    .replaceAll('&#39;', "'")
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim(),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in item.tags.take(12)) Chip(label: Text(tag)),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => openMediaPage(context, item),
              icon: const Icon(Icons.open_in_new),
              label: Text('Open on ${item.serviceLabel}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _save(context, library, item),
              icon: Icon(
                library.isSaved(item) ? Icons.bookmark : Icons.bookmark_border,
              ),
              label: Text(
                library.isSaved(item) ? 'Remove from saved' : 'Save for later',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SavedLibraryScreen extends StatelessWidget {
  final MediaLibrary library;
  final bool allowExplicitContent;
  const SavedLibraryScreen({
    super.key,
    required this.library,
    required this.allowExplicitContent,
  });

  @override
  Widget build(BuildContext context) => MediaLibraryScope(
    library: library,
    child: DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your list'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Saved for later'),
              Tab(text: 'Hidden picks'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: library,
          builder: (context, _) => TabBarView(
            children: [
              _items(context, library.saved, hidden: false),
              _items(context, library.hidden, hidden: true),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _items(
    BuildContext context,
    List<MediaItem> items, {
    required bool hidden,
  }) {
    final visible = items
        .where((item) => allowExplicitContent || !item.isAdult)
        .toList();
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hidden ? Icons.visibility_outlined : Icons.bookmark_border,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                hidden ? 'No hidden picks' : 'Keep your next favorite here',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hidden
                    ? 'Picks you hide can be restored here.'
                    : 'Tap “Save for later” on a recommendation. Your list stays on this device, ready when you return.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = visible[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 4,
          ),
          leading: SizedBox(
            width: 44,
            height: 60,
            child: item.hasCover
                ? Image.network(
                    item.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  )
                : const Icon(Icons.bookmark_outline),
          ),
          title: Text(item.title),
          subtitle: Text(item.serviceLabel),
          onTap: () => showMediaDetails(context, item),
          trailing: IconButton(
            tooltip: hidden ? 'Restore ${item.title}' : 'Remove ${item.title}',
            onPressed: () => hidden
                ? _hide(context, library, item, false)
                : _save(context, library, item),
            icon: Icon(hidden ? Icons.restore : Icons.bookmark_remove_outlined),
          ),
        );
      },
    );
  }
}
