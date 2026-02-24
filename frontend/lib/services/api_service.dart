import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/post.dart';
import '../models/comment.dart';

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

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
