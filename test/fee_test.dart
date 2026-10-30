import 'package:campus_track/core/models/fee.dart';
import 'package:flutter_test/flutter_test.dart';

FeeAccount account({double total = 30000, double discount = 0, double paid = 0, required List<FeeInstalment> instalments}) =>
    FeeAccount(
      studentId: 's1',
      studentName: 'Asha',
      section: 'JEE-A',
      totalFee: total,
      discount: discount,
      instalments: instalments,
      paidAmount: paid,
      note: '',
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('FeeInstalment.split', () {
    test('sums exactly to the total, remainder on the last instalment', () {
      final parts = FeeInstalment.split(total: 10000, count: 3, firstDue: DateTime(2026, 4, 10));
      expect(parts.map((p) => p.amount), [3333, 3333, 3334]);
      expect(parts.fold(0.0, (s, p) => s + p.amount), 10000);
    });

    test('spaces due dates by the gap, across year end', () {
      final parts = FeeInstalment.split(total: 900, count: 3, firstDue: DateTime(2026, 11, 5), monthsApart: 2);
      expect(parts.map((p) => p.dueDate), [DateTime(2026, 11, 5), DateTime(2027, 1, 5), DateTime(2027, 3, 5)]);
    });

    test('single instalment is labelled as the full fee', () {
      expect(FeeInstalment.split(total: 500, count: 1, firstDue: DateTime(2026)).single.label, 'Full fee');
    });
  });

  group('FeeAccount statuses', () {
    final plan = FeeInstalment.split(total: 30000, count: 3, firstDue: DateTime(2026, 4, 1));
    final now = DateTime(2026, 5, 15); // first two instalments are past due

    test('payments cover the oldest instalments first', () {
      final a = account(paid: 15000, instalments: plan);
      final s = a.statuses(now);
      expect(s.map((x) => x.state), [InstalmentState.paid, InstalmentState.overdue, InstalmentState.upcoming]);
      expect(s[1].covered, 5000);
      expect(a.overdueAmount(now), 5000);
      expect(a.nextDue(now)!.instalment.label, 'Instalment 2');
    });

    test('a part-paid instalment that is not yet due is "partial"', () {
      final a = account(paid: 22000, instalments: plan);
      expect(a.statuses(now)[2].state, InstalmentState.partial);
      expect(a.overdueAmount(now), 0);
    });

    test('an instalment due today is not overdue', () {
      final a = account(instalments: plan);
      expect(a.statuses(DateTime(2026, 4, 1, 18)).first.state, InstalmentState.upcoming);
    });

    test('discount reduces the balance; fully paid has no next due', () {
      final a = account(total: 30000, discount: 5000, paid: 25000,
          instalments: FeeInstalment.split(total: 25000, count: 2, firstDue: DateTime(2026, 4, 1)));
      expect(a.netFee, 25000);
      expect(a.balance, 0);
      expect(a.isFullyPaid, isTrue);
      expect(a.nextDue(now), isNull);
    });

    test('round-trips through toMap/fromMap', () {
      final a = account(paid: 1000, instalments: plan);
      final b = FeeAccount.fromMap('s1', a.toMap());
      expect(b.toMap(), a.toMap());
    });
  });
}
