import 'package:campus_track/core/models/institution_settings.dart';
import 'package:campus_track/core/models/notification.dart';
import 'package:campus_track/core/models/parent_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily_summary template has the 6 values the server sends', () {
    expect(RegExp(r'\{\{\d+\}\}').allMatches(kDailySummaryTemplateBody).length, 6);
    for (var i = 1; i <= 6; i++) {
      expect(kDailySummaryTemplateBody, contains('{{$i}}'));
    }
  });

  test('template list for Meta has every template once', () {
    final names = allWhatsAppTemplates.map((t) => t.$1).toList();
    expect(names.toSet().length, names.length);
    expect(names, containsAll(['absence_alert', 'fee_reminder', 'fee_receipt', 'test_result', 'daily_summary']));
  });

  test('owner phone round-trips and survives other edits', () {
    final s = InstitutionSettings.fromMap(InstitutionSettings.defaults.copyWith(ownerPhone: '98765 43210').toMap());
    expect(s.ownerPhone, '98765 43210');
    expect(s.copyWith(name: 'Apex').ownerPhone, '98765 43210');
    expect(InstitutionSettings.fromMap(const {}).ownerPhone, '');
  });

  test('summary notifications are recognised', () {
    final n = AppNotification.fromMap('n', {'userId': 'a', 'type': 'dailySummary', 'createdAt': DateTime(2026)});
    expect(n.type, NotificationType.dailySummary);
  });
}
