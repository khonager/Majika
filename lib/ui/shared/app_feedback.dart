import 'package:flutter/material.dart';

class AppProgressToast {
  final OverlayEntry _entry;
  final ValueNotifier<String> _message;
  bool _isDismissed = false;

  AppProgressToast._(this._entry, this._message);

  void update(String message) {
    if (_isDismissed) return;
    _message.value = message;
  }

  void dismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    _entry.remove();
    _message.dispose();
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

AppProgressToast showProgressToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final messages = ValueNotifier<String>(message);
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: SafeArea(
            bottom: false,
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: messages,
                          builder: (context, value, child) {
                            return Text(
                              value,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  return AppProgressToast._(entry, messages);
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
