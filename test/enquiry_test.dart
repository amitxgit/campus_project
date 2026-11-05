import 'package:campus_track/core/models/enquiry.dart';
import 'package:campus_track/core/models/role.dart';
import 'package:flutter_test/flutter_test.dart';

Enquiry enquiry({
  EnquiryStatus status = EnquiryStatus.newEnquiry,
  DateTime? followUp,
  DateTime? createdAt,
  String parentName = 'Sunita Sharma',
  String parentPhone = '98111 22233',
  String course = 'Class 11 JEE',
}) =>
    Enquiry(
      id: 'e1',
      name: 'Riya Sharma',
      phone: '9000011111',
      parentName: parentName,
      parentPhone: parentPhone,
      course: course,
      batch: 'JEE-A',
      source: EnquirySource.instagram,
      status: status,
      nextFollowUp: followUp,
      notes: 'Wants evening batch',
      createdBy: 'teacher1',
      createdAt: createdAt ?? DateTime(2026, 11, 1, 10),
      updatedAt: DateTime(2026, 11, 1, 10),
    );

void main() {
  final now = DateTime(2026, 11, 2, 18, 30);

  group('storage', () {
    test('round-trips every field; status "new" is stored as new', () {
      final e = enquiry(followUp: DateTime(2026, 11, 3)).copyWith(studentId: 'stu9');
      final map = e.toMap();
      expect(map['status'], 'new');
      expect(map['source'], 'instagram');
      final back = Enquiry.fromMap('e1', map);
      expect(back.name, 'Riya Sharma');
      expect(back.parentPhone, '98111 22233');
      expect(back.course, 'Class 11 JEE');
      expect(back.batch, 'JEE-A');
      expect(back.source, EnquirySource.instagram);
      expect(back.status, EnquiryStatus.newEnquiry);
      expect(back.nextFollowUp, DateTime(2026, 11, 3));
      expect(back.notes, 'Wants evening batch');
      expect(back.createdBy, 'teacher1');
      expect(back.studentId, 'stu9');
    });

    test('every status and source survives a round trip', () {
      for (final s in EnquiryStatus.values) {
        expect(EnquiryStatusX.parse(s.key), s);
      }
      for (final s in EnquirySource.values) {
        expect(EnquirySourceX.parse(s.name), s);
      }
    });

    test('unknown or missing values fall back safely', () {
      final e = Enquiry.fromMap('x', const {'name': 'A', 'status': 'weird', 'source': 'tv'});
      expect(e.status, EnquiryStatus.newEnquiry);
      expect(e.source, EnquirySource.other);
      expect(e.nextFollowUp, isNull);
      expect(e.studentId, isNull);
    });
  });

  group('follow-ups', () {
    test('due today and overdue count; future and closed ones do not', () {
      expect(enquiry(followUp: DateTime(2026, 11, 2, 9)).isDue(now), isTrue);
      expect(enquiry(followUp: DateTime(2026, 11, 2)).isOverdue(now), isFalse);
      expect(enquiry(followUp: DateTime(2026, 10, 30)).isDue(now), isTrue);
      expect(enquiry(followUp: DateTime(2026, 10, 30)).isOverdue(now), isTrue);
      expect(enquiry(followUp: DateTime(2026, 11, 3)).isDue(now), isFalse);
      expect(enquiry().isDue(now), isFalse);
      expect(enquiry(status: EnquiryStatus.joined, followUp: DateTime(2026, 10, 30)).isDue(now), isFalse);
      expect(enquiry(status: EnquiryStatus.lost, followUp: DateTime(2026, 10, 30)).isDue(now), isFalse);
      expect(enquiry(status: EnquiryStatus.demoBooked, followUp: DateTime(2026, 11, 1)).isDue(now), isTrue);
    });

    test('copyWith can clear the follow-up date', () {
      final e = enquiry(followUp: DateTime(2026, 11, 3));
      expect(e.copyWith(notes: 'x').nextFollowUp, DateTime(2026, 11, 3));
      expect(e.copyWith(clearFollowUp: true).nextFollowUp, isNull);
    });

    test('WhatsApp goes to the parent, or the student without a parent number', () {
      expect(enquiry().contactPhone, '98111 22233');
      expect(enquiry(parentPhone: ' ').contactPhone, '9000011111');
    });

    test('follow-up message greets the parent and names the course', () {
      final m = enquiry().followUpMessage('Apex Classes');
      expect(m, startsWith('Hello Sunita, this is Apex Classes.'));
      expect(m, contains('about Class 11 JEE for Riya Sharma'));
      expect(m.contains('\n'), isFalse);
      final plain = enquiry(parentName: '', course: '').followUpMessage('Apex');
      expect(plain, startsWith('Hello Riya, this is Apex.'));
      expect(plain, contains('your enquiry for Riya Sharma'));
    });
  });

  test('student draft is pre-filled from the enquiry', () {
    final u = enquiry().toStudentDraft('new-id');
    expect(u.id, 'new-id');
    expect(u.role, UserRole.student);
    expect(u.name, 'Riya Sharma');
    expect(u.phone, '9000011111');
    expect(u.parentName, 'Sunita Sharma');
    expect(u.parentPhone, '98111 22233');
    expect(u.section, 'JEE-A');
    expect(u.isActive, isTrue);
  });

  group('conversion this month', () {
    test('counts only this month and works out the joined share', () {
      final list = [
        enquiry(createdAt: DateTime(2026, 11, 1), status: EnquiryStatus.joined),
        enquiry(createdAt: DateTime(2026, 11, 2), status: EnquiryStatus.lost),
        enquiry(createdAt: DateTime(2026, 11, 2), status: EnquiryStatus.contacted),
        enquiry(createdAt: DateTime(2026, 10, 31, 23, 59), status: EnquiryStatus.joined),
        enquiry(createdAt: DateTime(2026, 12, 1), status: EnquiryStatus.joined),
      ];
      final c = EnquiryConversion.forMonth(list, now);
      expect(c.total, 3);
      expect(c.joined, 1);
      expect(c.percent, 33);
    });

    test('is 0% with no enquiries', () {
      expect(EnquiryConversion.forMonth(const [], now).percent, 0);
      expect(EnquiryConversion.monthStart(now), DateTime(2026, 11));
    });
  });
}
