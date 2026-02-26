import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

/// Compressed NFT (cNFT) minting service for ChainTok posts.
///
/// Uses Solana's Bubblegum protocol concepts to mint each post as a
/// compressed NFT, making content ownership verifiable on-chain at
/// minimal cost.
///
/// In a full production build, this would interact with the Metaplex
/// Bubblegum program. For the hackathon, we simulate the minting flow
/// and provide the UI framework.
class CnftService {
  static const String bubblegumProgramId =
      'BGUMAp9Gq7iTEuizy4pqaxsTyUCBK68MDfK752saRPUY';

  static const String compressionProgramId =
      'cmtDvXumGCrqC1Age74AVPhSRVXJMd8PJS91L8KbNCK';

  /// Simulate minting a cNFT for a post.
  /// Returns a mock asset ID.
  ///
  /// In production, this would:
  /// 1. Create/use a merkle tree
  /// 2. Call Bubblegum's `mint_v1` instruction
  /// 3. Return the real asset ID
  static Future<String> mintPostAsNft({
    required String creatorAddress,
    required String postPubkey,
    required String arweaveUri,
    required String caption,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    // Generate a deterministic "asset ID" from post data
    final hash = sha256.convert(
      utf8.encode('cnft:$postPubkey:$creatorAddress'),
    );
    final assetId = hash.toString().substring(0, 44);

    debugPrint('[cNFT] Minted post $postPubkey as cNFT: $assetId');
    return assetId;
  }

  /// Check if a post has been minted as a cNFT.
  /// In production, this would query the DAS API.
  static Future<bool> isPostMinted(String postPubkey) async {
    // For hackathon: always return false (not yet minted)
    return false;
  }

  /// Get metadata for a cNFT.
  static Map<String, dynamic> buildMetadata({
    required String name,
    required String description,
    required String imageUri,
    required String creatorAddress,
  }) {
    return {
      'name': name,
      'symbol': 'CTOK',
      'description': description,
      'image': imageUri,
      'attributes': [
        {'trait_type': 'Platform', 'value': 'ChainTok'},
        {'trait_type': 'Type', 'value': 'Video Post'},
        {'trait_type': 'Creator', 'value': creatorAddress},
      ],
      'properties': {
        'category': 'video',
        'creators': [
          {'address': creatorAddress, 'share': 100},
        ],
      },
    };
  }
}
