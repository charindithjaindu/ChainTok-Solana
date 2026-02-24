import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:provider/provider.dart';
import 'package:solana_web3/solana_web3.dart' as web3;

import '../config/theme.dart';
import '../models/comment.dart';
import '../services/api_service.dart';
import '../services/solana_service.dart';
import '../services/wallet_service.dart';
import '../providers/feed_provider.dart';

class CommentsSheet extends StatefulWidget {
  final String postPubkey;
  final int postIndex;

  const CommentsSheet({
    super.key,
    required this.postPubkey,
    required this.postIndex,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _commentController = TextEditingController();
  final _api = ApiService();
  List<Comment> _comments = [];
  bool _isLoading = true;

  // Demo comments for when backend isn't running
  static final List<Comment> _demoComments = [
    Comment(
      pubkey: 'Comment1aaa',
      postPubkey: '',
      author: 'SolanaDev111111111111111111111111111111111111',
      content: 'This is so cool! 🔥',
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000,
    ),
    Comment(
      pubkey: 'Comment2bbb',
      postPubkey: '',
      author: 'Web3Builder22222222222222222222222222222222222',
      content: 'Love the on-chain video concept!',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    ),
    Comment(
      pubkey: 'Comment3ccc',
      postPubkey: '',
      author: 'CryptoFan333333333333333333333333333333333333',
      content: 'Solana is the best chain for social apps ⚡',
      timestamp: DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch ~/ 1000,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _api.getComments(widget.postPubkey);
      if (mounted) {
        setState(() {
        _comments = comments;
        _isLoading = false;
      });
      }
    } catch (_) {
      // Fallback to demo comments
      if (mounted) {
        setState(() {
        _comments = _demoComments;
        _isLoading = false;
      });
      }
    }
  }

  void _postComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final wallet = context.read<WalletService>();
    final solana = context.read<SolanaService>();

    // Optimistic add
    setState(() {
      _comments.insert(
        0,
        Comment(
          pubkey: 'new_${DateTime.now().millisecondsSinceEpoch}',
          postPubkey: widget.postPubkey,
          author: wallet.walletAddress ?? 'YourWallet',
          content: text,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
    });
    _commentController.clear();
    context.read<FeedProvider>().incrementCommentCount(widget.postIndex);

    // Send create_comment transaction to Solana
    if (wallet.pubkey != null) {
      final commentId = DateTime.now().millisecondsSinceEpoch;
      final postPubkey =
          _tryParsePubkey(widget.postPubkey);
      if (postPubkey != null) {
        solana
            .buildCreateComment(
              author: wallet.pubkey!,
              postPubkey: postPubkey,
              commentId: commentId,
              content: text,
            )
            .then((tx) => wallet.signAndSendTransaction(
              tx,
              connection: solana.connection,
            ))
            .catchError((Object e) {
              debugPrint('Comment tx failed: $e');
              return Uint8List(0);
            });
      }
    }
  }

  web3.Pubkey? _tryParsePubkey(String address) {
    try {
      return web3.Pubkey.fromBase58(address);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_comments.length} Comments',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: AppTheme.divider, height: 1),

          // Comments list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _comments.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              FontAwesomeIcons.commentDots,
                              size: 32,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Be the first to comment!',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) =>
                            _CommentTile(comment: _comments[i]),
                      ),
          ),

          // Comment input
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + bottomInset),
            decoration: const BoxDecoration(
              color: AppTheme.background,
              border: Border(
                top: BorderSide(color: AppTheme.divider),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      filled: true,
                      fillColor: AppTheme.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _postComment,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
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

class _CommentTile extends StatelessWidget {
  final Comment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.surfaceLight,
            child:
                Icon(Icons.person, size: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorShort,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeago.format(comment.dateTime, locale: 'en_short'),
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              FontAwesomeIcons.heart,
              size: 14,
              color: AppTheme.textSecondary,
            ),
            onPressed: () {
              // TODO: like comment
            },
          ),
        ],
      ),
    );
  }
}
