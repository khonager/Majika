import 'package:flutter/material.dart';
import 'package:majika/ui/home/widgets/discover_feed.dart';
import 'package:majika/ui/home/widgets/milky_glass_nav.dart';
import 'package:majika/ui/home/widgets/profile_avatar.dart';
import 'package:majika/ui/home/widgets/side_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isNavVisible = true;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Hide nav on scroll down, show on scroll up
    if (_scrollController.offset > 50 &&
        _scrollController.offset > _lastScrollOffset &&
        _isNavVisible) {
      setState(() => _isNavVisible = false);
    } else if (_scrollController.offset < _lastScrollOffset && !_isNavVisible) {
      setState(() => _isNavVisible = true);
    }
    _lastScrollOffset = _scrollController.offset;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideDrawer(),
      body: Stack(
        children: [
          // Background content
          DiscoverFeed(scrollController: _scrollController),
          
          // Floating Milky Nav
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: _isNavVisible ? 50 : -100, // Hide upwards
            left: 20,
            right: 80, // Leave room for avatar
            child: const MilkyGlassNav(),
          ),
          
          // Floating Profile Avatar (Always visible or animate similarly)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: _isNavVisible ? 50 : -100,
            right: 20,
            child: const ProfileAvatar(),
          ),
        ],
      ),
    );
  }
}
