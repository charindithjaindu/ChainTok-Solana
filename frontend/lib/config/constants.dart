import 'dart:io' show Platform;

/// App-wide constants for ChainTok
class AppConstants {
  AppConstants._();

  // ── Backend ────────────────────────────────────────────────────────
  /// Base URL of the ElysiaJS indexer backend.
  /// Auto-detects platform: Android emulator uses 10.0.2.2, others use 127.0.0.1.
  /// Override with --dart-define=API_BASE_URL=... for custom.
  static final String apiBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  ).isNotEmpty
      ? const String.fromEnvironment('API_BASE_URL')
      : Platform.isAndroid
          ? 'http://10.0.2.2:3000'
          : 'http://127.0.0.1:3000';

  // ── Solana ─────────────────────────────────────────────────────────
  /// RPC via backend proxy (avoids emulator DNS issues with devnet).
  static final String solanaRpcUrl = '$apiBaseUrl/rpc';
  static const String programId =
      'ArteCcRQqj14sy5BaS7iHDU8EmYURYWFCLh4opB97vS2';

  // ── Feed defaults ──────────────────────────────────────────────────────
  static const int feedPageSize = 20;
  static const int maxCaptionLength = 280;
  static const int maxCommentLength = 280;

  // ── Arweave ────────────────────────────────────────────────────────────
  static const String arweaveGateway = 'https://arweave.net';
}
