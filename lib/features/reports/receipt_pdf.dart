// lib/features/reports/receipt_pdf.dart
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/fee.dart';
import '../../core/utils/money.dart';
import '../../core/utils/share_file.dart';
import 'pdf_kit.dart';

/// A one-page A5 fee receipt.
Future<Uint8List> buildReceiptPdf({
  required String institute,
  required String studentName,
  String? roll,
  required FeePayment payment,
  required FeeAccount account,
  required String currency,
}) async {
  final theme = await pdfTheme();
  String money(double v) => formatMoney(v, currency);
  final balance = account.balance < 0 ? 0.0 : account.balance;
  final doc = pw.Document(title: 'Receipt ${payment.receiptNo}', author: institute, theme: theme);

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Stack(children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pdfHeader(institute, 'Fee receipt', right: 'No. ${payment.receiptNo}'),
        pw.SizedBox(height: 18),
        pw.Text('Amount received', style: const pw.TextStyle(color: pdfMuted, fontSize: 10)),
        pw.Text(money(payment.amount), style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pdfRow('Student', studentName, bold: true),
        if (account.section.isNotEmpty) pdfRow('Batch', account.section),
        if (roll != null && roll.isNotEmpty) pdfRow('Roll no.', roll),
        pdfRow('Date', DateFormat('d MMM yyyy').format(payment.paidOn)),
        pdfRow('Paid by', payment.mode.label),
        if (payment.reference.isNotEmpty) pdfRow('Reference', payment.reference),
        if (payment.note.isNotEmpty) pdfRow('Note', payment.note),
        pw.SizedBox(height: 8),
        pw.Container(height: 0.5, color: pdfLine),
        pw.SizedBox(height: 8),
        pdfRow('Total fee', money(account.netFee)),
        pdfRow('Paid so far', money(account.paidAmount)),
        pdfRow('Balance due now', balance <= 0.5 ? 'Nil' : money(balance), bold: true),
        pw.Spacer(),
        pdfFootnote('This is a computer-generated receipt and does not need a signature.'),
        if (payment.receivedBy.isNotEmpty) pdfFootnote('Recorded by ${payment.receivedBy}.'),
      ]),
      if (payment.voided)
        pw.Center(
          child: pw.Transform.rotateBox(
            angle: 0.5,
            child: pw.Text('VOID',
                style: pw.TextStyle(fontSize: 90, fontWeight: pw.FontWeight.bold, color: PdfColors.red200)),
          ),
        ),
    ]),
  ));
  return doc.save();
}

String receiptFileName(String studentName, int receiptNo) => 'receipt-$receiptNo-${fileSlug(studentName)}.pdf';
