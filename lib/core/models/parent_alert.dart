// lib/core/models/parent_alert.dart
import '../utils/date_parser.dart';

/// Each kind maps to one pre-approved WhatsApp message template. The
/// [params] fill the template's {{1}}, {{2}}... placeholders in order, and
/// [preview] renders the same message as plain text for manual sending.
enum ParentAlertKind { absence, feeReminder, feeReceipt, testResult }

extension ParentAlertKindX on ParentAlertKind {
  String get label => switch (this) {
        ParentAlertKind.absence => 'Absence',
        ParentAlertKind.feeReminder => 'Fee reminder',
        ParentAlertKind.feeReceipt => 'Fee receipt',
        ParentAlertKind.testResult => 'Test result',
      };

  /// WhatsApp template name to create in Meta Business Manager.
  String get templateName => switch (this) {
        ParentAlertKind.absence => 'absence_alert',
        ParentAlertKind.feeReminder => 'fee_reminder',
        ParentAlertKind.feeReceipt => 'fee_receipt',
        ParentAlertKind.testResult => 'test_result',
      };

  /// Template body. Must match what is registered with Meta, word for word.
  String get templateBody => switch (this) {
        ParentAlertKind.absence =>
          'Dear Parent, {{1}} was absent from class on {{2}}. Please contact {{3}} if you have any questions.',
        ParentAlertKind.feeReminder =>
          'Dear Parent, a fee payment of {{1}} for {{2}} is due on {{3}}. Please pay at {{4}}. Ignore if already paid.',
        ParentAlertKind.feeReceipt =>
          'Dear Parent, we have received {{1}} towards the fees of {{2}} (Receipt No. {{3}}) at {{4}}. Thank you for your payment.',
        ParentAlertKind.testResult =>
          'Dear Parent, {{1}} scored {{2}} in {{3}} at {{4}}. Please contact us to discuss progress.',
      };

  String render(List<String> params) {
    var text = templateBody;
    for (var i = 0; i < params.length; i++) {
      text = text.replaceAll('{{${i + 1}}}', params[i]);
    }
    return text;
  }
}

enum ParentAlertStatus { pending, sent, failed, noPhone, notConfigured, rejected }

class ParentAlert {
  final String id;
  final String studentId;
  final String studentName;
  final ParentAlertKind kind;
  final List<String> params;
  final ParentAlertStatus status;
  final String? error;
  final DateTime createdAt;

  const ParentAlert({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.kind,
    required this.params,
    required this.status,
    this.error,
    required this.createdAt,
  });

  String get preview => kind.render(params);

  factory ParentAlert.fromMap(String id, Map<String, dynamic> map) => ParentAlert(
        id: id,
        studentId: map['studentId'] ?? '',
        studentName: map['studentName'] ?? '',
        kind: ParentAlertKind.values.firstWhere((k) => k.name == map['kind'], orElse: () => ParentAlertKind.absence),
        params: (map['params'] as List? ?? []).map((e) => e.toString()).toList(),
        status: ParentAlertStatus.values.firstWhere((s) => s.name == map['status'], orElse: () => ParentAlertStatus.pending),
        error: map['error'] as String?,
        createdAt: DateParser.parse(map['createdAt'], fieldName: 'ParentAlert.createdAt'),
      );
}
