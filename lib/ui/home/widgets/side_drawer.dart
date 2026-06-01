import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:majika/ui/profile/profile_screen.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';

class SideDrawer extends StatelessWidget {
  const SideDrawer({super.key});

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
          child: Container(
            color: const Color(0xFF121418).withValues(alpha: 0.5),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.5),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: const CircleAvatar(
                          backgroundImage: NetworkImage(
                            'https://i.pravatar.cc/300?u=majika',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Alex R.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Local Profile',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMenuItem(Icons.settings_outlined, 'Settings', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                }),
                _buildMenuItem(Icons.extension_outlined, 'Extensions', () {
                  Navigator.pop(context);
                  showFeatureComingSoon(context, 'Extensions');
                }),
                _buildMenuItem(Icons.favorite_border_rounded, 'Favorites', () {
                  Navigator.pop(context);
                  showFeatureComingSoon(context, 'Favorites');
                }),
                _buildMenuItem(Icons.library_books_outlined, 'Library', () {
                  Navigator.pop(context);
                  showFeatureComingSoon(context, 'Library');
                }),
                _buildMenuItem(Icons.person_outline_rounded, 'Account', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                }),
                _buildMenuItem(Icons.download_outlined, 'Downloads', () {
                  Navigator.pop(context);
                  showFeatureComingSoon(context, 'Downloads');
                }),
                const Divider(color: Colors.white10),
                _buildMenuItem(Icons.logout_rounded, 'Lock Interface', () {
                  Navigator.pop(context);
                  showFeatureComingSoon(context, 'Interface lock');
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
