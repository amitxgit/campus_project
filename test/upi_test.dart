import 'package:campus_track/core/models/fee.dart';
import 'package:campus_track/core/models/institution_settings.dart';
import 'package:campus_track/core/models/parent_alert.dart';
import 'package:campus_track/core/utils/upi.dart';
import 'package:campus_track/features/fees/fee_messages.dart';
import 'package:flutter_test/flutter_test.dart';

const base = 'https://pay.example.test';

FeeAccount account({double paid = 0}) => FeeAccount(
      studentId: 's1',
      studentName: 'Riya Sharma',
      section: 'JEE-A',
      totalFee: 30000,
      discount: 0,
      instalments: [
        FeeInstalment(label: 'Instalment 1', amount: 10000, dueDate: DateTime(2026, 1, 10)),
        FeeInstalment(label: 'Instalment 2', amount: 10000, dueDate: DateTime(2026, 2, 10)),
        FeeInstalment(label: 'Instalment 3', amount: 10000, dueDate: DateTime(2099, 3, 10)),
      ],
      paidAmount: paid,
      note: '',
      updatedAt: DateTime(2026, 1, 1),
    );

FeePayment payment(double amount) => FeePayment(
      id: 'p1',
      amount: amount,
      mode: PaymentMode.upi,
      reference: '',
      note: '',
      paidOn: DateTime(2026, 3, 1),
      receiptNo: 42,
      receivedBy: 'admin',
    );

final withUpi = InstitutionSettings.defaults.copyWith(name: 'Apex Classes', upiId: 'apex@okhdfcbank');
final withoutUpi = InstitutionSettings.defaults.copyWith(name: 'Apex Classes');

void main() {
  group('UpiPayment', () {
    test('validates UPI IDs', () {
      for (final ok in ['apex@okhdfcbank', 'apex.classes-1@ybl', '9876543210@paytm', ' a_b@upi ']) {
        expect(UpiPayment.isValidUpiId(ok), isTrue, reason: ok);
      }
      for (final bad in [null, '', 'apex', '@ybl', 'a@', 'a@1bank', 'a b@ybl', 'a@ok hdfc', 'javascript:x@ybl']) {
        expect(UpiPayment.isValidUpiId(bad), isFalse, reason: '$bad');
      }
    });

    test('intent link has payee, two-decimal amount, INR and note with %20 spaces', () {
      const p = UpiPayment(upiId: 'apex@ybl', payeeName: 'Apex Classes', amount: 1500, note: 'Fees Riya 12');
      expect(p.intentUri.toString(), 'upi://pay?pa=apex@ybl&pn=Apex%20Classes&am=1500.00&cu=INR&tn=Fees%20Riya%2012');
    });

    test('no amount lets the payer type one', () {
      const p = UpiPayment(upiId: 'apex@ybl', payeeName: 'Apex', amount: null);
      expect(p.intentUri.queryParameters.containsKey('am'), isFalse);
      expect(p.intentUri.queryParameters['cu'], 'INR');
    });

    test('pay page link carries the same fields over https', () {
      const p = UpiPayment(upiId: 'apex@ybl', payeeName: 'Apex & Co', amount: 99.5, note: 'Fees A');
      final uri = p.payPageUri('$base/');
      expect(uri.scheme, 'https');
      expect(uri.path, '/pay.html');
      expect(uri.queryParameters, {'pa': 'apex@ybl', 'pn': 'Apex & Co', 'am': '99.50', 'cu': 'INR', 'tn': 'Fees A'});
    });

    test('fee note includes the roll number and stays within 50 characters', () {
      expect(UpiPayment.feeNote('Riya  Sharma', '12'), 'Fees Riya Sharma 12');
      expect(UpiPayment.feeNote('Riya', null), 'Fees Riya');
      expect(UpiPayment.feeNote('A' * 80, '123').length, UpiPayment.maxNoteLength);
    });
  });

  group('settings', () {
    test('UPI fields round-trip and payee falls back to the institute name', () {
      final s = InstitutionSettings.fromMap(withUpi.toMap());
      expect(s.upiId, 'apex@okhdfcbank');
      expect(s.upiEnabled, isTrue);
      expect(s.upiPayee, 'Apex Classes');
      expect(s.copyWith(upiPayeeName: 'Apex Edu Pvt Ltd').upiPayee, 'Apex Edu Pvt Ltd');
      expect(InstitutionSettings.fromMap(const {}).upiEnabled, isFalse);
    });
  });

  group('FeeAccount.payableNow', () {
    final now = DateTime(2026, 3, 1);
    test('asks for everything overdue', () => expect(account(paid: 5000).payableNow(now), 15000));
    test('asks for the next instalment when nothing is overdue', () {
      expect(account(paid: 20000).payableNow(now), 10000);
      expect(account(paid: 25000).payableNow(now), 5000);
    });
    test('is zero when fully paid', () => expect(account(paid: 30000).payableNow(now), 0));
  });

  group('fee messages', () {
    final due = account(paid: 5000).nextDue(DateTime(2026, 3, 1))!;

    test('reminder carries a pay link when UPI is set up', () {
      final p = feeReminderParams(withUpi, studentName: 'Riya', roll: '12', due: due, payPageBase: base);
      expect(p.length, ParentAlertKind.feeReminder.paramCount);
      expect(p[0], '₹5,000');
      final link = Uri.parse(p[4]);
      expect(link.toString(), startsWith('$base/pay.html?'));
      expect(link.queryParameters['am'], '5000.00');
      expect(link.queryParameters['tn'], 'Fees Riya 12');
    });

    test('bulk reminder asks for the whole overdue amount', () {
      final p = feeReminderParams(withUpi, studentName: 'Riya', due: due, amount: 15000, payPageBase: base);
      expect(p[0], '₹15,000');
      expect(Uri.parse(p[4]).queryParameters['am'], '15000.00');
    });

    test('reminder says "at the office" without UPI', () {
      final p = feeReminderParams(withoutUpi, studentName: 'Riya', due: due);
      expect(p[4], 'at the office');
      expect(ParentAlertKind.feeReminder.render(p), contains('Pay: at the office'));
    });

    test('receipt shows the balance with a pay link, or nil', () {
      final partly = feeReceiptParams(withUpi,
          studentName: 'Riya', payment: payment(5000), account: account(paid: 5000), payPageBase: base);
      expect(partly.length, ParentAlertKind.feeReceipt.paramCount);
      expect(partly[2], '42');
      expect(partly[4], startsWith('₹25,000, pay online: $base/pay.html?'));

      final paid = feeReceiptParams(withUpi, studentName: 'Riya', payment: payment(30000), account: account(paid: 30000));
      expect(paid[4], 'nil');

      final noUpi = feeReceiptParams(withoutUpi, studentName: 'Riya', payment: payment(5000), account: account(paid: 5000));
      expect(noUpi[4], '₹25,000');
    });

    test('values never contain newlines (WhatsApp rejects them in variables)', () {
      final all = [
        ...feeReminderParams(withUpi, studentName: 'Riya', due: due),
        ...feeReceiptParams(withUpi, studentName: 'Riya', payment: payment(1), account: account(paid: 1)),
      ];
      for (final v in all) {
        expect(v.contains('\n'), isFalse, reason: v);
      }
    });
  });
}
