import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Glowing neon ring effect
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.6),
            blurRadius: 15,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
            blurRadius: 25,
            spreadRadius: 5,
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 2,
        ),
      ),
      child: const CircleAvatar(
        radius: 28,
        backgroundImage: NetworkImage('https://i.pravatar.cc/300?u=majika'),
      ),
    );
  }
}
