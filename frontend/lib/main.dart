import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'config/theme.dart';
import 'services/wallet_service.dart';
import 'services/solana_service.dart';
import 'services/api_service.dart';
import 'providers/feed_provider.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/upload/upload_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/profile_setup_screen.dart';
import 'screens/wallet/connect_wallet_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode (TikTok-style)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final walletService = WalletService();
  await walletService.init();

  final solanaService = SolanaService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: walletService),
        Provider.value(value: solanaService),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
      ],
      child: const ChainTokApp(),
    ),
  );
}

class ChainTokApp extends StatelessWidget {
  const ChainTokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChainTok',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const AppShell());
          case '/profile-setup':
            return MaterialPageRoute(builder: (_) => const ProfileSetupScreen());
          default:
            return null;
        }
      },
      home: Consumer<WalletService>(
        builder: (context, wallet, _) {
          if (!wallet.isConnected) {
            return const ConnectWalletScreen();
          }
          return const _ProfileGate();
        },
      ),
    );
  }
}

/// Checks if the user has a profile. If not, routes to ProfileSetupScreen.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate();

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  bool _checking = true;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final wallet = context.read<WalletService>();

    // In demo mode, skip profile gate
    if (wallet.mode == WalletMode.demo) {
      setState(() {
        _checking = false;
        _hasProfile = true;
      });
      return;
    }

    try {
      // Check backend cache first
      final api = ApiService();
      final profile = await api.getProfile(wallet.walletAddress!);
      if (profile != null && profile.displayName.isNotEmpty && profile.displayName != 'Anon') {
        setState(() {
          _checking = false;
          _hasProfile = true;
        });
        return;
      }

      // Check on-chain PDA existence
      final solana = context.read<SolanaService>();
      if (wallet.pubkey != null) {
        final pda = solana.findProfilePda(wallet.pubkey!);
        final exists = await solana.accountExists(pda);
        if (exists) {
          setState(() {
            _checking = false;
            _hasProfile = true;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Profile check error: $e');
    }

    setState(() {
      _checking = false;
      _hasProfile = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text(
                'Loading profile...',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasProfile) {
      return const ProfileSetupScreen();
    }

    return const AppShell();
  }
}

/// Main app shell with bottom navigation (TikTok-style layout).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final _screens = const [
    FeedScreen(),
    SizedBox(), // Discover placeholder
    UploadScreen(),
    SizedBox(), // Inbox placeholder
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          border: Border(
            top: BorderSide(
              color: AppTheme.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: FontAwesomeIcons.house,
                  label: 'Home',
                  isActive: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: FontAwesomeIcons.compass,
                  label: 'Discover',
                  isActive: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                // Center create button
                GestureDetector(
                  onTap: () => setState(() => _currentIndex = 2),
                  child: Container(
                    width: 44,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.solanaGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
                _NavItem(
                  icon: FontAwesomeIcons.inbox,
                  label: 'Inbox',
                  isActive: _currentIndex == 3,
                  onTap: () => setState(() => _currentIndex = 3),
                ),
                _NavItem(
                  icon: FontAwesomeIcons.user,
                  label: 'Profile',
                  isActive: _currentIndex == 4,
                  onTap: () => setState(() => _currentIndex = 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color:
                    isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
