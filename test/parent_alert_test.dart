import 'package:campus_track/core/models/parent_alert.dart';
import 'package:campus_track/core/utils/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNumber.normalize', () {
    test('accepts common Indian formats', () {
      for (final input in ['9876543210', '98765 43210', '+91 98765-43210', '09876543210', '0091 9876543210', '919876543210']) {
        expect(PhoneNumber.normalize(input), '919876543210', reason: input);
      }
    });

    test('keeps other country codes', () {
      expect(PhoneNumber.normalize('+1 415 555 0100'), '14155550100');
    });

    test('rejects junk', () {
      for (final input in [null, '', '12345', 'call me', '+91 98765']) {
        expect(PhoneNumber.normalize(input), isNull, reason: '$input');
      }
    });
  });

  group('templates', () {
    test('render fills every placeholder', () {
      for (final kind in ParentAlertKind.values) {
        final count = RegExp(r'\{\{\d\}\}').allMatches(kind.templateBody).length;
        final text = kind.render(List.generate(count, (i) => 'v$i'));
        expect(text.contains('{{'), isFalse, reason: kind.name);
      }
    });

    test('no template starts or ends with a variable (Meta rejects these)', () {
      for (final kind in ParentAlertKind.values) {
        final body = kind.templateBody.trim();
        expect(body.startsWith('{{'), isFalse, reason: kind.name);
        expect(RegExp(r'\{\{\d\}\}[.!]?$').hasMatch(body), isFalse, reason: kind.name);
      }
    });

    test('absence message reads naturally', () {
      expect(
        ParentAlertKind.absence.render(['Asha', '3 Nov 2026', 'Apex Classes']),
        'Dear Parent, Asha was absent from class on 3 Nov 2026. Please contact Apex Classes if you have any questions.',
      );
    });
  });
}
