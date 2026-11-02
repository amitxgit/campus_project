import 'package:campus_track/core/models/fee.dart';
import 'package:campus_track/core/models/institution_settings.dart';
import 'package:campus_track/core/models/parent_alert.dart';
import 'package:campus_track/features/fees/fee_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final due = InstalmentStatus(
    FeeInstalment(label: 'Instalment 2', amount: 10000, dueDate: DateTime(2026, 2, 10)),
    0,
    InstalmentState.overdue,
  );
  const link = 'https://rzp.io/rzp/AbC123';

  group('settings', () {
    test('Razorpay key id round-trips and marks Razorpay as connected', () {
      final s = InstitutionSettings.fromMap(
          InstitutionSettings.defaults.copyWith(razorpayKeyId: 'rzp_live_123').toMap());
      expect(s.razorpayKeyId, 'rzp_live_123');
      expect(s.razorpayConnected, isTrue);
      expect(InstitutionSettings.fromMap(const {}).razorpayConnected, isFalse);
      expect(s.copyWith(razorpayKeyId: '').razorpayConnected, isFalse);
    });

    test('other edits keep the Razorpay connection', () {
      final s = InstitutionSettings.defaults.copyWith(razorpayKeyId: 'rzp_live_123');
      expect(s.copyWith(name: 'Apex', upiId: 'apex@ybl').razorpayKeyId, 'rzp_live_123');
    });
  });

  group('payment link message', () {
    final withUpi = InstitutionSettings.defaults.copyWith(name: 'Apex Classes', upiId: 'apex@ybl');

    test('the Razorpay link replaces the UPI pay page in the reminder', () {
      final p = feeReminderParams(withUpi, studentName: 'Riya', due: due, amount: 7500, payLink: link);
      expect(p.length, ParentAlertKind.feeReminder.paramCount);
      expect(p[0], '₹7,500');
      expect(p[4], link);
      expect(ParentAlertKind.feeReminder.render(p), contains(link));
    });

    test('works without UPI set up', () {
      final p = feeReminderParams(InstitutionSettings.defaults, studentName: 'Riya', due: due, payLink: link);
      expect(p[4], link);
    });
  });

  group('payments recorded by the webhook', () {
    test('read back with their mode, reference and Razorpay as receiver', () {
      final p = FeePayment.fromMap('pay_X1', {
        'amount': 7500,
        'mode': 'bankTransfer',
        'reference': 'pay_X1',
        'note': 'Paid online (Razorpay link)',
        'paidOn': DateTime(2026, 11, 2),
        'receiptNo': 7,
        'receivedBy': 'Razorpay',
        'voided': false,
        'paymentLinkId': 'plink_1',
      });
      expect(p.mode, PaymentMode.bankTransfer);
      expect(p.reference, 'pay_X1');
      expect(p.receivedBy, 'Razorpay');
      expect(p.receiptNo, 7);
    });

    test('wallet and pay-later payments show as Online', () {
      final p = FeePayment.fromMap('pay_X2', {'mode': 'online', 'paidOn': DateTime(2026, 11, 2)});
      expect(p.mode, PaymentMode.online);
      expect(p.mode.label, 'Online');
    });
  });
}
