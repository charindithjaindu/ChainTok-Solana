import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:solana_web3/solana_web3.dart' as web3;
import 'package:solana_web3/programs.dart' show SystemProgram;

import '../config/constants.dart';

/// Handles all Solana RPC interactions and transaction building for the
/// ChainTok Anchor program.
///
/// Does **not** hold any private key — transactions are built unsigned and then
/// handed off to the wallet (MWA / Phantom) for signing.
class SolanaService {
  late final web3.Connection _connection;
  late final web3.Pubkey _programId;

  SolanaService() {
    _connection = web3.Connection(
      web3.Cluster(Uri.parse(AppConstants.solanaRpcUrl)),
    );
    _programId = web3.Pubkey.fromBase58(AppConstants.programId);
  }

  web3.Connection get connection => _connection;
  web3.Pubkey get programId => _programId;

  // ═══════════════════════════════════════════════════════════════════════
  // ── PDA derivation helpers  ──────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  /// [b"profile", authority]
  web3.Pubkey findProfilePda(web3.Pubkey authority) {
    return web3.Pubkey.findProgramAddress(
      [utf8.encode('profile'), authority.toBytes()],
      _programId,
    ).pubkey;
  }

  /// [b"post", creator, post_id_le_bytes]
  web3.Pubkey findPostPda(web3.Pubkey creator, int postId) {
    final pidBytes = _u64LeBytes(postId);
    return web3.Pubkey.findProgramAddress(
      [utf8.encode('post'), creator.toBytes(), pidBytes],
      _programId,
    ).pubkey;
  }

  /// [b"like", post, liker]
  web3.Pubkey findLikePda(web3.Pubkey post, web3.Pubkey liker) {
    return web3.Pubkey.findProgramAddress(
      [utf8.encode('like'), post.toBytes(), liker.toBytes()],
      _programId,
    ).pubkey;
  }

  /// [b"comment", post, author, comment_id_le_bytes]
  web3.Pubkey findCommentPda(
    web3.Pubkey post,
    web3.Pubkey author,
    int commentId,
  ) {
    final cidBytes = _u64LeBytes(commentId);
    return web3.Pubkey.findProgramAddress(
      [utf8.encode('comment'), post.toBytes(), author.toBytes(), cidBytes],
      _programId,
    ).pubkey;
  }

