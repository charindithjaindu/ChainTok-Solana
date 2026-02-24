import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/main.dart';
import 'package:frontend/services/wallet_service.dart';
import 'package:frontend/providers/feed_provider.dart';

void main() {
  testWidgets('App shows connect wallet screen', (WidgetTester tester) async {
    final wallet = WalletService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: wallet),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: const ChainTokApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Should show ChainTok title on wallet connect screen
    expect(find.text('ChainTok'), findsOneWidget);
  });
}
