import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/wallet_service.dart';
import '../../services/api_service.dart';
import '../../providers/feed_provider.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final wallet = context.read<WalletService>();
    if (wallet.walletAddress == null) return;

    try {
      final api = ApiService();
      final profile = await api.getProfile(wallet.walletAddress!);
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } catch (_) {
      // Silently fail — profile will show defaults
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final feed = context.watch<FeedProvider>();

    // Count "my" posts from feed
    final myPosts = feed.posts
        .where((p) =>
            p.creator == wallet.walletAddress ||
            wallet.mode == WalletMode.demo)
        .toList();
    final totalLikes = myPosts.fold<int>(0, (sum, p) => sum + p.likeCount);

    final displayName = _profile?.displayName ?? 'Anon';
    final bio = _profile?.bio ?? '';
    final pfpUri = _profile?.pfpUri ?? '';
    final pfpUrl = pfpUri.isNotEmpty
        ? (pfpUri.startsWith('http')
            ? pfpUri
            : '${AppConstants.apiBaseUrl}$pfpUri')
        : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar ─────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.background,
            title: Text(
              displayName != 'Anon' ? displayName : 'Profile',
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => _showSettings(context, wallet),
              ),
            ],
          ),

          // ── Profile header ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: pfpUrl == null
                          ? AppTheme.solanaGradient
                          : null,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: pfpUrl != null
                          ? CachedNetworkImage(
                              imageUrl: pfpUrl,
                              fit: BoxFit.cover,
                              width: 90,
                              height: 90,
                              placeholder: (_, __) => Container(
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.solanaGradient,
                                ),
                                child: const Icon(Icons.person,
                                    size: 44, color: Colors.white),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.solanaGradient,
                                ),
                                child: const Icon(Icons.person,
                                    size: 44, color: Colors.white),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 44,
                              color: Colors.white,
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Display name
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Address
                  GestureDetector(
                    onTap: () {
                      if (wallet.walletAddress != null) {
                        Clipboard.setData(
                            ClipboardData(text: wallet.walletAddress!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Address copied!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          wallet.walletShort,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),

                  // Bio
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],

                  if (wallet.mode == WalletMode.demo)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Demo Mode',
                        style: TextStyle(
                          color: AppTheme.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatItem(
                        count: myPosts.length.toString(),
                        label: 'Posts',
                      ),
                      _StatItem(
                        count: _formatCount(totalLikes),
                        label: 'Likes',
                      ),
                      const _StatItem(
                        count: '0',
                        label: 'Followers',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Edit profile button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        final profile = _profile ??
                            UserProfile(
                              pubkey: '',
                              authority: wallet.walletAddress ?? '',
                              displayName: 'Anon',
                              bio: '',
                              pfpUri: '',
                              postCount: 0,
                              totalLikes: 0,
                              createdAt: 0,
                            );
                        final updated = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                EditProfileScreen(profile: profile),
                          ),
                        );
                        if (updated == true) {
                          _loadProfile(); // refresh profile data
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Divider ─────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Divider(color: AppTheme.divider, height: 1),
          ),

          // ── Posts grid ──────────────────────────────────────────
          if (myPosts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FontAwesomeIcons.video,
                      size: 40,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No posts yet',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create your first ChainTok!',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(2),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _PostThumbnail(post: myPosts[index]),
                  childCount: myPosts.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 9 / 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, WalletService wallet) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.accent),
              title: const Text(
                'Disconnect Wallet',
                style: TextStyle(color: AppTheme.accent),
              ),
              onTap: () {
                Navigator.pop(context);
                wallet.disconnect();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final Post post;
  const _PostThumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceLight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: Icon(
              FontAwesomeIcons.play,
              color: AppTheme.textSecondary,
              size: 24,
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Row(
              children: [
                const Icon(
                  FontAwesomeIcons.play,
                  color: Colors.white,
                  size: 10,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
