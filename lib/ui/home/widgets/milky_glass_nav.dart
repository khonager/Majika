import 'dart:ui';
import 'package:flutter/material.dart';

class MilkyGlassNav extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final VoidCallback onFilterTap;

  const MilkyGlassNav({
    super.key,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        // Strong blur for that "milky" aesthetic requested by the user
        filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            // Milky semi-transparent white
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2), // Subtle border
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Burger Menu
              IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: onMenuTap,
              ),
              const SizedBox(width: 8),
              // Search / Modular Area
              Expanded(
                child: Text(
                  'DISCOVER',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: onSearchTap,
              ),
              IconButton(
                icon: const Icon(
                  Icons.filter_list_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: onFilterTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
