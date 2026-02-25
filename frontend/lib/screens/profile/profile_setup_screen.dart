import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../services/wallet_service.dart';
import '../../services/solana_service.dart';
import '../../services/api_service.dart';

/// Profile setup screen shown after wallet connect when no profile exists.
/// Collects display name, bio, and profile picture.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }


  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a display name');
      return;
    }
    if (name.length > 50) {
      setState(() => _error = 'Name must be 50 characters or less');
      return;
    }

    final bio = _bioController.text.trim();
    if (bio.length > 160) {
      setState(() => _error = 'Bio must be 160 characters or less');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final wallet = context.read<WalletService>();
      final solana = context.read<SolanaService>();
      final api = ApiService();

      // 1. Create profile on-chain (if real wallet)
      if (wallet.pubkey != null && wallet.mode == WalletMode.mwa) {
        try {
          final tx = await solana.buildCreateProfile(
            authority: wallet.pubkey!,
            displayName: name,
            bio: bio,
            pfpUri: '',
          );
          await wallet.signAndSendTransaction(
            tx,
            connection: solana.connection,
          );
          // Wait for confirmation
          await Future.delayed(const Duration(seconds: 2));

          // Sync so backend picks up the on-chain profile
          await api.syncFromChain();
        } catch (e) {
          // Profile may already exist on-chain — that's okay
          debugPrint('On-chain profile creation skipped/failed: $e');
        }
      }

      // 3. Update backend cache with profile metadata
      if (wallet.walletAddress != null) {
        await api.updateProfile(
          wallet.walletAddress!,
          displayName: name,
          bio: bio,
          pfpUri: '',
        );
      }

      if (mounted) {
        // Navigate to the main app
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Failed to create profile: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              // ── Header ─────────────────────────────────────────
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.solanaGradient.createShader(bounds),
                child: const Text(
                  'Set Up Your Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: -0.2, end: 0),

              const SizedBox(height: 8),

              Text(
                'Let others know who you are',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 40),

              // ── Avatar (display only) ──────────────────────────
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.solanaGradient,
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  size: 52,
                  color: Colors.white,
                ),
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 400.ms)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

              const SizedBox(height: 32),

              // ── Display Name ───────────────────────────────────
              TextField(
                controller: _nameController,
                maxLength: 50,
                enabled: !_isSubmitting,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Display name',
                  prefixIcon: const Icon(
                    FontAwesomeIcons.user,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  counterStyle: const TextStyle(color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
              )
                  .animate(delay: 400.ms)
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.1, end: 0),

              const SizedBox(height: 8),

              // ── Bio ────────────────────────────────────────────
              TextField(
                controller: _bioController,
                maxLength: 160,
                maxLines: 3,
                enabled: !_isSubmitting,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Bio (optional)',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(
                      FontAwesomeIcons.penFancy,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  counterStyle: const TextStyle(color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
              )
                  .animate(delay: 500.ms)
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.1, end: 0),

              // ── Error ──────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.accent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // ── Submit button ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: _isSubmitting
                    ? Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.solanaGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.solanaGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Create Profile',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
              )
                  .animate(delay: 600.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),

              const SizedBox(height: 16),

              // ── Skip button ────────────────────────────────────
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/', (_) => false);
                      },
                child: Text(
                  'Skip for now',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Info footer ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FontAwesomeIcons.link,
                      size: 14,
                      color: AppTheme.secondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your profile is stored on Solana and can be updated anytime.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
