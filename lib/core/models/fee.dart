// lib/core/models/fee.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

class FeeInstalment {
  final String label;
  final double amount;
  final DateTime dueDate;

  const FeeInstalment({required this.label, required this.amount, required this.dueDate});

  Map<String, dynamic> toMap() => {
        'label': label,
        'amount': amount,
        'dueDate': Timestamp.fromDate(dueDate),
      };

  factory FeeInstalment.fromMap(Map<String, dynamic> map) => FeeInstalment(
        label: map['label'] ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        dueDate: DateParser.parse(map['dueDate'], fieldName: 'FeeInstalment.dueDate'),
      );

  /// Splits [total] into [count] instalments, [monthsApart] months apart,
  /// starting on [firstDue]. Rounds to whole rupees; the last instalment takes
  /// the remainder so the sum always equals [total].
  static List<FeeInstalment> split({
    required double total,
    required int count,
    required DateTime firstDue,
    int monthsApart = 1,
  }) {
    if (count <= 0) return const [];
    final each = (total / count).floorToDouble();
    return List.generate(count, (i) {
      final amount = i == count - 1 ? total - each * (count - 1) : each;
      return FeeInstalment(
        label: count == 1 ? 'Full fee' : 'Instalment ${i + 1}',
        amount: amount,
        dueDate: DateTime(firstDue.year, firstDue.month + i * monthsApart, firstDue.day),
      );
    });
  }
}

enum InstalmentState { paid, partial, overdue, upcoming }

class InstalmentStatus {
  final FeeInstalment instalment;
  final double covered;
  final InstalmentState state;

  const InstalmentStatus(this.instalment, this.covered, this.state);

  double get outstanding => instalment.amount - covered;
}

/// One per student, keyed by student uid. `paidAmount` is kept in sync with
/// the payments subcollection (in the same transaction) so list screens don't
/// have to read every payment.
class FeeAccount {
  final String studentId;
  final String studentName;
  final String section;
  final double totalFee;
  final double discount;
  final List<FeeInstalment> instalments;
  final double paidAmount;
  final String note;
  final DateTime updatedAt;

  const FeeAccount({
    required this.studentId,
    required this.studentName,
    required this.section,
    required this.totalFee,
    required this.discount,
    required this.instalments,
    required this.paidAmount,
    required this.note,
    required this.updatedAt,
  });

  double get netFee => totalFee - discount;
  double get balance => netFee - paidAmount;
  bool get isFullyPaid => balance <= 0.5;

  /// Applies payments to instalments oldest-first.
  List<InstalmentStatus> statuses([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    final sorted = [...instalments]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    var remaining = paidAmount;
    return sorted.map((inst) {
      final covered = remaining.clamp(0.0, inst.amount);
      remaining -= covered;
      final InstalmentState state;
      if (covered >= inst.amount - 0.5) {
        state = InstalmentState.paid;
      } else if (_dateOnly(inst.dueDate).isBefore(today)) {
        state = InstalmentState.overdue;
      } else if (covered > 0) {
        state = InstalmentState.partial;
      } else {
        state = InstalmentState.upcoming;
      }
      return InstalmentStatus(inst, covered, state);
    }).toList();
  }

  double overdueAmount([DateTime? now]) => statuses(now)
      .where((s) => s.state == InstalmentState.overdue)
      .fold(0.0, (total, s) => total + s.outstanding);

  /// What to ask for when the student pays now: everything overdue, or the
  /// next instalment if nothing is overdue. Zero once fully paid.
  double payableNow([DateTime? now]) {
    final overdue = overdueAmount(now);
    if (overdue > 0.5) return overdue;
    return nextDue(now)?.outstanding ?? 0;
  }

  /// The first instalment that still has money owing, if any.
  InstalmentStatus? nextDue([DateTime? now]) {
    for (final s in statuses(now)) {
      if (s.state != InstalmentState.paid) return s;
    }
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'section': section,
        'totalFee': totalFee,
        'discount': discount,
        'instalments': instalments.map((i) => i.toMap()).toList(),
        'paidAmount': paidAmount,
        'note': note,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory FeeAccount.fromMap(String id, Map<String, dynamic> map) => FeeAccount(
        studentId: id,
        studentName: map['studentName'] ?? '',
        section: map['section'] ?? '',
        totalFee: (map['totalFee'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        instalments: (map['instalments'] as List? ?? [])
            .map((e) => FeeInstalment.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0,
        note: map['note'] ?? '',
        updatedAt: DateParser.parse(map['updatedAt'], fieldName: 'FeeAccount.updatedAt'),
      );

  FeeAccount copyWith({
    String? studentName,
    String? section,
    double? totalFee,
    double? discount,
    List<FeeInstalment>? instalments,
    String? note,
  }) =>
      FeeAccount(
        studentId: studentId,
        studentName: studentName ?? this.studentName,
        section: section ?? this.section,
        totalFee: totalFee ?? this.totalFee,
        discount: discount ?? this.discount,
        instalments: instalments ?? this.instalments,
        paidAmount: paidAmount,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
      );
}

enum PaymentMode { cash, upi, card, bankTransfer, cheque }

extension PaymentModeX on PaymentMode {
  String get label => switch (this) {
        PaymentMode.cash => 'Cash',
        PaymentMode.upi => 'UPI',
        PaymentMode.card => 'Card',
        PaymentMode.bankTransfer => 'Bank transfer',
        PaymentMode.cheque => 'Cheque',
      };
}

class FeePayment {
  final String id;
  final double amount;
  final PaymentMode mode;
  final String reference;
  final String note;
  final DateTime paidOn;
  final int receiptNo;
  final String receivedBy;
  final bool voided;

  const FeePayment({
    required this.id,
    required this.amount,
    required this.mode,
    required this.reference,
    required this.note,
    required this.paidOn,
    required this.receiptNo,
    required this.receivedBy,
    this.voided = false,
  });

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'mode': mode.name,
        'reference': reference,
        'note': note,
        'paidOn': Timestamp.fromDate(paidOn),
        'receiptNo': receiptNo,
        'receivedBy': receivedBy,
        'voided': voided,
      };

  factory FeePayment.fromMap(String id, Map<String, dynamic> map) => FeePayment(
        id: id,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        mode: PaymentMode.values.firstWhere((m) => m.name == map['mode'], orElse: () => PaymentMode.cash),
        reference: map['reference'] ?? '',
        note: map['note'] ?? '',
        paidOn: DateParser.parse(map['paidOn'], fieldName: 'FeePayment.paidOn'),
        receiptNo: (map['receiptNo'] as num?)?.toInt() ?? 0,
        receivedBy: map['receivedBy'] ?? '',
        voided: map['voided'] == true,
      );
}
