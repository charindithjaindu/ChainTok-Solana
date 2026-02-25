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
  /// [sort] can be 'latest' or 'hot'.
  Future<List<Post>> getFeed({
    String sort = 'latest',
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/feed?sort=$sort&limit=$limit&offset=$offset',
    );
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
  Future<UserProfile?> getProfile(String walletPubkey) async {
    try {
      final uri = Uri.parse('$_baseUrl/user/$walletPubkey/profile');
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
      headers: {'Content-Type': 'application/json'},
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

  // ── Health ─────────────────────────────────────────────────────────────

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
