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
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';
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

  String _filterLabel(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.overdue => 'Overdue',
        _Filter.due => 'Balance due',
        _Filter.paid => 'Fully paid',
        _Filter.noPlan => 'No plan',
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feesOverviewProvider);
    final settings = ref.watch(settingsProvider);
    final cur = settings.currencySymbol;
    final p = context.palette;

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
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: async.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _applyToGroup(async.value!),
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text('Plan for a ${settings.groupLabel.toLowerCase()}'),
            )
          : null,
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
              padding: const EdgeInsets.only(top: 8, bottom: 104),
              children: [
                // Collected vs expected: the number the owner opens this page for.
                FadeSlideIn(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Collected', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
                        Text(
                          formatMoney(collected, cur),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.4,
                            height: 1.15,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 14),
                        ProgressLine(value: expected <= 0 ? 0 : collected / expected),
                        const SizedBox(height: 8),
                        Text(
                          'of ${formatMoney(expected, cur)} expected${_group == null ? '' : ' · $_group'}',
                          style: TextStyle(fontSize: 13, color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FadeSlideIn(
                          index: 1,
                          child: StatBlock(
                            value: formatMoney((expected - collected).clamp(0, double.infinity), cur),
                            label: 'Outstanding',
                            onTap: () => setState(() => _filter = _Filter.due),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FadeSlideIn(
                          index: 2,
                          child: StatBlock(
                            value: formatMoney(overdue, cur),
                            label: overdueCount == 1 ? 'Overdue · 1 student' : 'Overdue · $overdueCount students',
                            tone: overdue > 0 ? p.danger : null,
                            onTap: () => setState(() => _filter = _Filter.overdue),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search student',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if (groups.isNotEmpty) ...[
                        MenuChip(
                          value: _group,
                          options: groups,
                          allLabel: 'All ${settings.groupLabelPlural.toLowerCase()}',
                          onSelected: (g) => setState(() => _group = g),
                        ),
                        Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: p.line),
                      ],
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_filterLabel(f)),
                            selected: _filter == f,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: EmptyNote(icon: Icons.search_off_rounded, text: 'No students match.'),
                  ),
                for (var i = 0; i < visible.length; i++) FadeSlideIn(index: i, child: _row(visible[i], cur)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(FeeRow r, String cur) {
    final p = context.palette;
    final a = r.account;
    final overdue = a?.overdueAmount() ?? 0;
    final (String text, Color color) = a == null
        ? ('No plan', p.inkFaint)
        : overdue > 0
            ? ('${formatMoney(overdue, cur)} overdue', p.danger)
            : a.isFullyPaid
                ? ('Paid', p.success)
                : ('${formatMoney(a.balance, cur)} due', p.ink);
    return InkWell(
      onTap: () async {
        await context.push('/admin/fees/${r.student.id}');
        ref.invalidate(feesOverviewProvider);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.student.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (r.student.section?.isNotEmpty == true)
                        Text(r.student.section!, style: TextStyle(fontSize: 13, color: p.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            if (a != null && !a.isFullyPaid) ...[
              const SizedBox(height: 10),
              ProgressLine(
                value: a.netFee <= 0 ? 1 : a.paidAmount / a.netFee,
                height: 4,
                color: overdue > 0 ? p.danger : p.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _remindOverdue(List<FeeRow> rows) async {
    final overdue = rows.where((r) => _group == null || r.student.section == _group).where((r) {
      final a = r.account;
      return a != null && a.overdueAmount() > 0;
    }).toList();
    if (overdue.isEmpty) {
      showMessage(context, 'No overdue fees.', success: true);
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
      showMessage(context, 'No students are in a ${settings.groupLabel.toLowerCase()} yet.');
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
              decoration: InputDecoration(labelText: settings.groupLabel),
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
        showMessage(context, 'Everyone in that ${settings.groupLabel.toLowerCase()} already has a plan.');
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
        showMessage(context, 'Fee plan applied to ${targets.length} students.', success: true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}
