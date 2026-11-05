import 'package:campus_track/core/utils/csv.dart';
import 'package:campus_track/core/utils/login_id.dart';
import 'package:campus_track/features/admin/import_students_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCsv', () {
    test('quoted fields with commas, quotes and newlines; CRLF; BOM', () {
      final rows = parseCsv('﻿name,note\r\n"Verma, Asha","said ""hi""\nthere"\r\nRohan,\r\n');
      expect(rows, [
        ['name', 'note'],
        ['Verma, Asha', 'said "hi"\nthere'],
        ['Rohan', ''],
      ]);
    });

    test('tab-separated text pasted from a spreadsheet', () {
      expect(parseCsv('name\tbatch\nAsha\tJEE-A'), [
        ['name', 'batch'],
        ['Asha', 'JEE-A'],
      ]);
    });

    test('skips blank lines', () {
      expect(parseCsv('a,b\n\n,\n1,2\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });
  });

  group('parseStudentCsv', () {
    test('the copyable template is valid', () {
      final r = parseStudentCsv(templateCsv, ['JEE-2027-A', 'NEET-2027-B']);
      expect(r.error, isNull);
      expect(r.rows.every((row) => row.errors.isEmpty), isTrue, reason: r.rows.map((x) => x.errors).toString());
    });

    test('flags each problem on its row', () {
      final r = parseStudentCsv(
        'Student Name,Mobile No,Batch,Parent Phone,Password\n'
        ',9876543210,JEE-A,,\n'
        'Asha,123,JEE-A,,\n'
        'Ravi,9876543211,MISSING,,\n'
        'Meena,,JEE-A,,\n'
        'Kiran,9876543211,JEE-A,abc,12\n',
        ['JEE-A'],
      );
      expect(r.rows[0].errors, ['name missing']);
      expect(r.rows[1].errors, ['invalid mobile']);
      expect(r.rows[2].errors, ['unknown batch "MISSING"']);
      expect(r.rows[3].errors, ['needs email or mobile to sign in']);
      expect(r.rows[4].errors, ['invalid parent phone', 'password under 6 characters', 'duplicate login in file']);
    });

    test('requires a header row with name and batch', () {
      expect(parseStudentCsv('Asha,9876543210', []).error, isNotNull);
    });
  });

  group('LoginId', () {
    test('mobile numbers map to an internal login and back', () {
      final email = LoginId.toEmail('+91 98765 43210');
      expect(email, '9876543210@${LoginId.phoneDomain}');
      expect(LoginId.isPhoneLogin(email), isTrue);
      expect(LoginId.display(email), '9876543210');
    });

    test('emails pass through, lower-cased', () {
      expect(LoginId.toEmail(' Asha@Example.com '), 'asha@example.com');
      expect(LoginId.isPhoneLogin('asha@example.com'), isFalse);
    });
  });
}
