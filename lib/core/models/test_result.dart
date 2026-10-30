// lib/core/models/test_result.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

/// A test given to one batch. Raw marks live in tests/{id}/marks/all (staff
/// only); on publish each student's result is copied to student_results.
class TestPaper {
  final String id;
  final String name;
  final String section;
  final String subjectName;
  final DateTime date;
  final double maxMarks;
  final String createdBy;
  final bool published;
  final int appeared;
  final double average;
  final double highest;

  const TestPaper({
    required this.id,
    required this.name,
    required this.section,
    required this.subjectName,
    required this.date,
    required this.maxMarks,
    required this.createdBy,
    this.published = false,
    this.appeared = 0,
    this.average = 0,
    this.highest = 0,
  });

  String get title => subjectName.isEmpty ? name : '$name • $subjectName';

  Map<String, dynamic> toMap() => {
        'name': name,
        'section': section,
        'subjectName': subjectName,
        'date': Timestamp.fromDate(date),
        'maxMarks': maxMarks,
        'createdBy': createdBy,
        'published': published,
        'appeared': appeared,
        'average': average,
        'highest': highest,
      };

  factory TestPaper.fromMap(String id, Map<String, dynamic> map) => TestPaper(
        id: id,
        name: map['name'] ?? '',
        section: map['section'] ?? '',
        subjectName: map['subjectName'] ?? '',
        date: DateParser.parse(map['date'], fieldName: 'TestPaper.date'),
        maxMarks: (map['maxMarks'] as num?)?.toDouble() ?? 100,
        createdBy: map['createdBy'] ?? '',
        published: map['published'] == true,
        appeared: (map['appeared'] as num?)?.toInt() ?? 0,
        average: (map['average'] as num?)?.toDouble() ?? 0,
        highest: (map['highest'] as num?)?.toDouble() ?? 0,
      );
}

/// One student's result for one test, as stored in
/// student_results/{studentId}.results.{testId}.
class StudentResult {
  final String testId;
  final String testName;
  final String subjectName;
  final DateTime date;
  final double maxMarks;
  final double? marks; // null = absent
  final int? rank;
  final int outOf;
  final double average;
  final double highest;

  const StudentResult({
    required this.testId,
    required this.testName,
    required this.subjectName,
    required this.date,
    required this.maxMarks,
    required this.marks,
    required this.rank,
    required this.outOf,
    required this.average,
    required this.highest,
  });

  bool get absent => marks == null;
  double get percent => marks == null || maxMarks <= 0 ? 0 : marks! / maxMarks * 100;

  Map<String, dynamic> toMap() => {
        'testName': testName,
        'subjectName': subjectName,
        'date': Timestamp.fromDate(date),
        'maxMarks': maxMarks,
        'marks': marks,
        'rank': rank,
        'outOf': outOf,
        'average': average,
        'highest': highest,
      };

  factory StudentResult.fromMap(String testId, Map<String, dynamic> map) => StudentResult(
        testId: testId,
        testName: map['testName'] ?? '',
        subjectName: map['subjectName'] ?? '',
        date: DateParser.parse(map['date'], fieldName: 'StudentResult.date'),
        maxMarks: (map['maxMarks'] as num?)?.toDouble() ?? 100,
        marks: (map['marks'] as num?)?.toDouble(),
        rank: (map['rank'] as num?)?.toInt(),
        outOf: (map['outOf'] as num?)?.toInt() ?? 0,
        average: (map['average'] as num?)?.toDouble() ?? 0,
        highest: (map['highest'] as num?)?.toDouble() ?? 0,
      );
}

typedef TestStats = ({Map<String, int> ranks, int appeared, double average, double highest});

/// Standard competition ranking ("1, 2, 2, 4"): equal marks share a rank and
/// the next rank skips. Absent students (null) get no rank and don't count
/// towards the average.
TestStats rankScores(Map<String, double?> scores) {
  final present = scores.entries.where((e) => e.value != null).toList()
    ..sort((a, b) => b.value!.compareTo(a.value!));
  final ranks = <String, int>{};
  for (var i = 0; i < present.length; i++) {
    final tiedWithPrevious = i > 0 && present[i].value == present[i - 1].value;
    ranks[present[i].key] = tiedWithPrevious ? ranks[present[i - 1].key]! : i + 1;
  }
  final total = present.fold(0.0, (s, e) => s + e.value!);
  return (
    ranks: ranks,
    appeared: present.length,
    average: present.isEmpty ? 0 : total / present.length,
    highest: present.isEmpty ? 0 : present.first.value!,
  );
}