  /// [b"follow", follower, following]
  web3.Pubkey findFollowPda(web3.Pubkey follower, web3.Pubkey following) {
    return web3.Pubkey.findProgramAddress(
      [utf8.encode('follow'), follower.toBytes(), following.toBytes()],
      _programId,
    ).pubkey;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Transaction builders (return unsigned Transaction) ───────────────
  // ═══════════════════════════════════════════════════════════════════════

  /// Build `create_profile` instruction.
  Future<web3.Transaction> buildCreateProfile({
    required web3.Pubkey authority,
    required String displayName,
    required String bio,
    required String pfpUri,
  }) async {
    final profilePda = findProfilePda(authority);

    final data = _encodeInstruction('global:create_profile', [
      _borshString(displayName),
      _borshString(bio),
      _borshString(pfpUri),
    ]);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(authority),
        web3.AccountMeta.writable(profilePda),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(authority, [ix]);
  }

  /// Build `update_profile` instruction.
  Future<web3.Transaction> buildUpdateProfile({
    required web3.Pubkey authority,
    required String displayName,
    required String bio,
    required String pfpUri,
  }) async {
    final profilePda = findProfilePda(authority);

    final data = _encodeInstruction('global:update_profile', [
      _borshString(displayName),
      _borshString(bio),
      _borshString(pfpUri),
    ]);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(authority),
        web3.AccountMeta.writable(profilePda),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(authority, [ix]);
  }

  /// Build `create_post` instruction.
  Future<web3.Transaction> buildCreatePost({
    required web3.Pubkey creator,
    required int postId,
    required String arweaveUri,
    required String caption,
  }) async {
    final profilePda = findProfilePda(creator);
    final postPda = findPostPda(creator, postId);

    final data = _encodeInstruction('global:create_post', [
      _u64LeBytes(postId),
      _borshString(arweaveUri),
      _borshString(caption),
    ]);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(creator),
        web3.AccountMeta.writable(profilePda),
        web3.AccountMeta.writable(postPda),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(creator, [ix]);
  }

  /// Build `delete_post` instruction.
  Future<web3.Transaction> buildDeletePost({
    required web3.Pubkey creator,
    required web3.Pubkey postPubkey,
  }) async {
    final profilePda = findProfilePda(creator);

    final data = _encodeInstruction('global:delete_post', []);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(creator),
        web3.AccountMeta.writable(profilePda),
        web3.AccountMeta.writable(postPubkey),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(creator, [ix]);
  }

  /// Build `like_post` instruction.
  Future<web3.Transaction> buildLikePost({
    required web3.Pubkey liker,
    required web3.Pubkey postPubkey,
    required web3.Pubkey postCreator,
    required int postId,
  }) async {
    // We need the post's PDA address — the caller already has postPubkey.
    final creatorProfilePda = findProfilePda(postCreator);
    final likePda = findLikePda(postPubkey, liker);

    final data = _encodeInstruction('global:like_post', []);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(liker),
        web3.AccountMeta.writable(postPubkey),
        web3.AccountMeta.writable(creatorProfilePda),
        web3.AccountMeta.writable(likePda),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(liker, [ix]);
  }

  /// Build `unlike_post` instruction.
  Future<web3.Transaction> buildUnlikePost({
    required web3.Pubkey liker,
    required web3.Pubkey postPubkey,
    required web3.Pubkey postCreator,
  }) async {
    final creatorProfilePda = findProfilePda(postCreator);
    final likePda = findLikePda(postPubkey, liker);

    final data = _encodeInstruction('global:unlike_post', []);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(liker),
        web3.AccountMeta.writable(postPubkey),
        web3.AccountMeta.writable(creatorProfilePda),
        web3.AccountMeta.writable(likePda),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(liker, [ix]);
  }

  /// Build `create_comment` instruction.
  Future<web3.Transaction> buildCreateComment({
    required web3.Pubkey author,
    required web3.Pubkey postPubkey,
    required int commentId,
    required String content,
  }) async {
    final commentPda = findCommentPda(postPubkey, author, commentId);

    final data = _encodeInstruction('global:create_comment', [
      _u64LeBytes(commentId),
      _borshString(content),
    ]);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(author),
        web3.AccountMeta.writable(postPubkey),
        web3.AccountMeta.writable(commentPda),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(author, [ix]);
  }

  /// Build `follow_user` instruction.
  Future<web3.Transaction> buildFollowUser({
    required web3.Pubkey follower,
    required web3.Pubkey following,
  }) async {
    final followPda = findFollowPda(follower, following);

    final data = _encodeInstruction('global:follow_user', []);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(follower),
        web3.AccountMeta(following, isSigner: false, isWritable: false),
        web3.AccountMeta.writable(followPda),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(follower, [ix]);
  }

  /// Build `unfollow_user` instruction.
  Future<web3.Transaction> buildUnfollowUser({
    required web3.Pubkey follower,
    required web3.Pubkey following,
  }) async {
    final followPda = findFollowPda(follower, following);

    final data = _encodeInstruction('global:unfollow_user', []);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(follower),
        web3.AccountMeta(following, isSigner: false, isWritable: false),
        web3.AccountMeta.writable(followPda),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(follower, [ix]);
  }

  /// Build `tip_creator` instruction.
  Future<web3.Transaction> buildTipCreator({
    required web3.Pubkey tipper,
    required web3.Pubkey creator,
    required web3.Pubkey postPubkey,
    required int amountLamports,
  }) async {
    final data = _encodeInstruction('global:tip_creator', [
      _u64LeBytes(amountLamports),
    ]);

    final ix = web3.TransactionInstruction(
      keys: [
        web3.AccountMeta.signerAndWritable(tipper),
        web3.AccountMeta.writable(creator),
        web3.AccountMeta(postPubkey, isSigner: false, isWritable: false),
        web3.AccountMeta(SystemProgram.programId, isSigner: false, isWritable: false),
      ],
      programId: _programId,
      data: data,
    );

    return _wrapInTransaction(tipper, [ix]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Helpers  ─────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetch balance (lamports) for a given public key.
  Future<int> getBalance(web3.Pubkey pubkey) async {
    return _connection.getBalance(pubkey);
  }

  /// Check if an account exists on-chain.
  Future<bool> accountExists(web3.Pubkey pubkey) async {
    try {
      final info = await _connection.getAccountInfo(pubkey);
      debugPrint('accountExists($pubkey): info=${info != null}');
      return info != null;
    } catch (e) {
      debugPrint('accountExists($pubkey) error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Private encoding helpers  ────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  /// Wrap instructions into a v0 transaction with a fresh blockhash.
  Future<web3.Transaction> _wrapInTransaction(
    web3.Pubkey payer,
    List<web3.TransactionInstruction> instructions,
  ) async {
    final blockhash = await _connection.getLatestBlockhash();
    return web3.Transaction.v0(
      payer: payer,
      recentBlockhash: blockhash.blockhash,
      instructions: instructions,
    );
  }

  /// Anchor 8-byte discriminator: sha256("global:&lt;instruction_name&gt;")[0..8]
  Uint8List _anchorDiscriminator(String namespace) {
    final hash = sha256.convert(utf8.encode(namespace));
    return Uint8List.fromList(hash.bytes.sublist(0, 8));
  }

  /// Encode an Anchor instruction: 8-byte discriminator + concatenated arg data.
  Uint8List _encodeInstruction(
    String namespace,
    List<Uint8List> argData,
  ) {
    final disc = _anchorDiscriminator(namespace);
    final buf = BytesBuilder(copy: false);
    buf.add(disc);
    for (final d in argData) {
      buf.add(d);
    }
    return buf.toBytes();
  }

  /// Borsh-encode a string (4-byte LE length prefix + UTF-8 bytes).
  Uint8List _borshString(String s) {
    final bytes = utf8.encode(s);
    final buf = ByteData(4 + bytes.length);
    buf.setUint32(0, bytes.length, Endian.little);
    final result = Uint8List(4 + bytes.length);
    result.setRange(0, 4, buf.buffer.asUint8List());
    result.setRange(4, 4 + bytes.length, bytes);
    return result;
  }

  /// Encode a u64 as 8 little-endian bytes.
  Uint8List _u64LeBytes(int value) {
    final buf = ByteData(8);
    buf.setUint64(0, value, Endian.little);
    return buf.buffer.asUint8List();
  }
}
