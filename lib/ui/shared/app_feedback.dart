import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:majika/core/ai/ai_console_log.dart';

class AppProgressToast {
  final OverlayEntry _entry;
  final ValueNotifier<String> _message;
  final AiConsoleLog? _consoleLog;
  final ValueNotifier<bool> _isExpanded;
  final ValueNotifier<bool> _isComplete;
  bool _isDismissed = false;

  AppProgressToast._(
    this._entry,
    this._message,
    this._consoleLog,
    this._isExpanded,
    this._isComplete,
  );

  void update(String message) {
    if (_isDismissed) return;
    _message.value = message;
    _consoleLog?.addLine(message);
  }

  void dismiss() {
    if (_isDismissed) return;
    if (_isExpanded.value) {
      _isComplete.value = true;
      _message.value = 'AI log complete. Swipe to dismiss.';
      _consoleLog?.addLine('Complete. Swipe the expanded log to dismiss.');
      return;
    }
    forceDismiss();
  }

  void forceDismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    _entry.remove();
    _message.dispose();
    _isExpanded.dispose();
    _isComplete.dispose();
  }
}

SnackBar _buildSnackBar(
  BuildContext context, {
  required String message,
  required IconData icon,
  required Color color,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF1B2027).withValues(alpha: 0.96),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
    ),
    content: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

AppProgressToast showProgressToast(
  BuildContext context,
  String message, {
  AiConsoleLog? consoleLog,
}) {
  final overlay = Overlay.of(context);
  final messages = ValueNotifier<String>(message);
  final isExpanded = ValueNotifier<bool>(false);
  final isComplete = ValueNotifier<bool>(false);
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  late final OverlayEntry entry;
  late final AppProgressToast toast;
  consoleLog?.addLine(message);

  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: SafeArea(
          bottom: false,
          child: _ProgressToastBody(
            message: messages,
            consoleLog: consoleLog,
            isExpanded: isExpanded,
            isComplete: isComplete,
            colorScheme: colorScheme,
            textTheme: textTheme,
            onDismissed: () => toast.forceDismiss(),
          ),
        ),
      );
    },
  );

  toast = AppProgressToast._(
    entry,
    messages,
    consoleLog,
    isExpanded,
    isComplete,
  );
  overlay.insert(entry);
  return toast;
}

class _ProgressToastBody extends StatelessWidget {
  final ValueListenable<String> message;
  final AiConsoleLog? consoleLog;
  final ValueNotifier<bool> isExpanded;
  final ValueListenable<bool> isComplete;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onDismissed;

  const _ProgressToastBody({
    required this.message,
    required this.consoleLog,
    required this.isExpanded,
    required this.isComplete,
    required this.colorScheme,
    required this.textTheme,
    required this.onDismissed,
  });

  void _copyLog() {
    final log = consoleLog?.value.trim();
    final fallback = message.value.trim();
    Clipboard.setData(
      ClipboardData(text: log?.isNotEmpty == true ? log! : fallback),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: const ValueKey('app-progress-toast'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismissed(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => isExpanded.value = !isExpanded.value,
        onLongPress: _copyLog,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1B2027).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: isExpanded,
              builder: (context, expanded, child) {
                return AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ValueListenableBuilder<bool>(
                              valueListenable: isComplete,
                              builder: (context, complete, child) {
                                if (complete) {
                                  return Icon(
                                    Icons.check_circle_rounded,
                                    color: colorScheme.primary,
                                    size: 20,
                                  );
                                }
                                return SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: message,
                                builder: (context, value, child) {
                                  return Text(
                                    value,
                                    maxLines: expanded ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Copy AI details',
                              visualDensity: VisualDensity.compact,
                              onPressed: _copyLog,
                              icon: const Icon(Icons.copy_rounded),
                              color: Colors.white70,
                            ),
                            Icon(
                              expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                        if (expanded) ...[
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: consoleLog == null
                                    ? const _ProgressLogText(
                                        value: 'Waiting for AI activity...',
                                      )
                                    : ValueListenableBuilder<String>(
                                        valueListenable: consoleLog!,
                                        builder: (context, _, child) {
                                          final summary = consoleLog!
                                              .summaryValue
                                              .trimRight();
                                          return _ProgressLogText(
                                            value: summary.isEmpty
                                                ? 'Waiting for AI activity...'
                                                : summary,
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLogText extends StatelessWidget {
  final String value;

  const _ProgressLogText({required this.value});

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      value,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.35,
      ),
    );
  }
}

void showInfoToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _buildSnackBar(
        context,
        message: message,
        icon: Icons.info_outline_rounded,
        color: Theme.of(context).colorScheme.secondary,
      ),
    );
}

void showFeatureComingSoon(BuildContext context, String featureName) {
  showInfoToast(context, '$featureName is not developed yet.');
}

void showErrorToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _buildSnackBar(
        context,
        message: message,
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFFF7C8C),
      ),
    );
}
