import 'package:flutter/material.dart';
import 'package:solana_web3/solana_web3.dart' as web3;
import '../models/post.dart';
import '../services/api_service.dart';
import '../services/solana_service.dart';
import '../services/wallet_service.dart';
import '../config/constants.dart';

class FeedProvider extends ChangeNotifier {
  final ApiService _api;

  List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String _sort = 'latest';
  String? _error;

  // ── Demo data for when backend is not running ─────────────────────────
  static final List<Post> _demoPosts = [
    Post(
      pubkey: 'DemoPost1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      creator: 'SoLCreator1111111111111111111111111111111111',
      arweaveUri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      caption: 'First ChainTok post ever! 🔥 #solana #web3',
      likeCount: 142,
      commentCount: 23,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
    ),
    Post(
      pubkey: 'DemoPost2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      creator: 'DevWallet2222222222222222222222222222222222222',
      arweaveUri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
      caption: 'Building on Solana is so fast ⚡ Love the dev experience',
      likeCount: 89,
      commentCount: 12,
      timestamp: DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000,
    ),
    Post(
      pubkey: 'DemoPost3cccccccccccccccccccccccccccccccccc',
      creator: 'HackerWallet33333333333333333333333333333333333',
      arweaveUri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
      caption: 'Hackathon vibes 🏆 Who\'s building something cool?',
      likeCount: 256,
      commentCount: 45,
      timestamp: DateTime.now().subtract(const Duration(hours: 8)).millisecondsSinceEpoch ~/ 1000,
    ),
    Post(
      pubkey: 'DemoPost4dddddddddddddddddddddddddddddddddd',
      creator: 'NFTCreator4444444444444444444444444444444444444',
      arweaveUri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
      caption: 'On-chain social media is the future 🚀 No censorship, full ownership',
      likeCount: 512,
      commentCount: 67,
      timestamp: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
    ),
    Post(
      pubkey: 'DemoPost5eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      creator: 'DegenTrader55555555555555555555555555555555555',
      arweaveUri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
      caption: 'Just minted my first compressed NFT post ✨',
      likeCount: 78,
      commentCount: 9,
      timestamp: DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
    ),
  ];

  FeedProvider({ApiService? api}) : _api = api ?? ApiService();

  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String get sort => _sort;
  String? get error => _error;

  // ── Load feed ──────────────────────────────────────────────────────────

  Future<void> loadFeed({bool refresh = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    if (refresh) {
      _posts = [];
      _hasMore = true;
    }
    notifyListeners();

    try {
      final newPosts = await _api.getFeed(
        sort: _sort,
        limit: AppConstants.feedPageSize,
        offset: _posts.length,
      );
      _posts = [..._posts, ...newPosts];
      _hasMore = newPosts.length >= AppConstants.feedPageSize;
    } catch (e) {
      // If backend is not running, use demo data
      if (_posts.isEmpty) {
        _posts = List.from(_demoPosts);
        _hasMore = false;
      }
      _error = null; // don't show error for demo fallback
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Change sort ────────────────────────────────────────────────────────

  Future<void> setSort(String newSort) async {
    if (_sort == newSort) return;
    _sort = newSort;
    await loadFeed(refresh: true);
  }

  // ── Toggle like (optimistic UI + on-chain tx) ────────────────────────

  Future<void> toggleLike(
    int index, {
    SolanaService? solana,
    WalletService? wallet,
  }) async {
    if (index < 0 || index >= _posts.length) return;
    final post = _posts[index];

    // Optimistic UI update
    final wasLiked = post.isLiked;
    _posts[index] = post.copyWith(
      isLiked: !wasLiked,
      likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
    );
    notifyListeners();

    // Send on-chain transaction if services are available
    if (solana != null && wallet != null && wallet.pubkey != null) {
      try {
        final userPubkey = wallet.pubkey!;
        final postPubkey = web3.Pubkey.fromBase58(post.pubkey);
        final postCreator = web3.Pubkey.fromBase58(post.creator);

        web3.Transaction tx;
        if (!wasLiked) {
          tx = await solana.buildLikePost(
            liker: userPubkey,
            postPubkey: postPubkey,
            postCreator: postCreator,
            postId: post.postId,
          );
        } else {
          tx = await solana.buildUnlikePost(
            liker: userPubkey,
            postPubkey: postPubkey,
            postCreator: postCreator,
          );
        }

        await wallet.signAndSendTransaction(
          tx,
          connection: solana.connection,
        );

        // Sync backend from chain so like counts update
        await Future.delayed(const Duration(seconds: 2));
        await _api.syncFromChain();
        await loadFeed();
      } catch (e) {
        // Revert on failure
        _posts[index] = post;
        notifyListeners();
        debugPrint('Like tx failed: $e');
      }
    }
  }

  // ── Increment comment count (after posting a comment) ─────────────────

  void incrementCommentCount(int index) {
    if (index < 0 || index >= _posts.length) return;
    final post = _posts[index];
    _posts[index] = post.copyWith(commentCount: post.commentCount + 1);
    notifyListeners();
  }
}
