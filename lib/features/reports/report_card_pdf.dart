// lib/features/reports/report_card_pdf.dart
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/attendance.dart';
import '../../core/models/fee.dart';
import '../../core/models/test_result.dart';
import '../../core/utils/money.dart';
import '../../core/utils/share_file.dart';
import 'pdf_kit.dart';

/// Present, late and excused count as attended (same as the attendance page).
({int attended, int total, int percent}) attendanceSummary(Iterable<AttendanceRecord> records) {
  final total = records.length;
  final attended = records.where((r) => r.status != AttendanceStatus.absent).length;
  return (attended: attended, total: total, percent: total == 0 ? 0 : (attended * 100 / total).round());
}

/// Average percentage over tests taken, and the best rank.
({double average, int taken, int? bestRank}) resultSummary(List<StudentResult> results) {
  final taken = results.where((r) => !r.absent).toList();
  final ranks = taken.map((r) => r.rank).whereType<int>();
  return (
    average: taken.isEmpty ? 0 : taken.fold(0.0, (s, r) => s + r.percent) / taken.length,
    taken: taken.length,
    bestRank: ranks.isEmpty ? null : ranks.reduce((a, b) => a < b ? a : b),
  );
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class ReportCardData {
  final String institute;
  final String studentName;
  final String batch;
  final String? roll;
  final List<StudentResult> results;
  final List<AttendanceRecord> attendance;
  final int attendanceThreshold;

  /// Included only when the office chooses to show fees.
  final FeeAccount? fees;
  final String currency;
  final DateTime generatedOn;

  const ReportCardData({
    required this.institute,
    required this.studentName,
    required this.batch,
    this.roll,
    required this.results,
    required this.attendance,
    required this.attendanceThreshold,
    this.fees,
    required this.currency,
    required this.generatedOn,
  });
}

/// A4 report card: summary, every published result with rank and class
/// average, attendance and (optionally) fee status. Runs onto more pages if
/// there are many tests.
Future<Uint8List> buildReportCardPdf(ReportCardData d) async {
  final theme = await pdfTheme();
  final results = [...d.results]..sort((a, b) => a.date.compareTo(b.date));
  final rs = resultSummary(results);
  final att = attendanceSummary(d.attendance);
  final doc = pw.Document(title: 'Report card – ${d.studentName}', author: d.institute, theme: theme);

  pw.Widget stat(String value, String label, {PdfColor? color}) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const pw.BoxDecoration(color: pdfSoft, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
            pw.Text(label, style: const pw.TextStyle(color: pdfMuted, fontSize: 9)),
          ]),
        ),
      );

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 20, bottom: 8),
        child: pw.Text(title.toUpperCase(),
            style: pw.TextStyle(color: pdfMuted, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.1)),
      );

  final lowAttendance = att.total > 0 && att.percent < d.attendanceThreshold;
  final fees = d.fees;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
    header: (ctx) => ctx.pageNumber == 1
        ? pdfHeader(d.institute, 'Report card', right: DateFormat('d MMM yyyy').format(d.generatedOn))
        : pw.SizedBox(),
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(child: pdfFootnote('Computer-generated from ${d.institute} records.')),
      pdfFootnote('Page ${ctx.pageNumber} of ${ctx.pagesCount}'),
    ]),
    build: (ctx) => [
      pw.SizedBox(height: 16),
      pw.Text(d.studentName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text(
        [if (d.batch.isNotEmpty) d.batch, if (d.roll != null && d.roll!.isNotEmpty) 'Roll no. ${d.roll}'].join('  ·  '),
        style: const pw.TextStyle(color: pdfMuted, fontSize: 11),
      ),
      pw.SizedBox(height: 16),
      pw.Row(children: [
        stat(rs.taken == 0 ? '—' : '${rs.average.toStringAsFixed(1)}%', 'Average score', color: pdfAccent),
        pw.SizedBox(width: 8),
        stat('${rs.taken}/${results.length}', 'Tests taken'),
        pw.SizedBox(width: 8),
        stat(rs.bestRank == null ? '—' : '#${rs.bestRank}', 'Best rank'),
        pw.SizedBox(width: 8),
        stat(att.total == 0 ? '—' : '${att.percent}%', 'Attendance', color: lowAttendance ? PdfColors.red700 : null),
      ]),
      section('Test results'),
      if (results.isEmpty)
        pw.Text('No results published yet.', style: const pw.TextStyle(color: pdfMuted, fontSize: 10))
      else
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Test', 'Subject', 'Marks', '%', 'Rank', 'Class avg'],
          data: [
            for (final r in results)
              [
                DateFormat('d MMM').format(r.date),
                r.testName,
                r.subjectName,
                r.absent ? 'Absent' : '${_num(r.marks!)}/${_num(r.maxMarks)}',
                r.absent ? '' : r.percent.toStringAsFixed(0),
                r.rank == null ? '' : '${r.rank}/${r.outOf}',
                _num(r.average),
              ],
          ],
          border: null,
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: pdfMuted),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: pdfLine, width: 0.5))),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          cellAlignments: {
            for (final i in [3, 4, 5, 6]) i: pw.Alignment.centerRight,
          },
          headerAlignments: {
            for (final i in [0, 1, 2]) i: pw.Alignment.centerLeft,
            for (final i in [3, 4, 5, 6]) i: pw.Alignment.centerRight,
          },
        ),
      section('Attendance'),
      pw.Text(
        att.total == 0
            ? 'No attendance recorded yet.'
            : 'Attended ${att.attended} of ${att.total} classes (${att.percent}%). '
                '${lowAttendance ? 'Below' : 'Meets'} the ${d.attendanceThreshold}% requirement.',
        style: const pw.TextStyle(fontSize: 10),
      ),
      if (fees != null) ...[
        section('Fees'),
        pdfRow('Total fee', formatMoney(fees.netFee, d.currency)),
        pdfRow('Paid', formatMoney(fees.paidAmount, d.currency)),
        pdfRow(
          'Balance',
          fees.isFullyPaid ? 'Fully paid' : formatMoney(fees.balance, d.currency),
          bold: true,
        ),
        if (fees.overdueAmount(d.generatedOn) > 0.5)
          pdfRow('Overdue', formatMoney(fees.overdueAmount(d.generatedOn), d.currency), bold: true),
      ],
    ],
  ));
  return doc.save();
}

String reportCardFileName(String studentName) => 'report-card-${fileSlug(studentName)}.pdf';
