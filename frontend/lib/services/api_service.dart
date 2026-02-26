import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../models/user_profile.dart';

/// Service for communicating with the ElysiaJS backend (read layer).
class ApiService {
  final http.Client _client;
  final String _baseUrl;

  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  // ── Feed ───────────────────────────────────────────────────────────────

  /// Fetch feed posts from the backend.
  /// [sort] can be 'latest', 'hot', 'foryou', or 'following'.
  /// [viewer] is the current wallet address to determine isLiked status.
  Future<List<Post>> getFeed({
    String sort = 'latest',
    int limit = 20,
    int offset = 0,
    String? viewer,
  }) async {
    var url = '$_baseUrl/feed?sort=$sort&limit=$limit&offset=$offset';
    if (viewer != null && viewer.isNotEmpty) {
      url += '&viewer=$viewer';
    }
    final uri = Uri.parse(url);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Failed to load feed: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Post.fromJson(json)).toList();
  }

  // ── Single post ────────────────────────────────────────────────────────

  Future<Post> getPost(String postPubkey) async {
    final uri = Uri.parse('$_baseUrl/post/$postPubkey');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Failed to load post: ${response.statusCode}');
    }
    return Post.fromJson(jsonDecode(response.body));
  }

  // ── Comments ───────────────────────────────────────────────────────────

  Future<List<Comment>> getComments(String postPubkey) async {
    final uri = Uri.parse('$_baseUrl/post/$postPubkey/comments');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Failed to load comments: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Comment.fromJson(json)).toList();
  }

  // ── User posts ─────────────────────────────────────────────────────────

  Future<List<Post>> getUserPosts(String creatorPubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$creatorPubkey/posts');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Failed to load user posts: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Post.fromJson(json)).toList();
  }

  // ── Upload video/media ─────────────────────────────────────────────

  /// Upload a video file to the backend and return the URL it's served at.
  /// Returns the URL string on success (e.g. http://10.0.2.2:3000/uploads/abc.mp4).
  Future<String> uploadVideo(File file) async {
    final uri = Uri.parse('$_baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path),
    );
    final streamed = await request.send().timeout(
      const Duration(minutes: 5),
    );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw ApiException('Upload failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data['error'] != null) {
      throw ApiException('Upload error: ${data['error']}');
    }
    return data['url'] as String;
  }

  // ── User Profile ──────────────────────────────────────────────────────

  /// Fetch a user's profile from the backend cache.
  Future<UserProfile?> getProfile(String walletPubkey, {String? viewer}) async {
    try {
      var url = '$_baseUrl/user/$walletPubkey/profile';
      if (viewer != null && viewer.isNotEmpty) {
        url += '?viewer=$viewer';
      }
      final uri = Uri.parse(url);
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;
      return UserProfile.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  /// Update a user's profile metadata in the backend cache.
  Future<UserProfile?> updateProfile(
    String walletPubkey, {
    required String displayName,
    required String bio,
    required String pfpUri,
  }) async {
    final uri = Uri.parse('$_baseUrl/user/$walletPubkey/profile');
    final response = await _client.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-wallet-address': walletPubkey,
      },
      body: jsonEncode({
        'display_name': displayName,
        'bio': bio,
        'pfp_uri': pfpUri,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to update profile: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data['error'] != null) return null;
    return UserProfile.fromJson(data);
  }

  // ── Upload profile picture ─────────────────────────────────────────

  /// Upload a profile picture and return the relative URL path.
  Future<String> uploadProfilePicture(File file) async {
    final uri = Uri.parse('$_baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path),
    );
    final streamed = await request.send().timeout(
      const Duration(minutes: 2),
    );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw ApiException('Upload failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data['error'] != null) {
      throw ApiException('Upload error: ${data['error']}');
    }
    return data['url'] as String;
  }

  // ── Search ──────────────────────────────────────────────────────────────

  /// Search posts and profiles by query string.
  Future<Map<String, dynamic>> search(String query, {int limit = 20, int offset = 0}) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': query,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiException('Search failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data;
  }

  // ── Health ─────────────────────────────────────────────────────────────

  // ── Follow / Unfollow ─────────────────────────────────────────────────

  /// Follow a user (backend-level, off-chain for speed).
  Future<bool> followUser(String followerPubkey, String targetPubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$targetPubkey/follow');
    final response = await _client.post(
      uri,
      headers: {'x-wallet-address': followerPubkey},
    );
    return response.statusCode == 200;
  }

  /// Unfollow a user.
  Future<bool> unfollowUser(String followerPubkey, String targetPubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$targetPubkey/follow');
    final response = await _client.delete(
      uri,
      headers: {'x-wallet-address': followerPubkey},
    );
    return response.statusCode == 200;
  }

  /// Get follower count for a user.
  Future<int> getFollowerCount(String pubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$pubkey/followers');
    final response = await _client.get(uri);
    if (response.statusCode != 200) return 0;
    final data = jsonDecode(response.body);
    return data['count'] as int? ?? 0;
  }

  /// Get following count for a user.
  Future<int> getFollowingCount(String pubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$pubkey/following');
    final response = await _client.get(uri);
    if (response.statusCode != 200) return 0;
    final data = jsonDecode(response.body);
    return data['count'] as int? ?? 0;
  }

  // ── Tips ───────────────────────────────────────────────────────────────

  /// Record a tip transaction in backend.
  Future<bool> recordTip({
    required String senderPubkey,
    required String receiverPubkey,
    required double amountSol,
    String? postPubkey,
    String? signature,
  }) async {
    final uri = Uri.parse('$_baseUrl/tip');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-wallet-address': senderPubkey,
      },
      body: jsonEncode({
        'receiver': receiverPubkey,
        'amount_sol': amountSol,
        if (postPubkey != null) 'post_pubkey': postPubkey,
        if (signature != null) 'signature': signature,
      }),
    );
    return response.statusCode == 200;
  }

  /// Get total tips for a user.
  Future<double> getTotalTips(String pubkey) async {
    final uri = Uri.parse('$_baseUrl/user/$pubkey/tips');
    final response = await _client.get(uri);
    if (response.statusCode != 200) return 0.0;
    final data = jsonDecode(response.body);
    return (data['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$_baseUrl/');
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Sync (poll devnet → index into backend DB) ────────────────────────

  /// Triggers the backend to pull recent on-chain transactions and index them.
  /// Call after any on-chain write (post, like, comment) to update the feed.
  Future<void> syncFromChain() async {
    try {
      final uri = Uri.parse('$_baseUrl/sync');
      await _client.post(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Best-effort sync — don't crash the app if it fails
    }
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
