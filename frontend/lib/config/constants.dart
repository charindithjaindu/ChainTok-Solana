/// App-wide constants for ChainTok
class AppConstants {
  AppConstants._();

  // ── Backend ────────────────────────────────────────────────────────────
  /// Base URL of the ElysiaJS indexer backend.
  /// For Android emulator use 10.0.2.2; for iOS simulator / macOS use 127.0.0.1.
  static const String apiBaseUrl = 'http://10.0.2.2:3000';

  // ── Solana ─────────────────────────────────────────────────────────────
  /// RPC via backend proxy (avoids emulator DNS issues with devnet).
  static const String solanaRpcUrl =
      'http://10.0.2.2:3000/rpc';
  static const String programId =
      'ArteCcRQqj14sy5BaS7iHDU8EmYURYWFCLh4opB97vS2';

  // ── Feed defaults ──────────────────────────────────────────────────────
  static const int feedPageSize = 20;
  static const int maxCaptionLength = 280;
  static const int maxCommentLength = 280;

  // ── Arweave ────────────────────────────────────────────────────────────
  static const String arweaveGateway = 'https://arweave.net';
}
