class UserProfile {
  final String pubkey;
  final String authority;
  final String displayName;
  final String bio;
  final String pfpUri;
  final int postCount;
  final int totalLikes;
  final int createdAt;
  final int followerCount;
  final int followingCount;
  final double totalTips;
  final bool isFollowing;

  const UserProfile({
    required this.pubkey,
    required this.authority,
    required this.displayName,
    required this.bio,
    required this.pfpUri,
    required this.postCount,
    required this.totalLikes,
    required this.createdAt,
    this.followerCount = 0,
    this.followingCount = 0,
    this.totalTips = 0.0,
    this.isFollowing = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      pubkey: json['pubkey'] as String? ?? '',
      authority: json['authority'] as String,
      displayName: json['display_name'] as String? ?? 'Anon',
      bio: json['bio'] as String? ?? '',
      pfpUri: json['pfp_uri'] as String? ?? '',
      postCount: json['post_count'] as int? ?? 0,
      totalLikes: json['total_likes'] as int? ?? 0,
      createdAt: json['created_at'] as int? ?? 0,
      followerCount: json['follower_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      totalTips: (json['total_tips'] as num?)?.toDouble() ?? 0.0,
      isFollowing: json['is_following'] as bool? ?? false,
    );
  }

  UserProfile copyWith({
    int? followerCount,
    int? followingCount,
    double? totalTips,
    bool? isFollowing,
    String? displayName,
    String? bio,
    String? pfpUri,
  }) {
    return UserProfile(
      pubkey: pubkey,
      authority: authority,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      pfpUri: pfpUri ?? this.pfpUri,
      postCount: postCount,
      totalLikes: totalLikes,
      createdAt: createdAt,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      totalTips: totalTips ?? this.totalTips,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }

  String get authorityShort {
    if (authority.length <= 8) return authority;
    return '${authority.substring(0, 4)}...${authority.substring(authority.length - 4)}';
  }
}
