class UserProfile {
  final String pubkey;
  final String authority;
  final String displayName;
  final String bio;
  final String pfpUri;
  final int postCount;
  final int totalLikes;
  final int createdAt;

  const UserProfile({
    required this.pubkey,
    required this.authority,
    required this.displayName,
    required this.bio,
    required this.pfpUri,
    required this.postCount,
    required this.totalLikes,
    required this.createdAt,
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
    );
  }

  String get authorityShort {
    if (authority.length <= 8) return authority;
    return '${authority.substring(0, 4)}...${authority.substring(authority.length - 4)}';
  }
}
