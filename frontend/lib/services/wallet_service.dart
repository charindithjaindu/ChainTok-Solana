import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:solana_web3/solana_web3.dart' as web3;

/// Manages wallet connection state via Solana Mobile Wallet Adapter (Android).
///
/// Supports:
/// 1. **MWA** – Real wallet connection via any MWA-compatible wallet (Phantom,
///    Solflare, etc.) on Android.
/// 2. **Demo mode** – Quick-connect with a generated dev address for testing.
///
/// The service also exposes [signAndSendTransactions] so the rest of the app
/// can hand off unsigned transactions to the wallet for signing + submission.
class WalletService extends ChangeNotifier {
  static const _keyWalletAddress = 'wallet_address';
  static const _keyWalletMode = 'wallet_mode';
  static const _keyAuthToken = 'auth_token';

  String? _walletAddress;
  Uint8List? _publicKeyBytes;
  String? _authToken;
  WalletMode _mode = WalletMode.disconnected;
  bool _isConnecting = false;

  String? get walletAddress => _walletAddress;
  Uint8List? get publicKeyBytes => _publicKeyBytes;
  String? get authToken => _authToken;
  WalletMode get mode => _mode;
  bool get isConnected => _walletAddress != null;
  bool get isConnecting => _isConnecting;

  /// Solana web3 Pubkey for use in transaction building.
  web3.Pubkey? get pubkey =>
      _walletAddress != null ? web3.Pubkey.fromBase58(_walletAddress!) : null;

  /// Short display format: "ABcd...xYz1"
  String get walletShort {
    if (_walletAddress == null || _walletAddress!.length <= 8) {
      return _walletAddress ?? '';
    }
    return '${_walletAddress!.substring(0, 4)}...${_walletAddress!.substring(_walletAddress!.length - 4)}';
  }

  // ── Init: restore from prefs ──────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _walletAddress = prefs.getString(_keyWalletAddress);
    _authToken = prefs.getString(_keyAuthToken);
    final modeStr = prefs.getString(_keyWalletMode);
    if (modeStr == 'demo') {
      _mode = WalletMode.demo;
    } else if (modeStr == 'mwa') {
      _mode = WalletMode.mwa;
      // Reconstruct pubkey bytes from base58 address
      if (_walletAddress != null) {
        try {
          _publicKeyBytes =
              web3.Pubkey.fromBase58(_walletAddress!).toBytes();
        } catch (_) {
          await disconnect();
          return;
        }
      }
    }
    notifyListeners();
  }

  // ── MWA connect (Android) ─────────────────────────────────────────────

  /// Connect via Solana Mobile Wallet Adapter.
  /// Opens the wallet app for authorization then stores the auth token
  /// and public key.
  Future<void> connectMwa() async {
    _isConnecting = true;
    notifyListeners();

    try {
      final session = await LocalAssociationScenario.create();
      // Fire-and-forget: opens Phantom without blocking the WebSocket handshake
      session.startActivityForResult(null);
      final client = await session.start();

      final result = await client.authorize(
        identityUri: Uri.parse('https://chaintok.app'),
        iconUri: Uri.parse('favicon.ico'),
        identityName: 'ChainTok',
        cluster: 'devnet',
      );

      if (result != null) {
        _publicKeyBytes = result.publicKey;
        _authToken = result.authToken;
        _walletAddress =
            web3.Pubkey.fromUint8List(result.publicKey).toBase58();
        _mode = WalletMode.mwa;
        await _persist();
      }

      await session.close();
    } catch (e) {
      debugPrint('MWA connect error: $e');
      rethrow;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // ── Sign & send transactions via MWA ──────────────────────────────────

  /// Takes **serialized** unsigned transactions, opens the wallet for signing,
  /// then submits via the provided RPC connection. Returns the tx signature(s).
  Future<List<Uint8List>> signAndSendTransactions(
    List<Uint8List> serializedTransactions, {
    web3.Connection? connection,
  }) async {
    if (_mode == WalletMode.demo) {
      // In demo mode we can't actually sign — return fake sigs
      return serializedTransactions
          .map((_) => Uint8List(64))
          .toList();
    }

    if (_authToken == null) {
      throw WalletException('Not authorized — connect wallet first');
    }

    final session = await LocalAssociationScenario.create();
    session.startActivityForResult(null);
    final client = await session.start();

    try {
      // Re-authorize to refresh the session token
      final reauth = await client.reauthorize(
        identityUri: Uri.parse('https://chaintok.app'),
        iconUri: Uri.parse('favicon.ico'),
        identityName: 'ChainTok',
        authToken: _authToken!,
      );

      if (reauth != null) {
        _authToken = reauth.authToken;
        await _persist();
      }

      // Sign only — don't let the wallet submit
      final signResult = await client.signTransactions(
        transactions: serializedTransactions,
      );

      final signedTxs = signResult.signedPayloads;

      await session.close();

      // Submit signed transactions ourselves via our RPC
      if (connection != null) {
        for (final signedTx in signedTxs) {
          try {
            final b64 = base64.encode(signedTx);
            final sig = await connection.sendSignedTransactionRaw(b64);
            debugPrint('Transaction submitted: ${sig.result}');
          } catch (e) {
            debugPrint('Transaction submission error: $e');
            rethrow;
          }
        }
      }

      return signedTxs;
    } catch (e) {
      try { await session.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Convenience: serialize a [web3.Transaction], sign via MWA, submit via
  /// RPC, return the first signature bytes.
  Future<Uint8List> signAndSendTransaction(
    web3.Transaction tx, {
    web3.Connection? connection,
  }) async {
    final serialized = tx.serialize().asUint8List();
    final sigs = await signAndSendTransactions(
      [serialized],
      connection: connection,
    );
    if (sigs.isEmpty) throw WalletException('No signature returned');
    return sigs.first;
  }

  // ── Demo mode connect ─────────────────────────────────────────────────

  /// Quick connect with a deterministic demo address (for testing/demo).
  Future<void> connectDemo() async {
    _isConnecting = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    _walletAddress = _generateDemoAddress();
    _mode = WalletMode.demo;
    _authToken = null;
    _publicKeyBytes = null;
    await _persist();

    _isConnecting = false;
    notifyListeners();
  }

  // ── Disconnect ────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    // If we have an MWA auth token, deauthorize
    if (_mode == WalletMode.mwa && _authToken != null) {
      try {
        final session = await LocalAssociationScenario.create();
        session.startActivityForResult(null);
        final client = await session.start();
        await client.deauthorize(authToken: _authToken!);
        await session.close();
      } catch (_) {
        // Best-effort deauthorize
      }
    }

    _walletAddress = null;
    _publicKeyBytes = null;
    _authToken = null;
    _mode = WalletMode.disconnected;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWalletAddress);
    await prefs.remove(_keyWalletMode);
    await prefs.remove(_keyAuthToken);
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_walletAddress != null) {
      await prefs.setString(_keyWalletAddress, _walletAddress!);
    }
    if (_authToken != null) {
      await prefs.setString(_keyAuthToken, _authToken!);
    }
    await prefs.setString(_keyWalletMode, _mode.name);
  }

  /// Generate a realistic-looking Solana address for demo mode.
  String _generateDemoAddress() {
    const chars =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    final rng = Random(42); // deterministic seed
    return String.fromCharCodes(
      Iterable.generate(
        44,
        (_) => chars.codeUnitAt(rng.nextInt(chars.length)),
      ),
    );
  }
}

enum WalletMode { disconnected, demo, mwa }

class WalletException implements Exception {
  final String message;
  WalletException(this.message);

  @override
  String toString() => 'WalletException: $message';
}
