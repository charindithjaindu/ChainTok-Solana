import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:solana_web3/solana_web3.dart' as web3;

import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/feed_provider.dart';
import '../../services/solana_service.dart';
import '../../services/wallet_service.dart';
import '../../services/api_service.dart';
import '../../widgets/comments_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Load feed on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wallet = context.read<WalletService>();
      final feed = context.read<FeedProvider>();
      feed.setViewer(wallet.walletAddress);
      feed.loadFeed(refresh: true);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, _) {
        if (feedProvider.isLoading && feedProvider.posts.isEmpty) {
          return const _LoadingView();
        }

        if (feedProvider.posts.isEmpty) {
          return _EmptyView(onRefresh: () => feedProvider.loadFeed(refresh: true));
        }

        return Stack(
          children: [
            // ── Vertical video feed ─────────────────────────────────
            RefreshIndicator(
              onRefresh: () => feedProvider.loadFeed(refresh: true),
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              edgeOffset: MediaQuery.of(context).padding.top + 50,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                itemCount: feedProvider.posts.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  // Load more when near the end
                  if (index >= feedProvider.posts.length - 3 &&
                      feedProvider.hasMore &&
                      !feedProvider.isLoading) {
                    feedProvider.loadFeed();
                  }
                },
                itemBuilder: (context, index) {
                  return _VideoCard(
                    post: feedProvider.posts[index],
                    index: index,
                    isActive: index == _currentPage,
                  );
                },
              ),
            ),

            // ── Top bar with sort toggle ────────────────────────────
            _TopBar(sort: feedProvider.sort, onSortChanged: feedProvider.setSort),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Video Card — full-screen video with overlay info
// ═════════════════════════════════════════════════════════════════════════════

class _VideoCard extends StatefulWidget {
  final Post post;
  final int index;
  final bool isActive;

  const _VideoCard({
    required this.post,
    required this.index,
    required this.isActive,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showPlayButton = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _initVideo() {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.post.arweaveUri),
    )..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.setLooping(true);
          if (widget.isActive) _controller.play();
        }
      });
  }

  @override
  void didUpdateWidget(covariant _VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _showPlayButton = true);
    } else {
      _controller.play();
      setState(() => _showPlayButton = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video player ──────────────────────────────────────
            if (_initialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primary,
                  strokeWidth: 2,
                ),
              ),

            // ── Play/pause icon ───────────────────────────────────
            if (_showPlayButton)
              Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.7),
                ).animate().fadeIn(duration: 200.ms).scale(
                      begin: const Offset(0.5, 0.5),
                      end: const Offset(1.0, 1.0),
                      duration: 200.ms,
                    ),
              ),

            // ── Bottom gradient ───────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 250,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),

            // ── Post info (bottom left) ───────────────────────────
            Positioned(
              bottom: 100,
              left: 16,
              right: 80,
              child: _PostInfo(post: widget.post),
            ),

            // ── Action buttons (right side) ───────────────────────
            Positioned(
              bottom: 100,
              right: 12,
              child: _ActionBar(post: widget.post, index: widget.index),
            ),

            // ── Progress bar ──────────────────────────────────────
            if (_initialized)
              Positioned(
                bottom: 84,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppTheme.primary,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Post Info — creator, caption, timestamp
// ═════════════════════════════════════════════════════════════════════════════

class _PostInfo extends StatefulWidget {
  final Post post;
  const _PostInfo({required this.post});

  @override
  State<_PostInfo> createState() => _PostInfoState();
}

class _PostInfoState extends State<_PostInfo> {
  bool _isFollowing = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Creator
        Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.surfaceLight,
              child: Icon(Icons.person, size: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 8),
            Text(
              '@${post.creatorShort}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 8),
            // Follow button
            if (!_isFollowing)
              GestureDetector(
                onTap: _loading ? null : _handleFollow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.secondary, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.secondary),
                        )
                      : Text(
                          'Follow',
                          style: TextStyle(color: AppTheme.secondary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                ),
              )
            else
              const Icon(Icons.check_circle, color: AppTheme.secondary, size: 16),
            const Spacer(),
            Text(
              timeago.format(post.dateTime, locale: 'en_short'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Caption
        Text(
          post.caption,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.3,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Future<void> _handleFollow() async {
    final wallet = context.read<WalletService>();
    if (wallet.walletAddress == null) return;

    setState(() => _loading = true);
    try {
      final api = ApiService();
      final ok = await api.followUser(wallet.walletAddress!, widget.post.creator);
      if (ok && mounted) {
        setState(() => _isFollowing = true);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Action Bar — like, comment, share buttons (right side vertical)
// ═════════════════════════════════════════════════════════════════════════════

class _ActionBar extends StatefulWidget {
  final Post post;
  final int index;
  const _ActionBar({required this.post, required this.index});

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _onLike() {
    HapticFeedback.mediumImpact();
    if (!widget.post.isLiked) {
      _heartController.forward(from: 0.0);
    }
    context.read<FeedProvider>().toggleLike(
          widget.index,
          solana: context.read<SolanaService>(),
          wallet: context.read<WalletService>(),
        );
  }

  void _onShare() {
    HapticFeedback.lightImpact();
    final solscanUrl = 'https://solscan.io/account/${widget.post.pubkey}?cluster=devnet';
    Share.share(
      'Check out this post on ChainTok!\n${widget.post.caption}\n\n$solscanUrl',
    );
  }

  void _openSolscan() {
    HapticFeedback.lightImpact();
    final url = Uri.parse(
      'https://solscan.io/account/${widget.post.pubkey}?cluster=devnet',
    );
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showTipSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TipSheet(post: widget.post),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like with heart animation
        GestureDetector(
          onTap: _onLike,
          child: AnimatedBuilder(
            animation: _heartScale,
            builder: (context, child) => Transform.scale(
              scale: _heartScale.value,
              child: child,
            ),
            child: Column(
              children: [
                Icon(
                  widget.post.isLiked ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                  color: widget.post.isLiked ? AppTheme.accent : Colors.white,
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatCount(widget.post.likeCount),
                  style: TextStyle(
                    color: widget.post.isLiked ? AppTheme.accent : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Comment
        _ActionButton(
          icon: FontAwesomeIcons.commentDots,
          label: _formatCount(widget.post.commentCount),
          color: Colors.white,
          onTap: () => _showComments(context),
        ),
        const SizedBox(height: 20),
        // Tip
        _ActionButton(
          icon: FontAwesomeIcons.coins,
          label: 'Tip',
          color: const Color(0xFFFFD700),
          onTap: _showTipSheet,
        ),
        const SizedBox(height: 20),
        // Share
        _ActionButton(
          icon: FontAwesomeIcons.share,
          label: 'Share',
          color: Colors.white,
          onTap: _onShare,
        ),
        const SizedBox(height: 20),
        // Solscan link
        GestureDetector(
          onTap: _openSolscan,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              FontAwesomeIcons.link,
              size: 14,
              color: AppTheme.secondary,
            ),
          ),
        ),
      ],
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        postPubkey: widget.post.pubkey,
        postIndex: widget.index,
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Top Bar — sort toggle (Following / For You style)
// ═════════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final String sort;
  final Function(String) onSortChanged;

  const _TopBar({required this.sort, required this.onSortChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'For You',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _SortTab kept for future multi-tab support
class _SortTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SortTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white54,
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Loading & Empty views
// ═════════════════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Shimmer.fromColors(
        baseColor: AppTheme.surfaceLight,
        highlightColor: AppTheme.surface,
        child: Column(
          children: [
            // Fake top bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 60, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                    const SizedBox(width: 20),
                    Container(width: 60, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                    const SizedBox(width: 20),
                    Container(width: 60, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fake avatar + name
                    Row(
                      children: [
                        const CircleAvatar(radius: 16, backgroundColor: Colors.white),
                        const SizedBox(width: 8),
                        Container(width: 100, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Fake caption
                    Container(width: 200, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 6),
                    Container(width: 150, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FontAwesomeIcons.video, size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'No posts yet',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Be the first to post on ChainTok!',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRefresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tip Sheet — bottom sheet for sending SOL tips
// ═════════════════════════════════════════════════════════════════════════════

class _TipSheet extends StatefulWidget {
  final Post post;
  const _TipSheet({required this.post});

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  double _selectedAmount = 0.01;
  bool _isSending = false;
  String? _txSignature;

  final List<double> _presetAmounts = [0.01, 0.05, 0.1, 0.25, 0.5, 1.0];

  Future<void> _sendTip() async {
    setState(() => _isSending = true);
    try {
      final wallet = context.read<WalletService>();
      final solana = context.read<SolanaService>();

      if (wallet.pubkey == null) {
        throw Exception('Wallet not connected');
      }

      final amountLamports = (_selectedAmount * 1e9).toInt();
      final tx = await solana.buildTipCreator(
        tipper: wallet.pubkey!,
        creator: web3.Pubkey.fromBase58(widget.post.creator),
        postPubkey: web3.Pubkey.fromBase58(widget.post.pubkey),
        amountLamports: amountLamports,
      );

      final sigBytes = await wallet.signAndSendTransaction(
        tx,
        connection: solana.connection,
      );

      // Convert signature bytes to hex string for display
      final sig = sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Record tip in backend
      final api = ApiService();
      await api.recordTip(
        senderPubkey: wallet.walletAddress!,
        receiverPubkey: widget.post.creator,
        amountSol: _selectedAmount,
        postPubkey: widget.post.pubkey,
        signature: sig,
      );

      setState(() => _txSignature = sig);
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tip failed: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Tip Creator', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Send SOL to @${widget.post.creatorShort}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),

          if (_txSignature != null) ...[
            const Icon(Icons.check_circle, color: AppTheme.secondary, size: 48),
            const SizedBox(height: 12),
            Text('Sent ${_selectedAmount} SOL!', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                final url = Uri.parse('https://solscan.io/tx/$_txSignature?cluster=devnet');
                launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: const Text('View on Solscan →', style: TextStyle(color: AppTheme.primary, fontSize: 14, decoration: TextDecoration.underline)),
            ),
            const SizedBox(height: 24),
          ] else ...[
            // Amount selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetAmounts.map((amount) {
                final isSelected = _selectedAmount == amount;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAmount = amount),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: isSelected ? null : Border.all(color: AppTheme.surfaceLight),
                    ),
                    child: Text(
                      '${amount} SOL',
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            // Send button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendTip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSending
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Send $_selectedAmount SOL', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
