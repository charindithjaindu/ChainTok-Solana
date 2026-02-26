import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/user_profile.dart';
import '../../services/wallet_service.dart';
import '../../services/solana_service.dart';
import '../../services/api_service.dart';

/// Edit profile screen — pre-populated with existing profile data.
class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  bool _isSaving = false;
  String? _error;
  File? _newAvatarFile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName == 'Anon' ? '' : widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _newAvatarFile = File(picked.path));
    }
  }

  Future<void> _save() async {
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
      _isSaving = true;
      _error = null;
    });

    try {
      final wallet = context.read<WalletService>();
      final solana = context.read<SolanaService>();
      final api = ApiService();

      // 1. Upload avatar if changed
      String pfpUri = widget.profile.pfpUri;
      if (_newAvatarFile != null) {
        try {
          final uploadedPath = await api.uploadProfilePicture(_newAvatarFile!);
          pfpUri = uploadedPath; // e.g. "/uploads/abc.jpg"
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      // 2. Update profile on-chain (if real wallet)
      if (wallet.pubkey != null && wallet.mode == WalletMode.mwa) {
        try {
          final tx = await solana.buildUpdateProfile(
            authority: wallet.pubkey!,
            displayName: name,
            bio: bio,
            pfpUri: pfpUri,
          );
          await wallet.signAndSendTransaction(
            tx,
            connection: solana.connection,
          );
          await Future.delayed(const Duration(seconds: 2));
          await api.syncFromChain();
        } catch (e) {
          debugPrint('On-chain profile update failed: $e');
        }
      }

      // 3. Update backend cache
      if (wallet.walletAddress != null) {
        await api.updateProfile(
          wallet.walletAddress!,
          displayName: name,
          bio: bio,
          pfpUri: pfpUri,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true); // return true to signal update
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Failed to update profile: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingPfpUrl = widget.profile.pfpUri.isNotEmpty
        ? (widget.profile.pfpUri.startsWith('http')
            ? widget.profile.pfpUri
            : '${AppConstants.apiBaseUrl}${widget.profile.pfpUri}')
        : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textPrimary),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Save',
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
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ── Avatar ───────────────────────────────────────────
            GestureDetector(
              onTap: _isSaving ? null : _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5),
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: _newAvatarFile != null
                          ? Image.file(_newAvatarFile!, fit: BoxFit.cover)
                          : existingPfpUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: existingPfpUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    decoration: const BoxDecoration(
                                      gradient: AppTheme.solanaGradient,
                                    ),
                                    child: const Icon(Icons.person,
                                        size: 48, color: Colors.white),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    decoration: const BoxDecoration(
                                      gradient: AppTheme.solanaGradient,
                                    ),
                                    child: const Icon(Icons.person,
                                        size: 48, color: Colors.white),
                                  ),
                                )
                              : Container(
                                  decoration: const BoxDecoration(
                                    gradient: AppTheme.solanaGradient,
                                  ),
                                  child: const Icon(Icons.person,
                                      size: 48, color: Colors.white),
                                ),
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.background,
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Name field ───────────────────────────────────────
            TextField(
              controller: _nameController,
              maxLength: 50,
              enabled: !_isSaving,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
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
                  borderSide: const BorderSide(
                      color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Bio field ────────────────────────────────────────
            TextField(
              controller: _bioController,
              maxLength: 160,
              maxLines: 3,
              enabled: !_isSaving,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Bio',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
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
                  borderSide: const BorderSide(
                      color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),

            // ── Error ────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: AppTheme.accent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
