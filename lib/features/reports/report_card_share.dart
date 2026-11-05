// lib/features/reports/report_card_share.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../core/utils/share_file.dart';
import 'report_card_pdf.dart';

/// Gathers a student's results, attendance and (if [withFees]) fee account,
/// builds the report card and opens the share sheet / download. Works for
/// admins and for students viewing their own (rules allow both).
Future<void> shareReportCard(WidgetRef ref, UserAccount student, {bool withFees = false}) async {
  final settings = ref.read(settingsProvider);
  final results = ref.read(testRepoProvider).resultsFor(student.id);
  final attendance = ref.read(attendanceRepoProvider).forStudent(student.id, limit: null);
  final fees = withFees && settings.feesEnabled ? ref.read(feeRepoProvider).account(student.id) : Future.value(null);

  final bytes = await buildReportCardPdf(ReportCardData(
    institute: settings.name,
    studentName: student.name,
    batch: student.section ?? '',
    roll: student.collegeRollNo,
    results: await results,
    attendance: await attendance,
    attendanceThreshold: settings.attendanceThreshold,
    fees: await fees,
    currency: settings.currencySymbol,
    generatedOn: DateTime.now(),
  ));
  await sharePdf(bytes, reportCardFileName(student.name));
}
