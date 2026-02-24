class Comment {
  final String pubkey;
  final String postPubkey;
  final String author;
  final String content;
  final int timestamp;

  const Comment({
    required this.pubkey,
    required this.postPubkey,
    required this.author,
    required this.content,
    required this.timestamp,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      pubkey: json['pubkey'] as String,
      postPubkey: json['post_pubkey'] as String,
      author: json['author'] as String,
      content: json['content'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  String get authorShort {
    if (author.length <= 8) return author;
    return '${author.substring(0, 4)}...${author.substring(author.length - 4)}';
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}
