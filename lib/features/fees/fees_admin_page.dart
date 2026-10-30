// lib/features/fees/fees_admin_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/fee.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/money.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/parent_alert.dart';
import '../parent_alerts/parent_messenger.dart';
import 'fee_detail_page.dart';
import 'fee_plan_dialog.dart';

class FeeRow {
  final UserAccount student;
  final FeeAccount? account;
  const FeeRow(this.student, this.account);
}

final feesOverviewProvider = FutureProvider.autoDispose<List<FeeRow>>((ref) async {
  final results = await Future.wait([
    ref.watch(authRepoProvider).allStudents(),
    ref.watch(feeRepoProvider).allAccounts(),
  ]);
  final students = results[0] as List<UserAccount>;
  final accounts = {for (final a in results[1] as List<FeeAccount>) a.studentId: a};
  return students.map((s) => FeeRow(s, accounts[s.id])).toList();
});

enum _Filter { all, overdue, due, paid, noPlan }

class FeesAdminPage extends ConsumerStatefulWidget {
  const FeesAdminPage({super.key});

  @override
  ConsumerState<FeesAdminPage> createState() => _FeesAdminPageState();
}

class _FeesAdminPageState extends ConsumerState<FeesAdminPage> {
  String? _group;
  _Filter _filter = _Filter.all;
  String _query = '';

