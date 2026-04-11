import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final VoidCallback onTap;

  const ProfileAvatar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Glowing neon ring effect
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.6),
                blurRadius: 15,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.3),
                blurRadius: 25,
                spreadRadius: 5,
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
              width: 2,
            ),
          ),
          child: const CircleAvatar(
            radius: 28,
            backgroundImage: NetworkImage('https://i.pravatar.cc/300?u=majika'),
          ),
        ),
      ),
    );
  }
}
