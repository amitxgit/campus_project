import 'dart:io';
import 'dart:typed_data';

import 'package:campus_track/core/models/attendance.dart';
import 'package:campus_track/core/models/fee.dart';
import 'package:campus_track/core/models/test_result.dart';
import 'package:campus_track/features/reports/report_card_pdf.dart';
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

AttendanceRecord att(int i, AttendanceStatus s) => AttendanceRecord(
      id: 'a$i',
      sessionId: 's$i',
      studentId: 's1',
      subjectId: 'phy',
      date: DateTime(2026, 10, 1 + i % 28),
      slot: '08:00-09:00',
      status: s,
      markedByTeacherId: 't1',
      markedAt: DateTime(2026, 10, 1),
    );

StudentResult result(int i, {double? marks, int? rank}) => StudentResult(
      testId: 't$i',
      testName: 'Weekly Test ${i + 1}',
      subjectName: ['Physics', 'Chemistry', 'Maths'][i % 3],
      date: DateTime(2026, 7, 1).add(Duration(days: 7 * i)),
      maxMarks: 100,
      marks: marks,
      rank: rank,
      outOf: 24,
      average: 61.5,
      highest: 96,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('report card summaries', () {
    test('attendance counts present, late and excused as attended', () {
      final s = attendanceSummary([
        att(0, AttendanceStatus.present),
        att(1, AttendanceStatus.late),
        att(2, AttendanceStatus.excused),
        att(3, AttendanceStatus.absent),
      ]);
      expect((s.attended, s.total, s.percent), (3, 4, 75));
      expect(attendanceSummary(const []).percent, 0);
    });

    test('results: average of tests taken, best rank, absences skipped', () {
      final s = resultSummary([result(0, marks: 80, rank: 3), result(1, marks: 60, rank: 9), result(2)]);
      expect(s.average, 70);
      expect(s.taken, 2);
      expect(s.bestRank, 3);
      expect(resultSummary(const []).bestRank, isNull);
    });
  });

  test('report card PDF builds and runs onto a second page', () async {
    final bytes = await buildReportCardPdf(ReportCardData(
      institute: 'Apex Classes',
      studentName: 'Riya Sharma',
      batch: 'JEE-A',
      roll: '12',
      results: [
        for (var i = 0; i < 40; i++)
          i == 5 ? result(i) : result(i, marks: 55.0 + (i * 7) % 40, rank: 1 + (i * 5) % 20),
      ],
      attendance: [for (var i = 0; i < 60; i++) att(i, i % 6 == 0 ? AttendanceStatus.absent : AttendanceStatus.present)],
      attendanceThreshold: 75,
      fees: account,
      currency: '₹',
      generatedOn: DateTime(2026, 12, 5),
    ));
    expect(isPdf(bytes), isTrue);
    keep('report-card.pdf', bytes);
  });

  test('report card with no data yet', () async {
    final bytes = await buildReportCardPdf(ReportCardData(
      institute: 'Apex Classes',
      studentName: 'New Student',
      batch: '',
      results: const [],
      attendance: const [],
      attendanceThreshold: 75,
      currency: '₹',
      generatedOn: DateTime(2026, 11, 2),
    ));
    expect(isPdf(bytes), isTrue);
    keep('report-card-empty.pdf', bytes);
  });

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
