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
        _wallet('2', 'My Debit Card', WalletType.card),
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

  group('ReceiptWalletMatcher — card clue (debit/credit qualifier or bare network) -> most-used card wallet', () {
    late List<Wallet> wallets;
    setUp(() {
      wallets = [
        _wallet('card-1', 'My Card A', WalletType.card),
        _wallet('card-2', 'My Card B', WalletType.card),
      ];
    });

    test('VISA DEBIT selects the most-used card wallet', () {
      final transactions = [_tx('card-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA DEBIT', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-1');
      expect(reason, 'card_fallback');
    });

    test('DEBIT CARD selects the most-used card wallet', () {
      final transactions = [_tx('card-1', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'DEBIT CARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-1');
      expect(reason, 'card_fallback');
    });

    test('VISA CREDIT selects the most-used card wallet', () {
      final transactions = [_tx('card-2', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA CREDIT', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-2');
      expect(reason, 'card_fallback');
    });

    test('CREDIT CARD selects the most-used card wallet', () {
      final transactions = [_tx('card-2', DateTime(2026, 1, 1))];
      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'CREDIT CARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-2');
      expect(reason, 'card_fallback');
    });

    test('VISA alone (no debit/credit qualifier) also picks the most-used card wallet', () {
      final transactions = List.generate(5, (i) => _tx('card-2', DateTime(2026, 1, i + 1)));

      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'VISA', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-2');
      expect(reason, 'card_fallback');
    });

    test('MASTERCARD alone also picks the most-used card wallet', () {
      final transactions = List.generate(5, (i) => _tx('card-1', DateTime(2026, 1, i + 1)));

      final (wallet, reason) =
          ReceiptWalletMatcher.match(rawText: 'MASTERCARD', wallets: wallets, transactions: transactions);
      expect(wallet?.id, 'card-1');
      expect(reason, 'card_fallback');
    });
  });

  group('ReceiptWalletMatcher — cash clue with no matching wallet name -> most-used cash wallet', () {
    test('a cash keyword with no uniquely-named "cash" wallet falls back to the most-used cash-type wallet', () {
      final wallets = [
        _wallet('cash-1', 'Petty Cash Box', WalletType.cash),
        _wallet('cash-2', 'Wallet Cash', WalletType.cash),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      final transactions = List.generate(3, (i) => _tx('cash-1', DateTime(2026, 1, i + 1)));

      final (wallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'STORE ABC\nCASH\nTOTAL 10.00\n',
        wallets: wallets,
        transactions: transactions,
      );
      expect(wallet?.id, 'cash-1');
      expect(reason, 'cash_fallback');
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
        _wallet('debit-1', 'My Debit Card', WalletType.card),
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
        _wallet('debit-1', 'Card A', WalletType.card),
        _wallet('debit-2', 'Card B', WalletType.card),
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
        _wallet('debit-1', 'My Debit Card', WalletType.card),
      ];
      // Heavily used, so the card fallback would otherwise pick this instead
      // of Maybank.
      final transactions = List.generate(10, (i) => _tx('debit-1', DateTime(2026, 1, i + 1)));

      // The user previously confirmed "VISA ****1234" belongs to Maybank.
      await PaymentAliasStore.learn('last4:1234', 'maybank-1');

      const rawText = 'VISA ****1234';
      final fingerprint = PaymentAliasStore.extractFingerprint(rawText);
      expect(fingerprint, 'last4:1234');

      final learnedWalletId = await PaymentAliasStore.lookup(fingerprint!);
      expect(learnedWalletId, 'maybank-1');

      // The rule-based matcher alone (ignoring the alias) would pick the
      // heavily-used card fallback wallet instead of Maybank — demonstrating
      // why the alias must be checked first by the caller.
      final (ruleOnlyWallet, ruleOnlyReason) =
          ReceiptWalletMatcher.match(rawText: rawText, wallets: wallets, transactions: transactions);
      expect(ruleOnlyWallet?.id, 'debit-1');
      expect(ruleOnlyReason, 'card_fallback');

      final resolvedWallet = wallets.where((w) => w.id == learnedWalletId).first;
      expect(resolvedWallet.name, 'Maybank');
    });
  });

  group('findUniqueTngWallet — TNG screenshot wallet resolution', () {
    test('matches without the OCR text ever containing "Touch \'n Go"', () {
      final wallets = [
        _wallet('tng-1', 'TnG Account', WalletType.eWallet),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      final wallet = ReceiptWalletMatcher.findUniqueTngWallet(wallets);
      expect(wallet?.id, 'tng-1');
    });

    for (final name in ['TnG', 'TNG', 'Touch n Go', "Touch 'n Go", 'Touch & Go', 'Touch n Go eWallet']) {
      test('matches wallet name variant "$name"', () {
        final wallets = [
          _wallet('tng-1', name, WalletType.eWallet),
          _wallet('other-1', 'GrabPay', WalletType.eWallet),
        ];
        final wallet = ReceiptWalletMatcher.findUniqueTngWallet(wallets);
        expect(wallet?.id, 'tng-1');
      });
    }

    test('returns null (safe fallback) when there is no TNG-named wallet at all', () {
      final wallets = [
        _wallet('bank-1', 'Maybank', WalletType.bank),
        _wallet('ewallet-1', 'GrabPay', WalletType.eWallet),
      ];
      expect(ReceiptWalletMatcher.findUniqueTngWallet(wallets), isNull);
    });

    test('returns null (ambiguous) rather than guessing when more than one wallet matches', () {
      final wallets = [
        _wallet('tng-1', 'TNG', WalletType.eWallet),
        _wallet('tng-2', "Touch 'n Go", WalletType.eWallet),
      ];
      expect(ReceiptWalletMatcher.findUniqueTngWallet(wallets), isNull);
    });
  });

  group('resolveTngWallet-style usage: unique TNG wallet beats the generic matcher', () {
    test('a unique TNG-named wallet is preferred even when the OCR text names another brand', () {
      final wallets = [
        _wallet('tng-1', 'TnG Account', WalletType.eWallet),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      final tngWallet = ReceiptWalletMatcher.findUniqueTngWallet(wallets);
      expect(tngWallet?.id, 'tng-1');

      // The generic matcher, if consulted instead, would pick differently —
      // demonstrating why a caller must check findUniqueTngWallet first for
      // a screenshot already confirmed to be TNG.
      final (genericWallet, genericReason) = ReceiptWalletMatcher.match(
        rawText: 'MAYBANK VISA',
        wallets: wallets,
      );
      expect(genericWallet?.id, 'bank-1');
      expect(genericReason, 'explicit_wallet');
    });

    test('falls back to the generic matcher when no unique TNG wallet exists', () {
      final wallets = [
        _wallet('bank-1', 'Maybank', WalletType.bank),
        _wallet('card-1', 'My Debit Card', WalletType.card),
      ];
      expect(ReceiptWalletMatcher.findUniqueTngWallet(wallets), isNull);

      final (fallbackWallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'RM 0.02\nTransferred\nReceiver CHANG NYET CHING',
        wallets: wallets,
        currentWallet: wallets.first,
      );
      // No reliable clue in that text, and no "others" wallet exists either
      // — the safe fallback preserves whatever was already selected rather
      // than forcing the wrong account.
      expect(fallbackWallet, wallets.first);
      expect(reason, 'preserve_current');
    });
  });

  group('findUniquePublicBankWallet — Public Bank screenshot wallet resolution', () {
    for (final name in ['Public Bank', 'PBB', 'Public Bank Account']) {
      test('matches wallet name variant "$name"', () {
        final wallets = [
          _wallet('pbb-1', name, WalletType.bank),
          _wallet('other-1', 'Maybank', WalletType.bank),
        ];
        final wallet = ReceiptWalletMatcher.findUniquePublicBankWallet(wallets);
        expect(wallet?.id, 'pbb-1');
      });
    }

    test('matches without the OCR text ever containing "Public Bank"', () {
      final wallets = [
        _wallet('pbb-1', 'PBB', WalletType.bank),
        _wallet('other-1', 'Maybank', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniquePublicBankWallet(wallets)?.id, 'pbb-1');
    });

    test('returns null (safe fallback) when there is no Public Bank-named wallet at all', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];
      expect(ReceiptWalletMatcher.findUniquePublicBankWallet(wallets), isNull);
    });

    test('returns null (ambiguous) rather than guessing when more than one wallet matches', () {
      final wallets = [
        _wallet('pbb-1', 'Public Bank', WalletType.bank),
        _wallet('pbb-2', 'PBB Savings', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniquePublicBankWallet(wallets), isNull);
    });
  });

  group('resolvePublicBankWallet-style usage: unique Public Bank wallet beats the generic matcher', () {
    test('a unique Public Bank wallet is preferred even when the OCR text names another brand', () {
      final wallets = [
        _wallet('pbb-1', 'Public Bank', WalletType.bank),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniquePublicBankWallet(wallets)?.id, 'pbb-1');
    });

    test('falls back to the generic matcher when no matching Public Bank wallet exists', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];
      expect(ReceiptWalletMatcher.findUniquePublicBankWallet(wallets), isNull);

      final (fallbackWallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'MAYBANK VISA',
        wallets: wallets,
      );
      expect(fallbackWallet?.id, 'bank-1');
      expect(reason, 'explicit_wallet');
    });
  });

  group('findUniqueMaybankWallet — Maybank screenshot wallet resolution', () {
    for (final name in ['Maybank', 'MBB']) {
      test('matches wallet name variant "$name"', () {
        final wallets = [
          _wallet('mbb-1', name, WalletType.bank),
          _wallet('other-1', 'Public Bank', WalletType.bank),
        ];
        final wallet = ReceiptWalletMatcher.findUniqueMaybankWallet(wallets);
        expect(wallet?.id, 'mbb-1');
      });
    }

    test('does NOT match a "MAE" wallet by default, even though it is a Maybank sub-account', () {
      final wallets = [
        _wallet('mae-1', 'MAE', WalletType.eWallet),
        _wallet('bank-1', 'Public Bank', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniqueMaybankWallet(wallets), isNull);
    });

    test('matches a "MAE" wallet only when preferMae is true', () {
      final wallets = [
        _wallet('mae-1', 'MAE', WalletType.eWallet),
        _wallet('mbb-1', 'Maybank', WalletType.bank),
      ];
      final withoutPreference = ReceiptWalletMatcher.findUniqueMaybankWallet(wallets);
      expect(withoutPreference?.id, 'mbb-1');

      final withPreference = ReceiptWalletMatcher.findUniqueMaybankWallet(wallets, preferMae: true);
      expect(withPreference?.id, 'mae-1');
    });

    test('returns null (safe fallback) when there is no matching wallet at all', () {
      final wallets = [_wallet('bank-1', 'Public Bank', WalletType.bank)];
      expect(ReceiptWalletMatcher.findUniqueMaybankWallet(wallets), isNull);
    });

    test('returns null (ambiguous) rather than guessing when more than one Maybank wallet matches', () {
      final wallets = [
        _wallet('mbb-1', 'Maybank', WalletType.bank),
        _wallet('mbb-2', 'Maybank Savings', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniqueMaybankWallet(wallets), isNull);
    });
  });

  group('resolveMaybankWallet-style usage: unique Maybank wallet beats the generic matcher', () {
    test('a unique Maybank wallet is preferred even when the OCR text names another brand', () {
      final wallets = [
        _wallet('mbb-1', 'Maybank', WalletType.bank),
        _wallet('bank-1', 'Public Bank', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.findUniqueMaybankWallet(wallets)?.id, 'mbb-1');
    });

    test('falls back to the generic matcher when no matching Maybank wallet exists', () {
      final wallets = [_wallet('bank-1', 'Public Bank', WalletType.bank)];
      expect(ReceiptWalletMatcher.findUniqueMaybankWallet(wallets), isNull);

      final (fallbackWallet, reason) = ReceiptWalletMatcher.match(
        rawText: 'PUBLIC BANK',
        wallets: wallets,
      );
      expect(fallbackWallet?.id, 'bank-1');
      expect(reason, 'explicit_wallet');
    });
  });
}
