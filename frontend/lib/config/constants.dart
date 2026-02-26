/// App-wide constants for ChainTok
class AppConstants {
  AppConstants._();

  // ── Backend ────────────────────────────────────────────────────────
  /// Base URL of the ElysiaJS indexer backend.
  /// Override with --dart-define=API_BASE_URL=... for custom.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://chaintok.jaindu.me',
  );

  // ── Solana ─────────────────────────────────────────────────────────
  /// RPC via backend proxy (avoids emulator DNS issues with devnet).
  static const String solanaRpcUrl = '$apiBaseUrl/rpc';
  static const String programId =
      'ArteCcRQqj14sy5BaS7iHDU8EmYURYWFCLh4opB97vS2';

  // ── Feed defaults ──────────────────────────────────────────────────────
  static const int feedPageSize = 20;
  static const int maxCaptionLength = 280;
  static const int maxCommentLength = 280;

  // ── Arweave ────────────────────────────────────────────────────────────
  static const String arweaveGateway = 'https://arweave.net';
}
