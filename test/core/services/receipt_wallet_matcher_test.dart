import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_app_flutter/core/services/receipt_wallet_matcher.dart';
import 'package:money_app_flutter/core/services/payment_alias_store.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

Wallet _wallet(String id, String name, WalletType type) =>
    Wallet(id: id, name: name, type: type, balance: 0, includeInTotal: true);

Transaction _tx(String walletId, DateTime date) => Transaction(
      id: 'tx-$walletId-${date.microsecondsSinceEpoch}',
      type: TransactionType.expense,
      amount: 10,
      category: 'Food',
      accountId: walletId,
      date: date,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptWalletMatcher — explicit bank/e-wallet name (beats generic card/type)', () {
    test('MAYBANK VISA resolves to the exact Maybank wallet, not a generic-card fallback', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        // Heavily used, so a generic-card fallback would otherwise pick this.
        _wallet('2', 'My Debit Card', WalletType.debitCard),
      ];
      final transactions = List.generate(10, (i) => _tx('2', DateTime(2026, 1, i + 1)));

      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'STORE ABC\nTOTAL 10.00\nMAYBANK VISA\n',
        wallets: wallets,
        transactions: transactions,
      );
      expect(wallet?.name, 'Maybank');
      expect(reason, 'explicit_wallet');
    });

    test('CIMB MASTERCARD resolves to the exact CIMB wallet', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        _wallet('2', 'CIMB', WalletType.bank),
      ];
      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'CIMB MASTERCARD',
        wallets: wallets,
      );
      expect(wallet?.name, 'CIMB');
      expect(reason, 'explicit_wallet');
    });

    test("TNG eWallet resolves to the exact Touch 'n Go wallet", () {
      final wallets = [
        _wallet('1', "Touch 'n Go", WalletType.eWallet),
        _wallet('2', 'GrabPay', WalletType.eWallet),
      ];
      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'PETRONAS STATION\nTNG eWallet\nTOTAL 20.00',
        wallets: wallets,
      );
      expect(wallet?.name, "Touch 'n Go");
      expect(reason, 'explicit_wallet');
    });

    test('MAE resolves to the exact MAE wallet', () {
      final wallets = [
        _wallet('1', 'MAE', WalletType.eWallet),
        _wallet('2', 'Maybank', WalletType.bank),
      ];
      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'PAID VIA MAE',
        wallets: wallets,
      );
      expect(wallet?.name, 'MAE');
      expect(reason, 'explicit_wallet');
    });
  });

  group('ReceiptWalletMatcher — explicit debit/credit qualifier -> most-used matching type', () {
    late List<Wallet> wallets;
    setUp(() {
      wallets = [
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
        _wallet('credit-1', 'My Credit Card', WalletType.creditCard),
      ];
    });

    test('VISA DEBIT selects the most-used debit-card wallet', () {
      final transactions = [_tx('debit-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA DEBIT', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'debit-1');
      expect(reason, 'debit_fallback');
    });

    test('DEBIT CARD selects the most-used debit-card wallet', () {
      final transactions = [_tx('debit-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'DEBIT CARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'debit-1');
      expect(reason, 'debit_fallback');
    });

    test('VISA CREDIT selects the most-used credit-card wallet', () {
      final transactions = [_tx('credit-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA CREDIT', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'credit-1');
      expect(reason, 'credit_fallback');
    });

    test('CREDIT CARD selects the most-used credit-card wallet', () {
      final transactions = [_tx('credit-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'CREDIT CARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'credit-1');
      expect(reason, 'credit_fallback');
    });
  });

  group('ReceiptWalletMatcher — bare card network (no debit/credit qualifier)', () {
    test('VISA alone searches both debit and credit wallets and picks the most-used', () {
      final wallets = [
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
        _wallet('credit-1', 'My Credit Card', WalletType.creditCard),
      ];
      final transactions = List.generate(5, (i) => _tx('credit-1', DateTime(2026, 1, i + 1)));

      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'credit-1');
      expect(reason, 'generic_card_fallback');
    });

    test('MASTERCARD alone searches both debit and credit wallets and picks the most-used', () {
      final wallets = [
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
        _wallet('credit-1', 'My Credit Card', WalletType.creditCard),
      ];
      final transactions = List.generate(5, (i) => _tx('debit-1', DateTime(2026, 1, i + 1)));

      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'MASTERCARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'debit-1');
      expect(reason, 'generic_card_fallback');
    });

    test('does not assume VISA always means debit or always means credit', () {
      final wallets = [
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
        _wallet('credit-1', 'My Credit Card', WalletType.creditCard),
      ];
      // Debit-card wallet is the most used here -> a bare "VISA" should
      // follow usage, not a hardcoded assumption about what VISA implies.
      final transactions = List.generate(3, (i) => _tx('debit-1', DateTime(2026, 1, i + 1)));
      final (wallet, _) = ReceiptWalletMatcher.match(rawText: 'VISA', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'debit-1');
    });
  });

  group('ReceiptWalletMatcher — generic e-wallet clue', () {
    test('a generic e-wallet clue (no specific brand) picks the most-used e-wallet', () {
      final wallets = [
        _wallet('ewallet-1', "Touch 'n Go", WalletType.eWallet),
        _wallet('ewallet-2', 'GrabPay', WalletType.eWallet),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      final transactions = List.generate(4, (i) => _tx('ewallet-2', DateTime(2026, 1, i + 1)));

      for (final rawText in ['PAID VIA E-WALLET', 'EWALLET PAYMENT', 'DUITNOW QR', 'SCAN QR PAY']) {
        final (wallet, reason) =
            ReceiptWalletMatcher.match(rawText: rawText, wallets: wallets, transactions: transactions);
        expect(wallet?.id, 'ewallet-2', reason: 'for rawText "$rawText"');
        expect(reason, 'ewallet_fallback');
      }
    });

    test('a specific e-wallet brand still wins over a generic e-wallet clue', () {
      final wallets = [
        _wallet('ewallet-1', "Touch 'n Go", WalletType.eWallet),
        _wallet('ewallet-2', 'GrabPay', WalletType.eWallet),
      ];
      // GrabPay is far more used, but the receipt names TNG explicitly.
      final transactions = List.generate(10, (i) => _tx('ewallet-2', DateTime(2026, 1, i + 1)));

      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'TOUCH N GO EWALLET PAYMENT',
        wallets: wallets,
        transactions: transactions,
      );
      expect(wallet?.id, 'ewallet-1');
      expect(reason, 'explicit_wallet');
    });
  });

  group('ReceiptWalletMatcher — unknown payment method', () {
    test('falls back to the most-used "others" wallet when there is no reliable clue', () {
      final wallets = [
        _wallet('others-1', 'Petty Cash Box', WalletType.others),
        _wallet('others-2', 'Misc', WalletType.others),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      final transactions = List.generate(3, (i) => _tx('others-1', DateTime(2026, 1, i + 1)));

      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'STORE ABC\nTOTAL 10.00\n',
        wallets: wallets,
        transactions: transactions,
      );
      expect(wallet?.id, 'others-1');
      expect(reason, 'others_fallback');
    });

    test('does not randomly choose from all wallets — only ever "others"', () {
      final wallets = [
        _wallet('bank-1', 'Maybank', WalletType.bank),
        _wallet('others-1', 'Misc', WalletType.others),
      ];
      final (wallet, _) = ReceiptWalletMatcher.match(rawText: 'STORE ABC\nTOTAL 10.00', wallets: wallets);
      expect(wallet?.id, 'others-1');
    });

    test('preserves the currently-selected wallet when no "others" wallet exists at all', () {
      final wallets = [
        _wallet('bank-1', 'Maybank', WalletType.bank),
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
      ];
      final current = wallets.first;

      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'STORE ABC\nTOTAL 10.00\n',
        wallets: wallets,
        currentWallet: current,
      );
      expect(wallet, current);
      expect(reason, 'preserve_current');
    });

    test('returns null with no crash when there is no fallback and no current wallet either', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];
      final (wallet, reason) = ReceiptWalletMatcher.match(rawText: 'STORE ABC\nTOTAL 10.00', wallets: wallets);
      expect(wallet, isNull);
      expect(reason, 'none');
    });
  });

  group('WalletUsageStats via ReceiptWalletMatcher — usage-count tie-breaking', () {
    test('a tie in usage count is broken by whichever wallet was most recently used', () {
      final wallets = [
        _wallet('debit-1', 'Card A', WalletType.debitCard),
        _wallet('debit-2', 'Card B', WalletType.debitCard),
      ];
      final transactions = [
        _tx('debit-1', DateTime(2026, 1, 1)),
        _tx('debit-2', DateTime(2026, 6, 1)), // same count (1 each), used more recently
      ];

      final (wallet, _) =
          ReceiptWalletMatcher.match(rawText: 'DEBIT CARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'debit-2');
    });
  });

  group('Wallet resolution priority — learned payment alias outranks every rule-based fallback', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a learned card fingerprint wins over what the rule-based matcher would otherwise pick', () async {
      final wallets = [
        _wallet('maybank-1', 'Maybank', WalletType.bank),
        _wallet('debit-1', 'My Debit Card', WalletType.debitCard),
      ];
      // Heavily used, so the generic-card fallback would otherwise pick this
      // instead of Maybank.
      final transactions = List.generate(10, (i) => _tx('debit-1', DateTime(2026, 1, i + 1)));

      // The user previously confirmed "VISA ****1234" belongs to Maybank.
      await PaymentAliasStore.learn('last4:1234', 'maybank-1');

      const rawText = 'VISA ****1234';
      final fingerprint = PaymentAliasStore.extractFingerprint(rawText);
      expect(fingerprint, 'last4:1234');

      final learnedWalletId = await PaymentAliasStore.lookup(fingerprint!);
      expect(learnedWalletId, 'maybank-1');

      // The rule-based matcher alone (ignoring the alias) would pick the
      // heavily-used generic-card fallback wallet instead of Maybank —
      // demonstrating why the alias must be checked first by the caller.
      final (ruleOnlyWallet, ruleOnlyReason) =
          ReceiptWalletMatcher.match(rawText: rawText, wallets: wallets, transactions: transactions);
      expect(ruleOnlyWallet?.id, 'debit-1');
      expect(ruleOnlyReason, 'generic_card_fallback');

      final resolvedWallet = wallets.where((w) => w.id == learnedWalletId).first;
      expect(resolvedWallet.name, 'Maybank');
    });
  });
}
