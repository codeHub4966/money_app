import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/add_transaction_screen/add_transaction_screen.dart';
import '../../presentation/screens/budget/new_transaction_screen.dart';
import '../../presentation/screens/budget/add_budget_screen.dart';
import '../../presentation/screens/wallet/add_wallet_screen.dart';
import '../../presentation/screens/wallet/transfer_funds_screen.dart';
import '../../presentation/screens/budget/budget_screen.dart';
import '../../presentation/screens/budget/budget_detail_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/pin_screen.dart';
import '../../presentation/screens/home/transaction_details_screen.dart';
import '../../presentation/screens/wallet/wallet_screen.dart';
import '../../presentation/screens/wallet/wallet_account_screen.dart';
import '../../presentation/screens/settings/category_management_screen.dart';
import '../../presentation/widgets/bottom_nav.dart';
import '../../domain/models/transaction.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
          GoRoute(path: '/budget', builder: (c, s) => const BudgetScreen()),
          GoRoute(path: '/wallet', builder: (c, s) => const WalletScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        ],
      ),
      GoRoute(path: '/add-transaction', builder: (c, s) => const AddTransactionScreen()),
      GoRoute(
        path: '/edit-transaction',
        builder: (c, s) => AddTransactionScreen(transaction: s.extra as Transaction?),
      ),
      GoRoute(
        path: '/new-transaction',
        builder: (c, s) {
          final extra = s.extra as Map<String, String?>?;
          return NewTransactionScreen(
            title: extra?['title'],
            initialCategoryId: extra?['categoryId'],
            initialAmount: extra?['amount'],
          );
        },
      ),
      GoRoute(
        path: '/add-wallet',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AddWalletScreen(
            initialId: extra?['id'] as String?,
            initialName: extra?['name'] as String?,
            initialType: extra?['type'] as String?,
            initialBalance: (extra?['balance'] as num?)?.toDouble(),
            initialIncludeInTotal: extra?['includeInTotal'] as bool?,
          );
        },
      ),
      GoRoute(path: '/add-budget', builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return AddBudgetScreen(
          initialId: extra?['id'] as String?,
          initialCategory: extra?['category'] as String?,
          initialLimit: (extra?['limit'] as num?)?.toDouble(),
        );
      }),
      GoRoute(path: '/transfer', builder: (c, s) => const TransferFundsScreen()),
      GoRoute(
        path: '/budget/:category',
        builder: (c, s) => BudgetDetailScreen(categoryName: s.pathParameters['category']),
      ),
      GoRoute(path: '/categories', builder: (c, s) => const CategoryManagementScreen()),
      GoRoute(path: '/pin', builder: (c, s) => const PinScreen()),
      GoRoute(
        path: '/transaction-details',
        builder: (c, s) => TransactionDetailsScreen(transaction: s.extra as Transaction?),
      ),
      GoRoute(
        path: '/wallet-account',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return WalletAccountScreen(
            id: extra['id'] as String? ?? '',
            name: extra['name'] as String? ?? '',
            type: extra['type'] as String? ?? 'bank',
            balance: (extra['balance'] as num?)?.toDouble() ?? 0,
            includeInTotal: extra['includeInTotal'] as bool? ?? true,
          );
        },
      ),
    ],
  );
});

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = switch (location) {
      '/budget' => 1,
      '/wallet' => 3,
      '/settings' => 4,
      _ => 0,
    };
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavBar(
        currentIndex: index,
        onTap: (i) {
          switch (i) {
            case 0: context.go('/');
            case 1: context.go('/budget');
            case 2: context.push('/add-transaction');
            case 3: context.go('/wallet');
            case 4: context.go('/settings');
          }
        },
      ),
    );
  }
}
