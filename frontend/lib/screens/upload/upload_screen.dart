import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/wallet_service.dart';
import '../../services/solana_service.dart';
import '../../services/api_service.dart';
import '../../services/cnft_service.dart';
import '../../providers/feed_provider.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _captionController = TextEditingController();
  XFile? _videoFile;
  bool _isUploading = false;
  double _uploadProgress = 0;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (video != null) {
      setState(() => _videoFile = video);
    }
  }

  Future<void> _recordVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    );
    if (video != null) {
      setState(() => _videoFile = video);
    }
  }

  Future<void> _uploadPost() async {
    if (_videoFile == null) return;

    final wallet = context.read<WalletService>();
    if (!wallet.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect wallet first')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // Step 1: Upload video to backend storage
      final api = ApiService();
      if (mounted) setState(() => _uploadProgress = 0.1);

      final videoUrl = await api.uploadVideo(File(_videoFile!.path));

      if (mounted) setState(() => _uploadProgress = 0.6);

      // Step 2: Create post on-chain
      final solana = context.read<SolanaService>();
      final postId = DateTime.now().millisecondsSinceEpoch;
      // Use the uploaded video path as the arweave_uri field
      // videoUrl is a relative path like /uploads/abc.mp4
      final arweaveUri = '${AppConstants.apiBaseUrl}$videoUrl';

      if (wallet.pubkey != null) {
        // Ensure profile exists before posting — if creation fails
        // (e.g. profile already exists on-chain), just continue.
        try {
          final profilePda = solana.findProfilePda(wallet.pubkey!);
          final hasProfile = await solana.accountExists(profilePda);
          if (!hasProfile) {
            final profileTx = await solana.buildCreateProfile(
              authority: wallet.pubkey!,
              displayName: wallet.walletShort,
              bio: '',
              pfpUri: '',
            );
            await wallet.signAndSendTransaction(
              profileTx,
              connection: solana.connection,
            );
            // Wait for confirmation
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          // Profile likely already exists (error 0x0 = AccountAlreadyInUse)
          debugPrint('Profile creation skipped/failed: $e');
        }

        final tx = await solana.buildCreatePost(
          creator: wallet.pubkey!,
          postId: postId,
          arweaveUri: arweaveUri,
          caption: _captionController.text.trim(),
        );
        await wallet.signAndSendTransaction(
          tx,
          connection: solana.connection,
        );

        if (mounted) setState(() => _uploadProgress = 0.9);

        // Sync backend from chain so the post appears in the feed
        await Future.delayed(const Duration(seconds: 2));
        await api.syncFromChain();

        if (mounted) setState(() => _uploadProgress = 1.0);
      }

      if (mounted) {
        // Refresh the feed after sync
        try {
          await context.read<FeedProvider>().loadFeed(refresh: true);
        } catch (_) {}

        final caption = _captionController.text.trim();
        final creatorAddr = wallet.walletAddress ?? '';

        setState(() {
          _isUploading = false;
          _videoFile = null;
          _captionController.clear();
        });

        // Show cNFT minting dialog
        _showPostSuccessDialog(
          context,
          postPubkey: solana.findPostPda(wallet.pubkey!, postId).toBase58(),
          arweaveUri: arweaveUri,
          caption: caption,
          creatorAddress: creatorAddr,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    }
  }

  void _showPostSuccessDialog(
    BuildContext context, {
    required String postPubkey,
    required String arweaveUri,
    required String caption,
    required String creatorAddress,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _PostSuccessDialog(
        postPubkey: postPubkey,
        arweaveUri: arweaveUri,
        caption: caption,
        creatorAddress: creatorAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('New Post'),
        actions: [
          if (_videoFile != null && !_isUploading)
            TextButton(
              onPressed: _uploadPost,
              child: const Text(
                'Post',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Video preview / picker ───────────────────────────
            if (_videoFile == null) ...[
              _PickerCard(
                icon: FontAwesomeIcons.photoFilm,
                title: 'Choose from Gallery',
                subtitle: 'Select a video up to 60 seconds',
                onTap: _pickVideo,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

              const SizedBox(height: 16),

              _PickerCard(
                icon: FontAwesomeIcons.camera,
                title: 'Record Video',
                subtitle: 'Create something new',
                onTap: _recordVideo,
              )
                  .animate(delay: 100.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
            ] else ...[
              // Video selected — show preview
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: AppTheme.surfaceLight,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FontAwesomeIcons.circleCheck,
                                color: AppTheme.secondary,
                                size: 48,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Video selected',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => setState(() => _videoFile = null),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Caption input ───────────────────────────────────
            TextField(
              controller: _captionController,
              maxLength: AppConstants.maxCaptionLength,
              maxLines: 3,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Write a caption...',
                counterStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),

            const SizedBox(height: 24),

            // ── Upload progress ─────────────────────────────────
            if (_isUploading) ...[
              const Text(
                'Uploading to Arweave & creating on-chain post...',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // ── Info box ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    FontAwesomeIcons.link,
                    size: 16,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your video will be stored permanently on Arweave and the post metadata recorded on Solana.',
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
          ],
        ),
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PickerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Post Success Dialog — with cNFT minting option
// ═════════════════════════════════════════════════════════════════════════════

class _PostSuccessDialog extends StatefulWidget {
  final String postPubkey;
  final String arweaveUri;
  final String caption;
  final String creatorAddress;

  const _PostSuccessDialog({
    required this.postPubkey,
    required this.arweaveUri,
    required this.caption,
    required this.creatorAddress,
  });

  @override
  State<_PostSuccessDialog> createState() => _PostSuccessDialogState();
}

class _PostSuccessDialogState extends State<_PostSuccessDialog> {
  bool _isMinting = false;
  String? _assetId;

  Future<void> _mintCnft() async {
    setState(() => _isMinting = true);
    try {
      final assetId = await CnftService.mintPostAsNft(
        creatorAddress: widget.creatorAddress,
        postPubkey: widget.postPubkey,
        arweaveUri: widget.arweaveUri,
        caption: widget.caption,
      );
      if (mounted) {
        setState(() => _assetId = assetId);
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Minting failed: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
    if (mounted) setState(() => _isMinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: AppTheme.secondary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Post Created!',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your video is now live on Solana',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                final url = Uri.parse(
                  'https://solscan.io/account/${widget.postPubkey}?cluster=devnet',
                );
                launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: const Text(
                'View on Solscan →',
                style: TextStyle(color: AppTheme.primary, fontSize: 13, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 24),

            if (_assetId != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(FontAwesomeIcons.gem, color: AppTheme.primary, size: 24),
                    const SizedBox(height: 8),
                    const Text(
                      'Minted as cNFT!',
                      style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Asset: ${_assetId!.substring(0, 12)}...',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isMinting ? null : _mintCnft,
                  icon: _isMinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                        )
                      : const Icon(FontAwesomeIcons.gem, size: 14),
                  label: Text(_isMinting ? 'Minting...' : 'Mint as Compressed NFT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Own your content as a compressed NFT on Solana',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
