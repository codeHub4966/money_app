import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/presentation/screens/add_transaction_screen/add_transaction_screen.dart';
import 'package:money_app_flutter/core/services/public_bank_receipt_parser.dart';
import 'package:money_app_flutter/core/services/maybank_receipt_parser.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

Wallet _wallet(String id, String name, WalletType type) =>
    Wallet(id: id, name: name, type: type, balance: 0, includeInTotal: true);

void main() {
  group('receiptPermanentPath', () {
    test('builds the deterministic per-transaction receipt path', () {
      expect(receiptPermanentPath('/docs', 't1'), '/docs/receipts/t1.jpg');
    });
  });

  group(
      'isAlreadyPermanentReceiptPath (requirement 6A: no self-copy on edit)',
      () {
    test('true when the candidate path is already the permanent file', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/docs/receipts/t1.jpg', '/docs', 't1'),
        isTrue,
      );
    });

    test('false for a fresh picker temp path (new photo)', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/tmp/cache/image_picker_123.jpg', '/docs', 't1'),
        isFalse,
      );
    });

    test('false when it is another transaction\'s permanent path', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/docs/receipts/other-tx.jpg', '/docs', 't1'),
        isFalse,
      );
    });
  });

  group('shouldDeleteOldReceipt (requirements 6B/6C: replace/remove cleanup)',
      () {
    test('false when there was no old receipt', () {
      expect(shouldDeleteOldReceipt(null, '/docs/receipts/t1.jpg'), isFalse);
    });

    test(
        'false when unchanged — editing without touching the receipt overwrites in place',
        () {
      expect(
        shouldDeleteOldReceipt(
            '/docs/receipts/t1.jpg', '/docs/receipts/t1.jpg'),
        isFalse,
      );
    });

    test('true when the receipt was removed (new path is null)', () {
      expect(shouldDeleteOldReceipt('/docs/receipts/t1.jpg', null), isTrue);
    });

    test('true when replaced by a genuinely different path', () {
      expect(
        shouldDeleteOldReceipt(
            '/docs/receipts/t1.jpg', '/docs/receipts/other.jpg'),
        isTrue,
      );
    });
  });

  group('tryParseAsTngReceipt (TNG screenshot routing)', () {
    const tngTransferredText = '''
RM 0.02
Transferred
Receiver CHANG NYET CHING
Remark snacks
Date & Time 14/09/2026 17:20:36
''';

    test('a confidently-detected TNG screenshot is routed to TngReceiptParser', () {
      final result = tryParseAsTngReceipt(
        tngTransferredText,
        existingCategoryLabels: ['Snacks'],
      );

      expect(result, isNotNull);
      expect(result!.amount, 0.02);
      expect(result.counterpartyName, 'CHANG NYET CHING');
      expect(result.note, 'snacks - Transfer to CHANG NYET CHING');
      expect(result.category, 'Snacks');
    });

    test('a normal paper receipt is not routed to TngReceiptParser (null)', () {
      const receiptText = '''
99 Speed Mart
Milk 5.00
Bread 3.20
TOTAL 8.20
CASH 10.00
CHANGE 1.80
''';
      expect(tryParseAsTngReceipt(receiptText), isNull);
    });

    test(
        'the TNG result comes only from TngReceiptParser — the generic receipt parser '
        'never runs on (and so can never overwrite) a detected TNG screenshot', () {
      final result = tryParseAsTngReceipt(tngTransferredText);
      // A generic parser reading this text would treat "Transferred" as the
      // merchant name (the first plausible-looking line) — that value must
      // never leak into the TNG result.
      expect(result!.counterpartyName, isNot('Transferred'));
      expect(result.counterpartyName, 'CHANG NYET CHING');
    });
  });

  group('resolveTngWallet', () {
    test('a unique TNG-named wallet is selected when available', () {
      final wallets = [
        _wallet('tng-1', 'TnG Account', WalletType.eWallet),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];

      final (wallet, reason) = resolveTngWallet(
        rawText: 'RM 0.02\nTransferred\nReceiver CHANG NYET CHING',
        wallets: wallets,
      );

      expect(wallet?.id, 'tng-1');
      expect(reason, 'tng_wallet');
    });

    test('safely falls back to the generic matcher when no TNG wallet exists', () {
      final wallets = [
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];

      final (wallet, reason) = resolveTngWallet(
        rawText: 'MAYBANK VISA',
        wallets: wallets,
      );

      expect(wallet?.id, 'bank-1');
      expect(reason, 'explicit_wallet');
    });

    test('never forces the wrong account when no TNG wallet and no other clue exists', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];
      final current = wallets.first;

      final (wallet, reason) = resolveTngWallet(
        rawText: 'RM 0.02\nTransferred\nReceiver CHANG NYET CHING',
        wallets: wallets,
        currentWallet: current,
      );

      expect(wallet, current);
      expect(reason, 'preserve_current');
    });
  });

  group('tryParseAsPublicBankReceipt (Public Bank screenshot routing)', () {
    const moneySentText = '''
Money Sent
RM 0.01
Recipient Reference rice
Recipient Bank Public Bank Berhad
Recipient Account CHANG NYET CHING O/B AU
4450438109
From Account ******6316
''';

    const moneyPaidText = '''
Money Paid
RM 0.01
Payment Method DuitNow QR
Recipient Name AU XIAO YEW
Recipient's Bank TNG DIGITAL SDN BHD
From Account ******6316
''';

    test('a Money Sent screenshot is routed to PublicBankReceiptParser', () {
      final result = tryParseAsPublicBankReceipt(
        moneySentText,
        existingCategoryLabels: ['Groceries'],
      );

      expect(result, isNotNull);
      expect(result!.kind, PublicBankTransactionKind.moneySent);
      expect(result.amount, 0.01);
      expect(result.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
      expect(result.note, 'rice - Sent to CHANG NYET CHING O/B AU 4450438109');
    });

    test('a Money Paid screenshot is routed to PublicBankReceiptParser', () {
      final result = tryParseAsPublicBankReceipt(moneyPaidText);

      expect(result, isNotNull);
      expect(result!.kind, PublicBankTransactionKind.moneyPaid);
      expect(result.amount, 0.01);
      expect(result.recipientName, 'AU XIAO YEW');
      expect(result.note, 'Paid to AU XIAO YEW');
    });

    test('a normal paper receipt is not routed to PublicBankReceiptParser (null)', () {
      const receiptText = '''
99 Speed Mart
Milk 5.00
Bread 3.20
TOTAL 8.20
CASH 10.00
CHANGE 1.80
''';
      expect(tryParseAsPublicBankReceipt(receiptText), isNull);
    });

    test(
        'the Public Bank result comes only from PublicBankReceiptParser — the generic receipt '
        'parser never runs on (and so can never overwrite) a detected screenshot', () {
      final result = tryParseAsPublicBankReceipt(moneySentText);
      // A generic parser reading this text would treat "Money Sent" as the
      // merchant name (the first plausible-looking line) — that value must
      // never leak into the Public Bank result.
      expect(result!.recipientAccount, isNot('Money Sent'));
      expect(result.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
    });
  });

  group('resolvePublicBankWallet', () {
    test('a unique Public Bank-named wallet is selected when available', () {
      final wallets = [
        _wallet('pbb-1', 'Public Bank Account', WalletType.bank),
        _wallet('bank-1', 'Maybank', WalletType.bank),
      ];

      final (wallet, reason) = resolvePublicBankWallet(
        rawText: 'Money Sent\nRM 0.01\nRecipient Reference rice',
        wallets: wallets,
      );

      expect(wallet?.id, 'pbb-1');
      expect(reason, 'public_bank_wallet');
    });

    test('safely falls back to the generic matcher when no Public Bank wallet exists', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];

      final (wallet, reason) = resolvePublicBankWallet(
        rawText: 'MAYBANK VISA',
        wallets: wallets,
      );

      expect(wallet?.id, 'bank-1');
      expect(reason, 'explicit_wallet');
    });

    test('never forces the wrong account when no Public Bank wallet and no other clue exists', () {
      final wallets = [_wallet('bank-1', 'Maybank', WalletType.bank)];
      final current = wallets.first;

      final (wallet, reason) = resolvePublicBankWallet(
        rawText: 'Money Sent\nRM 0.01\nRecipient Reference rice',
        wallets: wallets,
        currentWallet: current,
      );

      expect(wallet, current);
      expect(reason, 'preserve_current');
    });
  });

  group('tryParseAsMaybankReceipt (Maybank screenshot routing)', () {
    const scanAndPayText = '''
Maybank
Scan and Pay
Merchant Name AUXIAOYEW
Amount RM 0.01
''';

    const transferText = '''
Maybank
Third Party Transfer
Beneficiary Name AU XIAO XUAN
Beneficiary Account Number 158284304009
Recipient Reference hhhh
Amount RM 5.20
''';

    test('a Scan and Pay screenshot is routed to MaybankReceiptParser', () {
      final result = tryParseAsMaybankReceipt(scanAndPayText);

      expect(result, isNotNull);
      expect(result!.type, MaybankReceiptType.scanAndPay);
      expect(result.amount, 0.01);
      expect(result.merchantName, 'AUXIAOYEW');
      expect(result.note, 'AUXIAOYEW');
    });

    test('a transfer screenshot is routed to MaybankReceiptParser', () {
      final result = tryParseAsMaybankReceipt(transferText);

      expect(result, isNotNull);
      expect(result!.type, MaybankReceiptType.duitNowTransfer);
      expect(result.amount, 5.20);
      expect(result.beneficiaryName, 'AU XIAO XUAN');
      expect(result.note, 'hhhh - AU XIAO XUAN');
    });

    test('a normal paper receipt is not routed to MaybankReceiptParser (null)', () {
      const receiptText = '''
99 Speed Mart
Milk 5.00
Bread 3.20
TOTAL 8.20
CASH 10.00
CHANGE 1.80
''';
      expect(tryParseAsMaybankReceipt(receiptText), isNull);
    });

    test(
        'the Maybank result comes only from MaybankReceiptParser — the generic receipt parser '
        'never runs on (and so can never overwrite) a detected screenshot', () {
      final result = tryParseAsMaybankReceipt(transferText);
      expect(result!.beneficiaryName, isNot('Third Party Transfer'));
      expect(result.beneficiaryName, 'AU XIAO XUAN');
    });
  });

  group('resolveMaybankWallet', () {
    test('a unique Maybank-named wallet is selected when available', () {
      final wallets = [
        _wallet('mbb-1', 'Maybank', WalletType.bank),
        _wallet('bank-1', 'Public Bank', WalletType.bank),
      ];

      final (wallet, reason) = resolveMaybankWallet(
        rawText: 'Maybank\nScan and Pay\nMerchant Name AUXIAOYEW',
        wallets: wallets,
      );

      expect(wallet?.id, 'mbb-1');
      expect(reason, 'maybank_wallet');
    });

    test('does not prefer a MAE wallet unless the OCR text clearly names MAE', () {
      final wallets = [
        _wallet('mae-1', 'MAE', WalletType.eWallet),
        _wallet('mbb-1', 'Maybank', WalletType.bank),
      ];

      final (wallet, reason) = resolveMaybankWallet(
        rawText: 'Maybank\nScan and Pay\nMerchant Name AUXIAOYEW',
        wallets: wallets,
      );
      expect(wallet?.id, 'mbb-1');
      expect(reason, 'maybank_wallet');

      final (maeWallet, maeReason) = resolveMaybankWallet(
        rawText: 'Maybank\nSource: MAE Wallet\nMerchant Name AUXIAOYEW',
        wallets: wallets,
      );
      expect(maeWallet?.id, 'mae-1');
      expect(maeReason, 'maybank_wallet');
    });

    test('safely falls back to the generic matcher when no Maybank wallet exists', () {
      final wallets = [_wallet('bank-1', 'Public Bank', WalletType.bank)];

      final (wallet, reason) = resolveMaybankWallet(
        rawText: 'PUBLIC BANK',
        wallets: wallets,
      );

      expect(wallet?.id, 'bank-1');
      expect(reason, 'explicit_wallet');
    });

    test('never forces the wrong account when no Maybank wallet and no other clue exists', () {
      final wallets = [_wallet('bank-1', 'Public Bank', WalletType.bank)];
      final current = wallets.first;

      final (wallet, reason) = resolveMaybankWallet(
        rawText: 'Maybank\nScan and Pay\nMerchant Name AUXIAOYEW',
        wallets: wallets,
        currentWallet: current,
      );

      expect(wallet, current);
      expect(reason, 'preserve_current');
    });
  });
}
