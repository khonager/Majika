import 'package:flutter/material.dart';
import 'package:majika/core/firebase/firebase_bootstrap.dart';
import 'package:majika/core/firebase/firebase_profile_service.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = const FirebaseProfileService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _steamProfileController = TextEditingController();
  bool _isCreatingAccount = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _steamProfileController.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    if (email.isEmpty || password.length < 6) {
      showErrorToast(context, 'Enter an email and a 6+ character password.');
      return;
    }
    if (_isCreatingAccount && displayName.isEmpty) {
      showErrorToast(context, 'Choose a display name for your profile.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isCreatingAccount) {
        await _service.createAccount(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        await _service.signIn(email: email, password: password);
      }
      if (!mounted) return;
      _passwordController.clear();
      showInfoToast(
        context,
        _isCreatingAccount ? 'Account created.' : 'Signed in.',
      );
    } catch (error) {
      if (!mounted) return;
      showErrorToast(context, 'Could not sign in: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      showErrorToast(context, 'Display name cannot be empty.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _service.saveProfile(
        displayName: displayName,
        steamProfile: _steamProfileController.text,
      );
      if (!mounted) return;
      showInfoToast(context, 'Profile saved.');
    } catch (error) {
      if (!mounted) return;
      showErrorToast(context, 'Could not save profile: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF16211C), Color(0xFF0F1217), Color(0xFF1B2028)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Majika identity',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to use Firebase-backed features. Steam imports use your signed-in session to call a Cloud Function, so the Steam Web API key stays on the server.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!_service.isConfigured)
              _SetupRequiredCard(error: FirebaseBootstrap.lastError)
            else
              StreamBuilder<AppAuthUser?>(
                stream: _service.authStateChanges(),
                builder: (context, snapshot) {
                  final user = snapshot.data;
                  if (user == null) return _buildAuthCard();
                  return FutureBuilder<AppUserProfile?>(
                    future: _service.fetchProfile(),
                    builder: (context, profileSnapshot) {
                      final profile = profileSnapshot.data;
                      if (profile != null) {
                        _displayNameController.text = profile.displayName;
                        _steamProfileController.text =
                            profile.steamProfile ?? '';
                      } else {
                        _displayNameController.text = user.fallbackDisplayName;
                      }
                      return _buildSignedInCard(user: user, profile: profile);
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthCard() {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isCreatingAccount ? 'Create account' : 'Sign in',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _ProfileTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          _ProfileTextField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
          ),
          if (_isCreatingAccount) ...[
            const SizedBox(height: 10),
            _ProfileTextField(
              controller: _displayNameController,
              label: 'Display name',
              icon: Icons.badge_outlined,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isSaving ? null : _submitAuth,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isCreatingAccount
                            ? Icons.person_add_alt_1_rounded
                            : Icons.login_rounded,
                      ),
                label: Text(_isCreatingAccount ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => setState(
                        () => _isCreatingAccount = !_isCreatingAccount,
                      ),
                child: Text(
                  _isCreatingAccount
                      ? 'I already have one'
                      : 'Create one instead',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignedInCard({
    required AppAuthUser user,
    AppUserProfile? profile,
  }) {
    final theme = Theme.of(context);
    final updatedAt = profile?.updatedAt;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.secondary.withValues(
                  alpha: 0.18,
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: theme.colorScheme.secondary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.displayName ??
                          user.displayName ??
                          (user.email.isEmpty ? null : user.email) ??
                          'Majika user',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      user.email.isEmpty ? user.uid : user.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ProfileTextField(
            controller: _displayNameController,
            label: 'Display name',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 10),
          _ProfileTextField(
            controller: _steamProfileController,
            label: 'Steam profile URL, vanity name, or SteamID64',
            icon: Icons.sports_esports_outlined,
          ),
          const SizedBox(height: 10),
          Text(
            'Steam OpenID account linking is a bigger custom-auth step. For now, saving your public Steam profile here gives Majika a safe profile link while the actual Web API key remains in Firebase Functions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${updatedAt.toLocal()}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save profile'),
              ),
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () async {
                        await _service.signOut();
                        if (!mounted) return;
                        showInfoToast(context, 'Signed out.');
                      },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupRequiredCard extends StatelessWidget {
  final Object? error;

  const _SetupRequiredCard({this.error});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firebase setup needed',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your Firebase app config with FlutterFire or the --dart-define values from the tutorial. The Profile page will activate automatically after Firebase initializes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.45,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              '$error',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFA0AD)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
    );
  }
}
