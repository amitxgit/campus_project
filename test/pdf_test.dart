import 'dart:io';
import 'dart:typed_data';

import 'package:campus_track/core/models/fee.dart';
import 'package:campus_track/features/reports/receipt_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Set PDF_OUT to a folder to keep the generated files for a visual check.
void keep(String name, Uint8List bytes) {
  final dir = Platform.environment['PDF_OUT'];
  if (dir != null) File('$dir/$name').writeAsBytesSync(bytes);
}

bool isPdf(Uint8List b) => String.fromCharCodes(b.take(5)) == '%PDF-';

final account = FeeAccount(
  studentId: 's1',
  studentName: 'Riya Sharma',
  section: 'JEE-A',
  totalFee: 60000,
  discount: 5000,
  instalments: [FeeInstalment(label: 'Full fee', amount: 55000, dueDate: DateTime(2026, 12, 1))],
  paidAmount: 25000,
  note: '',
  updatedAt: DateTime(2026, 11, 1),
);

FeePayment payment({bool voided = false}) => FeePayment(
      id: 'p1',
      amount: 12500,
      mode: PaymentMode.upi,
      reference: 'UPI 412233445566',
      note: '',
      paidOn: DateTime(2026, 11, 2),
      receiptNo: 1042,
      receivedBy: 'Office',
      voided: voided,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt PDF builds with the rupee font', () async {
    final bytes = await buildReceiptPdf(
      institute: 'Apex Classes',
      studentName: 'Riya Sharma',
      roll: '12',
      payment: payment(),
      account: account,
      currency: '₹',
    );
    expect(isPdf(bytes), isTrue);
    keep('receipt.pdf', bytes);
  });

  test('void receipt still builds', () async {
    final bytes = await buildReceiptPdf(
      institute: 'Apex Classes',
      studentName: 'Riya Sharma',
      payment: payment(voided: true),
      account: account,
      currency: '₹',
    );
    expect(isPdf(bytes), isTrue);
    keep('receipt-void.pdf', bytes);
  });

  test('receipt file name is safe', () {
    expect(receiptFileName('Riya  Sharma (JEE)', 7), 'receipt-7-riya-sharma-jee.pdf');
  });
}
