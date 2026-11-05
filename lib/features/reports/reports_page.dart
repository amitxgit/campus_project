// lib/features/reports/reports_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/models/test_result.dart';
import '../../core/models/user.dart';
import '../../core/utils/csv.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/share_file.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/ui_kit.dart';
import 'exports.dart';
import 'report_card_share.dart';

/// Admin downloads: report cards (PDF) and spreadsheets (CSV, opens in Excel
/// or Google Sheets).
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String? _busy; // which report is being made

  final _range = DateFormat('d MMM yyyy');

  /// Runs [make] with a spinner on its row and reports errors.
  Future<void> _run(String key, Future<void> Function() make) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await make();
    } catch (e) {
      if (mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<DateTimeRange?> _pickRange(String title) {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      helpText: title,
      firstDate: DateTime(now.year - 3),
      lastDate: DateUtils.dateOnly(now),
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month), end: DateUtils.dateOnly(now)),
    );
  }

  /// Picked range as [from, to) covering whole days.
  (DateTime, DateTime) _bounds(DateTimeRange r) => (r.start, DateUtils.dateOnly(r.end).add(const Duration(days: 1)));

  String _rangeLabel(DateTimeRange r) => '${_range.format(r.start)} - ${_range.format(r.end)}';

  Future<Map<String, UserAccount>> _studentsById() async =>
      {for (final s in await ref.read(authRepoProvider).allStudents(limit: 5000)) s.id: s};

  // ------------------------------------------------------------------ reports

  Future<void> _feeLedger() async {
    final r = await _pickRange('Payments between');
    if (r == null) return;
    await _run('ledger', () async {
      final (from, to) = _bounds(r);
      final fees = ref.read(feeRepoProvider);
      final results = await Future.wait([fees.paymentsBetween(from, to), fees.allAccounts(), _studentsById()]);
      final payments = results[0] as List<({String studentId, FeePayment payment})>;
      final accounts = {for (final a in results[1] as List<FeeAccount>) a.studentId: a};
      final rows = feeLedgerRows(payments, accounts: accounts, students: results[2] as Map<String, UserAccount>);
      await shareCsv(csvBytes(rows), '${fileSlug('fee ledger ${_rangeLabel(r)}')}.csv');
    });
  }

  Future<void> _dues() => _run('dues', () async {
        final results = await Future.wait([ref.read(feeRepoProvider).allAccounts(), _studentsById()]);
        final rows = duesRows(results[0] as List<FeeAccount>, students: results[1] as Map<String, UserAccount>);
        if (rows.length == 1) {
          if (mounted) showMessage(context, 'Nobody owes fees right now.');
          return;
        }
        await shareCsv(csvBytes(rows), 'dues-${fileSlug(_range.format(DateTime.now()))}.csv');
      });

  Future<void> _attendance() async {
    final settings = ref.read(settingsProvider);
    if (settings.groups.isEmpty) {
      showMessage(context, 'Add batches in Settings first.');
      return;
    }
    final batch = await _pickOne<String>('Which ${settings.groupLabel.toLowerCase()}?', settings.groups, (g) => g);
    if (batch == null || !mounted) return;
    final r = await _pickRange('Attendance between');
    if (r == null) return;
    await _run('attendance', () async {
      final (from, to) = _bounds(r);
      final students = await ref.read(authRepoProvider).studentsInSection(batch, limit: 1000);
      final records = await ref.read(attendanceRepoProvider).between(from, to);
      final rows = attendanceRows(students, records);
      await shareCsv(csvBytes(rows), '${fileSlug('attendance $batch ${_rangeLabel(r)}')}.csv');
    });
  }

  Future<void> _testResults() async {
    List<TestPaper> tests = const [];
    await _run('tests', () async => tests = await ref.read(testRepoProvider).recent());
    if (!mounted) return;
    if (tests.isEmpty) {
      showMessage(context, 'No tests yet.');
      return;
    }
    final test = await _pickOne<TestPaper>(
      'Which test?',
      tests,
      (t) => '${t.title} · ${t.section} · ${DateFormat('d MMM').format(t.date)}',
    );
    if (test == null) return;
    await _run('tests', () async {
      final marks = await ref.read(testRepoProvider).marks(test.id);
      final students = await ref.read(authRepoProvider).studentsInSection(test.section, limit: 1000);
      final rows = testResultRows(test, marks, students);
      await shareCsv(csvBytes(rows), '${fileSlug('${test.name} ${test.section}')}.csv');
    });
  }

  Future<void> _reportCard() async {
    List<UserAccount> students = const [];
    await _run('card', () async => students = (await _studentsById()).values.toList()
      ..sort((a, b) => a.name.compareTo(b.name)));
    if (!mounted || students.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final picked = await showDialog<(UserAccount, bool)>(
      context: context,
      builder: (_) => _StudentPicker(students: students, offerFees: settings.feesEnabled),
    );
    if (picked == null) return;
    await _run('card', () => shareReportCard(ref, picked.$1, withFees: picked.$2));
  }

  Future<T?> _pickOne<T>(String title, List<T> options, String Function(T) label) => showDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: [
            SizedBox(
              width: 420,
              height: options.length > 8 ? 420 : null,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(title: Text(label(o)), onTap: () => Navigator.pop(ctx, o)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    Widget item(String key, IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(icon, color: context.palette.ink),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(color: context.palette.inkMuted, fontSize: 13)),
          trailing: _busy == key
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.ios_share_rounded, size: 20, color: context.palette.inkMuted),
          onTap: _busy == null ? onTap : null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionLabel('PDF'),
          item('card', Icons.workspace_premium_outlined, 'Report card',
              'Results with rank, attendance${settings.feesEnabled ? ', fees (optional)' : ''}', _reportCard),
          const SectionLabel('Spreadsheets (CSV)'),
          if (settings.feesEnabled) ...[
            item('ledger', Icons.receipt_long_outlined, 'Fee ledger', 'Every payment in a date range', _feeLedger),
            item('dues', Icons.pending_actions_outlined, 'Dues list', 'Who owes what, most overdue first', _dues),
          ],
          item('attendance', Icons.fact_check_outlined, 'Batch attendance',
              'Each student\'s classes and % for a date range', _attendance),
          if (settings.testsEnabled)
            item('tests', Icons.quiz_outlined, 'Test results', 'Marks and ranks for one test', _testResults),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Spreadsheets open in Excel or Google Sheets. On a phone, choose where to send them; in a browser they download.',
              style: TextStyle(color: context.palette.inkMuted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search a student; choose whether the report card shows fees.
class _StudentPicker extends StatefulWidget {
  final List<UserAccount> students;
  final bool offerFees;
  const _StudentPicker({required this.students, required this.offerFees});

  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  String _q = '';
  bool _fees = false;

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final shown = widget.students
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.section ?? '').toLowerCase().contains(q) ||
            (s.collegeRollNo ?? '').toLowerCase().contains(q))
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('Report card for'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 440,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search name, batch or roll no.', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          if (widget.offerFees)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include fee status'),
              value: _fees,
              onChanged: (v) => setState(() => _fees = v),
            ),
          Expanded(
            child: ListView(children: [
              for (final s in shown)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.name),
                  subtitle: Text([if ((s.section ?? '').isNotEmpty) s.section!, if ((s.collegeRollNo ?? '').isNotEmpty) s.collegeRollNo!].join(' · ')),
                  onTap: () => Navigator.pop(context, (s, _fees)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
