// lib/features/fees/fee_messages.dart
//
// Builds the values for the fee WhatsApp templates (see ParentAlertKind) and
// the UPI payment for a student. Pure functions so they can be unit-tested.

import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/models/institution_settings.dart';
import '../../core/utils/money.dart';
import '../../core/utils/upi.dart';

/// The UPI payment a student should make now, or null when the institute
/// hasn't set up UPI. [amount] defaults to what is payable now; pass 0 to let
/// the payer type it.
UpiPayment? upiPaymentFor(
  InstitutionSettings s, {
  required String studentName,
  String? roll,
  double? amount,
}) {
  if (!s.upiEnabled) return null;
  return UpiPayment(
    upiId: s.upiId,
    payeeName: s.upiPayee,
    amount: amount != null && amount > 0.5 ? amount : null,
    note: UpiPayment.feeNote(studentName, roll),
  );
}

/// fee_reminder: amount, student, due date, institute, how to pay.
/// [amount] defaults to what's left on [due]; bulk reminders pass the whole
/// overdue amount instead.
List<String> feeReminderParams(
  InstitutionSettings s, {
  required String studentName,
  String? roll,
  required InstalmentStatus due,
  double? amount,
  String payPageBase = kPayPageBase,
}) {
  final ask = amount ?? due.outstanding;
  final upi = upiPaymentFor(s, studentName: studentName, roll: roll, amount: ask);
  return [
    formatMoney(ask, s.currencySymbol),
    studentName,
    DateFormat('d MMM yyyy').format(due.instalment.dueDate),
    s.name,
    upi == null ? 'at the office' : upi.payPageUri(payPageBase).toString(),
  ];
}

/// fee_receipt: amount, student, receipt no., institute, balance (+ pay link).
List<String> feeReceiptParams(
  InstitutionSettings s, {
  required String studentName,
  String? roll,
  required FeePayment payment,
  required FeeAccount account,
  String payPageBase = kPayPageBase,
}) {
  final cur = s.currencySymbol;
  final String balance;
  if (account.isFullyPaid) {
    balance = 'nil';
  } else {
    final upi = upiPaymentFor(s, studentName: studentName, roll: roll, amount: account.payableNow());
    balance = upi == null
        ? formatMoney(account.balance, cur)
        : '${formatMoney(account.balance, cur)}, pay online: ${upi.payPageUri(payPageBase)}';
  }
  return [
    formatMoney(payment.amount, cur),
    studentName,
    '${payment.receiptNo}',
    s.name,
    balance,
  ];
}
