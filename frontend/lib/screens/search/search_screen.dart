import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import '../../services/api_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _api = ApiService();
  Timer? _debounce;

  List<Post> _posts = [];
  List<UserProfile> _profiles = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query.trim());
      } else {
        setState(() {
          _posts = [];
          _profiles = [];
          _hasSearched = false;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);

    try {
      final results = await _api.search(query);

      final posts = (results['posts'] as List<dynamic>?)
              ?.map((json) => Post.fromJson(json as Map<String, dynamic>))
              .toList() ??
          [];
      final profiles = (results['profiles'] as List<dynamic>?)
              ?.map((json) =>
                  UserProfile.fromJson(json as Map<String, dynamic>))
              .toList() ??
          [];

      if (mounted) {
        setState(() {
          _posts = posts;
          _profiles = profiles;
          _hasSearched = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search creators or posts...',
                    hintStyle: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        FontAwesomeIcons.magnifyingGlass,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 0,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: AppTheme.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                ),
              ),
            ),

            // ── Tabs ────────────────────────────────────────────────
            if (_hasSearched) ...[
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.textPrimary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: AppTheme.divider,
                tabs: [
                  Tab(text: 'Creators (${_profiles.length})'),
                  Tab(text: 'Posts (${_posts.length})'),
                ],
              ),
            ],

            // ── Results ─────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : !_hasSearched
                      ? _buildIdleState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildProfileResults(),
                            _buildPostResults(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              FontAwesomeIcons.magnifyingGlass,
              size: 28,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Search ChainTok',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Find creators, posts, and on-chain content',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileResults() {
    if (_profiles.isEmpty) {
      return _buildEmptyResult('No creators found');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        final profile = _profiles[index];
        return _ProfileTile(profile: profile);
      },
    );
  }

  Widget _buildPostResults() {
    if (_posts.isEmpty) {
      return _buildEmptyResult('No posts found');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _PostTile(post: post);
      },
    );
  }

  Widget _buildEmptyResult(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FontAwesomeIcons.faceSadTear,
            size: 40,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Profile tile
// ═════════════════════════════════════════════════════════════════════════════

class _ProfileTile extends StatelessWidget {
  final UserProfile profile;

  const _ProfileTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    final hasPfp = profile.pfpUri.isNotEmpty;
    final baseUrl = AppConstants.apiBaseUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.surfaceLight,
        backgroundImage: hasPfp
            ? CachedNetworkImageProvider(
                profile.pfpUri.startsWith('http')
                    ? profile.pfpUri
                    : '$baseUrl${profile.pfpUri}',
              )
            : null,
        child: hasPfp
            ? null
            : const Icon(Icons.person, color: AppTheme.textSecondary),
      ),
      title: Text(
        profile.displayName.isNotEmpty ? profile.displayName : 'Anon',
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        profile.authorityShort,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
        ),
      ),
      trailing: Text(
        '${profile.postCount} posts',
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Post tile
// ═════════════════════════════════════════════════════════════════════════════

class _PostTile extends StatelessWidget {
  final Post post;

  const _PostTile({required this.post});

  String get _creatorShort {
    if (post.creator.length <= 8) return post.creator;
    return '${post.creator.substring(0, 4)}...${post.creator.substring(post.creator.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          gradient: AppTheme.primaryGradient.scale(0.3),
        ),
        child: const Icon(
          FontAwesomeIcons.play,
          size: 18,
          color: AppTheme.primary,
        ),
      ),
      title: Text(
        post.caption.isNotEmpty ? post.caption : 'Untitled post',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 14,
          height: 1.3,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Text(
              _creatorShort,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 12),
            Icon(FontAwesomeIcons.heart,
                size: 11, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              '${post.likeCount}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 10),
            Icon(FontAwesomeIcons.comment,
                size: 11, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              '${post.commentCount}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
