// lib/features/reports/exports.dart
//
// Turns app data into spreadsheet rows (see csvBytes). Pure functions so the
// columns and maths are unit-tested. Amounts are plain numbers, not "₹1,200",
// so Excel can add them up.

import 'package:intl/intl.dart';

import '../../core/models/attendance.dart';
import '../../core/models/fee.dart';
import '../../core/models/test_result.dart';
import '../../core/models/user.dart';

typedef Rows = List<List<Object?>>;

final _date = DateFormat('dd-MM-yyyy');

/// Every payment in the period, oldest first, then a total of the valid ones.
Rows feeLedgerRows(
  List<({String studentId, FeePayment payment})> payments, {
  required Map<String, FeeAccount> accounts,
  Map<String, UserAccount> students = const {},
}) {
  final rows = <List<Object?>>[
    ['Date', 'Receipt no.', 'Student', 'Batch', 'Roll no.', 'Amount', 'Mode', 'Reference', 'Note', 'Recorded by', 'Status'],
  ];
  var total = 0.0;
  for (final (:studentId, :payment) in payments) {
    final a = accounts[studentId];
    final u = students[studentId];
    if (!payment.voided) total += payment.amount;
    rows.add([
      _date.format(payment.paidOn),
      payment.receiptNo,
      u?.name ?? a?.studentName ?? studentId,
      a?.section ?? u?.section ?? '',
      u?.collegeRollNo ?? '',
      payment.amount,
      payment.mode.label,
      payment.reference,
      payment.note,
      payment.receivedBy,
      payment.voided ? 'Void' : 'Paid',
    ]);
  }
  rows.add(['Total (excluding void)', null, null, null, null, total]);
  return rows;
}

/// Students who still owe money, most overdue first.
Rows duesRows(List<FeeAccount> accounts, {Map<String, UserAccount> students = const {}, DateTime? now}) {
  final at = now ?? DateTime.now();
  final owing = accounts.where((a) => !a.isFullyPaid).toList()
    ..sort((a, b) {
      final byOverdue = b.overdueAmount(at).compareTo(a.overdueAmount(at));
      return byOverdue != 0 ? byOverdue : a.studentName.compareTo(b.studentName);
    });
  return [
    ['Student', 'Batch', 'Parent phone', 'Net fee', 'Paid', 'Balance', 'Overdue', 'Next due date', 'Next due amount'],
    for (final a in owing)
      [
        students[a.studentId]?.name ?? a.studentName,
        a.section,
        students[a.studentId]?.parentPhone ?? '',
        a.netFee,
        a.paidAmount,
        a.balance,
        a.overdueAmount(at),
        a.nextDue(at) == null ? '' : _date.format(a.nextDue(at)!.instalment.dueDate),
        a.nextDue(at)?.outstanding,
      ],
  ];
}

/// One row per student in the batch: classes in the period by status.
/// Present, late and excused count as attended (same as the app).
Rows attendanceRows(List<UserAccount> students, List<AttendanceRecord> records) {
  final byStudent = <String, List<AttendanceRecord>>{};
  for (final r in records) {
    byStudent.putIfAbsent(r.studentId, () => []).add(r);
  }
  final sorted = [...students]..sort((a, b) => a.name.compareTo(b.name));
  int count(List<AttendanceRecord> rs, AttendanceStatus s) => rs.where((r) => r.status == s).length;
  return [
    ['Student', 'Roll no.', 'Present', 'Late', 'Excused', 'Absent', 'Classes', 'Attendance %'],
    for (final s in sorted)
      () {
        final rs = byStudent[s.id] ?? const <AttendanceRecord>[];
        final attended = rs.length - count(rs, AttendanceStatus.absent);
        return [
          s.name,
          s.collegeRollNo ?? '',
          count(rs, AttendanceStatus.present),
          count(rs, AttendanceStatus.late),
          count(rs, AttendanceStatus.excused),
          count(rs, AttendanceStatus.absent),
          rs.length,
          rs.isEmpty ? null : (attended * 100 / rs.length).round(),
        ];
      }(),
  ];
}

/// One test's marks with ranks (ties share a rank), best first; absent and
/// not-yet-entered students at the end.
Rows testResultRows(TestPaper test, Map<String, double?> marks, List<UserAccount> students) {
  final stats = rankScores(marks);
  String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final sorted = [...students]..sort((a, b) {
      final ra = stats.ranks[a.id] ?? 1 << 30;
      final rb = stats.ranks[b.id] ?? 1 << 30;
      return ra != rb ? ra.compareTo(rb) : a.name.compareTo(b.name);
    });
  return [
    ['Test', test.name, 'Subject', test.subjectName, 'Date', _date.format(test.date)],
    ['Student', 'Roll no.', 'Marks', 'Out of', '%', 'Rank', 'Status'],
    for (final s in sorted)
      () {
        final entered = marks.containsKey(s.id);
        final m = marks[s.id];
        return [
          s.name,
          s.collegeRollNo ?? '',
          m == null ? null : fmt(m),
          fmt(test.maxMarks),
          m == null || test.maxMarks <= 0 ? null : (m * 100 / test.maxMarks).round(),
          stats.ranks[s.id],
          !entered ? 'Not entered' : (m == null ? 'Absent' : ''),
        ];
      }(),
    [],
    ['Appeared', stats.appeared, 'Average', fmt(stats.average), 'Highest', fmt(stats.highest)],
  ];
}
