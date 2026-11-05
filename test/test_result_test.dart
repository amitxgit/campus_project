import 'package:campus_track/core/models/test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('competition ranking: ties share a rank and the next rank skips', () {
    final s = rankScores({'a': 90, 'b': 75, 'c': 90, 'd': 60, 'e': 75});
    expect(s.ranks, {'a': 1, 'c': 1, 'b': 3, 'e': 3, 'd': 5});
  });

  test('absent students get no rank and are left out of stats', () {
    final s = rankScores({'a': 40, 'b': null, 'c': 80});
    expect(s.ranks.containsKey('b'), isFalse);
    expect(s.appeared, 2);
    expect(s.average, 60);
    expect(s.highest, 80);
  });

  test('empty or all-absent tests have zero stats', () {
    expect(rankScores({}).appeared, 0);
    final s = rankScores({'a': null});
    expect(s.average, 0);
    expect(s.highest, 0);
  });

  test('student result percent and round trip', () {
    final r = StudentResult(
      testId: 't', testName: 'WT1', subjectName: 'Physics', date: DateTime(2026, 5, 1),
      maxMarks: 120, marks: 90, rank: 2, outOf: 30, average: 70.5, highest: 110,
    );
    expect(r.percent, 75);
    expect(StudentResult.fromMap('t', r.toMap()).toMap(), r.toMap());
  });
}
