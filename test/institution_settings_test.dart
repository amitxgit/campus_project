import 'package:campus_track/core/models/institution_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attendanceMarksFor', () {
    // College defaults: 75% threshold, 6 attendance marks. These are the bands
    // the app used before settings existed, so existing grades don't change.
    final college = InstitutionSettings.preset(InstitutionType.college);

    test('matches the original 75% / 6-mark bands', () {
      const expected = {
        0: 0, 75: 0, 76: 1, 80: 1, 81: 2, 85: 2, 86: 3, 90: 3,
        91: 4, 95: 4, 96: 5, 99: 5, 100: 6,
      };
      expected.forEach((pct, marks) {
        expect(college.attendanceMarksFor(pct), marks, reason: '$pct%');
      });
    });

    test('scales with a custom scheme', () {
      final s = college.copyWith(attendanceThreshold: 60, attendanceMax: 5);
      expect(s.attendanceMarksFor(60), 0);
      expect(s.attendanceMarksFor(61), 1);
      expect(s.attendanceMarksFor(99), 4);
      expect(s.attendanceMarksFor(100), 5);
    });

    test('zero attendance marks never awards anything', () {
      expect(college.copyWith(attendanceMax: 0).attendanceMarksFor(100), 0);
    });
  });

  group('fromMap', () {
    test('missing fields fall back to the preset for the stored type', () {
      final s = InstitutionSettings.fromMap({'type': 'college', 'name': 'ABC College'});
      expect(s.name, 'ABC College');
      expect(s.groupLabel, 'Section');
      expect(s.internalMarksEnabled, isTrue);
      expect(s.periodStarts, isNotEmpty);
    });

    test('round-trips through toMap', () {
      final original = InstitutionSettings.preset(InstitutionType.coaching, name: 'Apex Classes')
          .copyWith(groups: ['JEE-A', 'NEET-B'], attendanceThreshold: 85);
      final copy = InstitutionSettings.fromMap(original.toMap());
      expect(copy.toMap(), original.toMap());
    });

    test('unknown type defaults to coaching', () {
      expect(InstitutionSettings.fromMap({'type': 'bogus'}).type, InstitutionType.coaching);
    });
  });

  test('labels and period end times', () {
    final s = InstitutionSettings.preset(InstitutionType.coaching);
    expect(s.groupLabelPlural, 'Batches');
    expect(s.copyWith(groupLabel: 'Class').groupLabelPlural, 'Classes');
    expect(s.copyWith(groupLabel: 'Section').groupLabelPlural, 'Sections');
    expect(s.endTimeFor('07:00'), '08:30');
    expect(s.copyWith(periodMinutes: 45).endTimeFor('23:30'), '00:15');
  });
}
