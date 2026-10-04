import 'package:flutter/material.dart';
import 'package:majika/core/ai/model_download_manager.dart';

/// A persistent in-app notification also works on desktop, where the download
/// continues while the app is open but has no mobile foreground service.
class ModelDownloadNotice extends StatelessWidget {
  final Widget child;
  final ModelDownloadManager? manager;
  const ModelDownloadNotice({super.key, required this.child, this.manager});

  @override
  Widget build(BuildContext context) {
    final downloads = manager ?? ModelDownloadManager.instance;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final visible =
            downloads.phase != ModelDownloadPhase.idle && !downloads.dismissed;
        return Column(
          children: [
            if (!visible)
              const SizedBox.shrink()
            else
              Material(
                color: const Color(0xFF21372F),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.downloading_rounded, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                downloads.status,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (downloads.phase ==
                                ModelDownloadPhase.downloading)
                              TextButton(
                                onPressed: downloads.cancel,
                                child: const Text('Cancel'),
                              ),
                            if (!downloads.busy)
                              IconButton(
                                onPressed: downloads.dismiss,

                                icon: const Icon(
                                  Icons.close_rounded,
                                  semanticLabel: 'Dismiss download notice',
                                ),
                              ),
                          ],
                        ),
                        if (downloads.busy)
                          LinearProgressIndicator(
                            value:
                                downloads.phase == ModelDownloadPhase.checking
                                ? null
                                : downloads.progress,
                            semanticsLabel: 'Model download progress',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
