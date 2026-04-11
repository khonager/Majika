import 'package:flutter/material.dart';

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
