import 'package:campus_track/core/models/attendance.dart';
import 'package:campus_track/core/models/fee.dart';
import 'package:campus_track/core/models/role.dart';
import 'package:campus_track/core/models/test_result.dart';
import 'package:campus_track/core/models/user.dart';
import 'package:campus_track/features/reports/exports.dart';
import 'package:flutter_test/flutter_test.dart';

UserAccount student(String id, String name, {String? roll, String? parentPhone}) => UserAccount(
      id: id,
      role: UserRole.student,
      name: name,
      phone: '',
      section: 'JEE-A',
      collegeRollNo: roll,
      parentPhone: parentPhone,
      createdAt: DateTime(2026),
    );

FeeAccount account(String id, String name, {required double paid, double total = 30000}) => FeeAccount(
      studentId: id,
      studentName: name,
      section: 'JEE-A',
      totalFee: total,
      discount: 0,
      instalments: [
        FeeInstalment(label: 'I1', amount: total / 2, dueDate: DateTime(2026, 10, 1)),
        FeeInstalment(label: 'I2', amount: total / 2, dueDate: DateTime(2026, 12, 1)),
      ],
      paidAmount: paid,
      note: '',
      updatedAt: DateTime(2026),
    );

FeePayment pay(int no, double amount, {bool voided = false}) => FeePayment(
      id: 'p$no',
      amount: amount,
      mode: PaymentMode.cash,
      reference: '',
      note: '',
      paidOn: DateTime(2026, 11, no),
      receiptNo: no,
      receivedBy: 'Office',
      voided: voided,
    );

AttendanceRecord rec(String sid, AttendanceStatus s) => AttendanceRecord(
      id: '$sid$s',
      sessionId: 'x',
      studentId: sid,
      subjectId: 'phy',
      date: DateTime(2026, 11, 1),
      slot: '',
      status: s,
      markedByTeacherId: 't',
      markedAt: DateTime(2026, 11, 1),
    );

void main() {
  final now = DateTime(2026, 11, 2);

  test('fee ledger lists payments with names and totals only valid ones', () {
    final rows = feeLedgerRows(
      [(studentId: 's1', payment: pay(1, 5000)), (studentId: 's2', payment: pay(2, 700, voided: true))],
      accounts: {'s1': account('s1', 'Riya', paid: 5000), 's2': account('s2', 'Old name', paid: 0)},
      students: {'s2': student('s2', 'Kabir', roll: '7')},
    );
    expect(rows.first.first, 'Date');
    expect(rows[1], ['01-11-2026', 1, 'Riya', 'JEE-A', '', 5000.0, 'Cash', '', '', 'Office', 'Paid']);
    expect(rows[2][2], 'Kabir');
    expect(rows[2][4], '7');
    expect(rows[2].last, 'Void');
    expect(rows.last, ['Total (excluding void)', null, null, null, null, 5000.0]);
  });

  test('dues list leaves out the fully paid and puts the most overdue first', () {
    final rows = duesRows(
      [
        account('a', 'Paid up', paid: 30000),
        account('b', 'Some overdue', paid: 10000),
        account('c', 'All overdue', paid: 0),
        account('d', 'On time', paid: 15000),
      ],
      students: {'c': student('c', 'All overdue', parentPhone: '9811122233')},
      now: now,
    );
    expect(rows.map((r) => r.first).skip(1), ['All overdue', 'Some overdue', 'On time']);
    final c = rows[1];
    expect(c[2], '9811122233');
    expect(c.sublist(3, 7), [30000.0, 0.0, 30000.0, 15000.0]);
    expect(c[7], '01-10-2026');
    expect(rows[3][6], 0.0); // on time: nothing overdue
    expect(rows[3][7], '01-12-2026');
  });

  test('attendance summarises each student, including those with no classes', () {
    final rows = attendanceRows(
      [student('s2', 'Zoya'), student('s1', 'Aman', roll: '3')],
      [
        rec('s1', AttendanceStatus.present),
        rec('s1', AttendanceStatus.late),
        rec('s1', AttendanceStatus.absent),
        rec('s1', AttendanceStatus.excused),
        rec('other', AttendanceStatus.present),
      ],
    );
    expect(rows[1], ['Aman', '3', 1, 1, 1, 1, 4, 75]);
    expect(rows[2], ['Zoya', '', 0, 0, 0, 0, 0, null]);
  });

  test('test results ranked with ties, then absent and not entered', () {
    final test = TestPaper(
      id: 't', name: 'WT1', section: 'JEE-A', subjectName: 'Physics',
      date: DateTime(2026, 11, 1), maxMarks: 80, createdBy: 'x',
    );
    final rows = testResultRows(
      test,
      {'a': 60, 'b': 72, 'c': 60, 'd': null},
      [student('a', 'Asha'), student('b', 'Bilal'), student('c', 'Chetan'), student('d', 'Dev'), student('e', 'Esha')],
    );
    expect(rows[0], ['Test', 'WT1', 'Subject', 'Physics', 'Date', '01-11-2026']);
    final body = rows.sublist(2, 7);
    expect(body.map((r) => r[0]), ['Bilal', 'Asha', 'Chetan', 'Dev', 'Esha']);
    expect(body.map((r) => r[5]), [1, 2, 2, null, null]);
    expect(body[0].sublist(2, 5), ['72', '80', 90]);
    expect(body[3].last, 'Absent');
    expect(body[4].last, 'Not entered');
    expect(rows.last, ['Appeared', 3, 'Average', '64', 'Highest', '72']);
  });
}
