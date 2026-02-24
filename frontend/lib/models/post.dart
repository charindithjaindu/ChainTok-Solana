class Post {
  final String pubkey;
  final String creator;
  final int postId; // client-generated unique id (e.g. unix ms)
  final String arweaveUri;
  final String caption;
  final int likeCount;
  final int commentCount;
  final int timestamp;
  final bool isLiked; // client-side state

  const Post({
    required this.pubkey,
    required this.creator,
    this.postId = 0,
    required this.arweaveUri,
    required this.caption,
    required this.likeCount,
    required this.commentCount,
    required this.timestamp,
    this.isLiked = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      pubkey: json['pubkey'] as String,
      creator: json['creator'] as String,
      postId: json['post_id'] as int? ?? 0,
      arweaveUri: json['arweave_uri'] as String,
      caption: json['caption'] as String? ?? '',
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      timestamp: json['timestamp'] as int,
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
  }) {
    return Post(
      pubkey: pubkey,
      creator: creator,
      postId: postId,
      arweaveUri: arweaveUri,
      caption: caption,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      timestamp: timestamp,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  /// Short wallet address for display: "ABcd...xYz1"
  String get creatorShort {
    if (creator.length <= 8) return creator;
    return '${creator.substring(0, 4)}...${creator.substring(creator.length - 4)}';
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}