  bool _matches(FeeRow r) {
    if (_group != null && r.student.section != _group) return false;
    if (_query.isNotEmpty && !r.student.name.toLowerCase().contains(_query.toLowerCase())) return false;
    final a = r.account;
    return switch (_filter) {
      _Filter.all => true,
      _Filter.noPlan => a == null,
      _Filter.overdue => a != null && a.overdueAmount() > 0,
      _Filter.due => a != null && !a.isFullyPaid,
      _Filter.paid => a != null && a.isFullyPaid,
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feesOverviewProvider);
    final settings = ref.watch(settingsProvider);
    final cur = settings.currencySymbol;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fees'),
        actions: [
          if (settings.parentAlertsEnabled)
            IconButton(
              tooltip: 'Remind parents of overdue fees',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => _remindOverdue(async.valueOrNull ?? []),
            ),
          TextButton.icon(
            onPressed: () => _applyToGroup(async.valueOrNull ?? []),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text('Plan for ${settings.groupLabel.toLowerCase()}'),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(feesOverviewProvider)),
        data: (rows) {
          final withPlan = rows.where((r) => r.account != null && (_group == null || r.student.section == _group));
          final expected = withPlan.fold(0.0, (s, r) => s + r.account!.netFee);
          final collected = withPlan.fold(0.0, (s, r) => s + r.account!.paidAmount);
          final overdue = withPlan.fold(0.0, (s, r) => s + r.account!.overdueAmount());
          final overdueCount = withPlan.where((r) => r.account!.overdueAmount() > 0).length;
          final groups = rows.map((r) => r.student.section ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
          final visible = rows.where(_matches).toList()
            ..sort((a, b) => (b.account?.overdueAmount() ?? 0).compareTo(a.account?.overdueAmount() ?? 0));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(feesOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _stat('Expected', formatMoney(expected, cur), Icons.account_balance_wallet_rounded, cs.primary),
                    _stat('Collected', formatMoney(collected, cur), Icons.savings_rounded, Colors.green),
                    _stat('Outstanding', formatMoney((expected - collected).clamp(0, double.infinity), cur), Icons.hourglass_bottom_rounded, Colors.orange),
                    _stat('Overdue ($overdueCount)', formatMoney(overdue, cur), Icons.warning_amber_rounded, cs.error),
                  ],
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search student',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String?>(
                    value: _group,
                    hint: Text('All ${settings.groupLabelPlural.toLowerCase()}'),
                    items: [
                      DropdownMenuItem(value: null, child: Text('All ${settings.groupLabelPlural.toLowerCase()}')),
                      ...groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                    ],
                    onChanged: (g) => setState(() => _group = g),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in _Filter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => 'All',
                          _Filter.overdue => 'Overdue',
                          _Filter.due => 'Balance due',
                          _Filter.paid => 'Fully paid',
                          _Filter.noPlan => 'No plan',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No students match.')),
                  ),
                ...visible.map((r) => _row(r, cur, cs)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color))),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(FeeRow r, String cur, ColorScheme cs) {
    final a = r.account;
    final overdue = a?.overdueAmount() ?? 0;
    final (String text, Color color) = a == null
        ? ('No plan', cs.onSurfaceVariant)
        : overdue > 0
            ? ('${formatMoney(overdue, cur)} overdue', cs.error)
            : a.isFullyPaid
                ? ('Paid', Colors.green)
                : ('${formatMoney(a.balance, cur)} due', Colors.orange);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(r.student.name.isEmpty ? '?' : r.student.name[0].toUpperCase())),
        title: Text(r.student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          if (r.student.section?.isNotEmpty == true) r.student.section!,
          if (a != null) 'Paid ${formatMoney(a.paidAmount, cur)} of ${formatMoney(a.netFee, cur)}',
        ].join(' • ')),
        trailing: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        onTap: () async {
          await context.push('/admin/fees/${r.student.id}');
          ref.invalidate(feesOverviewProvider);
        },
      ),
    );
  }

  Future<void> _remindOverdue(List<FeeRow> rows) async {
    final overdue = rows.where((r) => _group == null || r.student.section == _group).where((r) {
      final a = r.account;
      return a != null && a.overdueAmount() > 0;
    }).toList();
    if (overdue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No overdue fees. 🎉')));
      return;
    }
    await ParentMessenger.send(context, ref, kind: ParentAlertKind.feeReminder, messages: [
      for (final r in overdue)
        ParentMessage(
          r.student,
          // Remind about the whole overdue amount, dated by the oldest unpaid instalment.
          () {
            final p = feeReminderParams(ref, r.student.name, r.account!.nextDue()!);
            p[0] = formatMoney(r.account!.overdueAmount(), ref.read(settingsProvider).currencySymbol);
            return p;
          }(),
        ),
    ]);
  }

  /// Gives every student in a batch the same fee plan in one go.
  Future<void> _applyToGroup(List<FeeRow> rows) async {
    final settings = ref.read(settingsProvider);
    final groups = rows.map((r) => r.student.section ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No students are in a ${settings.groupLabel.toLowerCase()} yet.')),
      );
      return;
    }
    String group = _group ?? groups.first;
    bool skipExisting = true;

    final plan = await showFeePlanDialog(
      context,
      title: 'Fee plan for a ${settings.groupLabel.toLowerCase()}',
      currency: settings.currencySymbol,
      header: StatefulBuilder(
        builder: (ctx, setState) => Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: group,
              decoration: InputDecoration(labelText: settings.groupLabel, border: const OutlineInputBorder()),
              items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (g) => setState(() => group = g!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: skipExisting,
              title: const Text("Skip students who already have a plan"),
              onChanged: (v) => setState(() => skipExisting = v ?? true),
            ),
          ],
        ),
      ),
    );
    if (plan == null) return;

    final targets = rows.where((r) => r.student.section == group && (!skipExisting || r.account == null)).toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Everyone in that group already has a plan.')));
      }
      return;
    }
    try {
      await ref.read(feeRepoProvider).savePlans(targets
          .map((r) => FeeAccount(
                studentId: r.student.id,
                studentName: r.student.name,
                section: r.student.section ?? '',
                totalFee: plan.totalFee,
                discount: plan.discount,
                instalments: plan.instalments,
                paidAmount: r.account?.paidAmount ?? 0,
                note: plan.note,
                updatedAt: DateTime.now(),
              ))
          .toList());
      ref.invalidate(feesOverviewProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fee plan applied to ${targets.length} students.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
        );
      }
    }
  }
}
