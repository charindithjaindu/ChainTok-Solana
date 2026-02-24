import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/feed_provider.dart';
import '../../services/solana_service.dart';
import '../../services/wallet_service.dart';
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
      context.read<FeedProvider>().loadFeed(refresh: true);
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
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
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

class _PostInfo extends StatelessWidget {
  final Post post;
  const _PostInfo({required this.post});

  @override
  Widget build(BuildContext context) {
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
}

// ═════════════════════════════════════════════════════════════════════════════
// Action Bar — like, comment, share buttons (right side vertical)
// ═════════════════════════════════════════════════════════════════════════════

class _ActionBar extends StatelessWidget {
  final Post post;
  final int index;
  const _ActionBar({required this.post, required this.index});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like
        _ActionButton(
          icon: post.isLiked ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
          label: _formatCount(post.likeCount),
          color: post.isLiked ? AppTheme.accent : Colors.white,
          onTap: () => context.read<FeedProvider>().toggleLike(
                index,
                solana: context.read<SolanaService>(),
                wallet: context.read<WalletService>(),
              ),
        ),
        const SizedBox(height: 20),
        // Comment
        _ActionButton(
          icon: FontAwesomeIcons.commentDots,
          label: _formatCount(post.commentCount),
          color: Colors.white,
          onTap: () => _showComments(context),
        ),
        const SizedBox(height: 20),
        // Share
        _ActionButton(
          icon: FontAwesomeIcons.share,
          label: 'Share',
          color: Colors.white,
          onTap: () {
            // TODO: share_plus integration
          },
        ),
        const SizedBox(height: 20),
        // On-chain badge
        Container(
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
      ],
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        postPubkey: post.pubkey,
        postIndex: index,
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
            _SortTab(
              label: 'Latest',
              isActive: sort == 'latest',
              onTap: () => onSortChanged('latest'),
            ),
            const SizedBox(width: 24),
            _SortTab(
              label: 'Hot 🔥',
              isActive: sort == 'hot',
              onTap: () => onSortChanged('hot'),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text(
            'Loading feed...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
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
