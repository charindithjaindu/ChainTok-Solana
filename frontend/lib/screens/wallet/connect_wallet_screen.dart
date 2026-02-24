import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../services/wallet_service.dart';

class ConnectWalletScreen extends StatelessWidget {
  const ConnectWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // ── Logo ──────────────────────────────────────────────
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppTheme.solanaGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  FontAwesomeIcons.play,
                  color: Colors.white,
                  size: 40,
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideY(begin: -0.3, end: 0, duration: 600.ms),

              const SizedBox(height: 32),

              // ── Title ─────────────────────────────────────────────
              const Text(
                'ChainTok',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 600.ms),

              const SizedBox(height: 8),

              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.solanaGradient.createShader(bounds),
                child: const Text(
                  'On-chain short videos on Solana',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
                  .animate(delay: 400.ms)
                  .fadeIn(duration: 600.ms),

              const Spacer(flex: 2),

              // ── Connect buttons ───────────────────────────────────
              Consumer<WalletService>(
                builder: (context, wallet, _) {
                  if (wallet.isConnecting) {
                    return const Column(
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
                        Text(
                          'Connecting wallet...',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      // MWA wallet button (Android)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
                            try {
                              await wallet.connectMwa();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No MWA wallet found. Try Demo Mode.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: AppTheme.accent,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(FontAwesomeIcons.wallet, size: 20),
                          label: const Text('Connect Wallet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFAB9FF2),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                          .animate(delay: 600.ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.3, end: 0),

                      const SizedBox(height: 16),

                      // Demo mode button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            wallet.connectDemo();
                          },
                          icon: const Icon(FontAwesomeIcons.code, size: 18),
                          label: const Text('Demo Mode (Dev)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                            side: BorderSide(
                              color: AppTheme.secondary.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                          .animate(delay: 800.ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.3, end: 0),
                    ],
                  );
                },
              ),

              const Spacer(),

              // ── Footer ────────────────────────────────────────────
              Text(
                'Built on Solana ⚡',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
