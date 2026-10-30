// lib/features/fees/fee_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/money.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/async_error_widget.dart';
import 'fee_plan_dialog.dart';
import 'fee_widgets.dart';

typedef FeeDetail = ({UserAccount? student, FeeAccount? account, List<FeePayment> payments});

final feeDetailProvider = FutureProvider.autoDispose.family<FeeDetail, String>((ref, studentId) async {
  final repo = ref.watch(feeRepoProvider);
  final results = await Future.wait([
    ref.watch(authRepoProvider).userById(studentId),
    repo.account(studentId),
    repo.payments(studentId),
  ]);
  return (
    student: results[0] as UserAccount?,
    account: results[1] as FeeAccount?,
    payments: results[2] as List<FeePayment>,
  );
});

/// Admin view of one student's fees: plan, instalments, payments, receipts.
class FeeDetailPage extends ConsumerWidget {
  final String studentId;
  const FeeDetailPage({super.key, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(feeDetailProvider(studentId));
    final settings = ref.watch(settingsProvider);
    final cur = settings.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.student?.name ?? 'Student fees'),
        actions: [
          if (async.hasValue)
            IconButton(
              tooltip: 'Edit fee plan',
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: () => _editPlan(context, ref, async.value!),
            ),
        ],
      ),
      floatingActionButton: async.valueOrNull?.account == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _recordPayment(context, ref, async.value!),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Record payment'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(e),
          onRetry: () => ref.invalidate(feeDetailProvider(studentId)),
        ),
        data: (d) {
          final account = d.account;
          if (account == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 56),
                  const SizedBox(height: 12),
                  const Text('No fee plan yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _editPlan(context, ref, d),
                    icon: const Icon(Icons.add),
                    label: const Text('Set up fee plan'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      FeeSummaryRow(account: account, currency: cur),
                      if (account.discount > 0 || account.note.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text(
                          [
                            if (account.discount > 0) 'Discount ${formatMoney(account.discount, cur)} on ${formatMoney(account.totalFee, cur)}',
                            if (account.note.isNotEmpty) account.note,
                          ].join(' • '),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Instalments', style: TextStyle(fontWeight: FontWeight.w900)),
              InstalmentList(account: account, currency: cur),
              const SizedBox(height: 16),
              const Text('Payments', style: TextStyle(fontWeight: FontWeight.w900)),
              if (d.payments.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No payments recorded yet.')),
              ...d.payments.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.voided ? Icons.block_rounded : Icons.receipt_rounded,
                        color: p.voided ? Colors.grey : Colors.green),
                    title: Text(
                      '${formatMoney(p.amount, cur)} • ${p.mode.label}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: p.voided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text('#${p.receiptNo} • ${DateFormat('d MMM yyyy').format(p.paidOn)}'
                        '${p.reference.isNotEmpty ? ' • ${p.reference}' : ''}${p.voided ? ' • VOID' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'receipt'
                          ? _showReceipt(context, ref, d, p)
                          : _voidPayment(context, ref, p),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'receipt', child: Text('View receipt')),
                        if (!p.voided) const PopupMenuItem(value: 'void', child: Text('Void payment')),
                      ],
                    ),
                    onTap: () => _showReceipt(context, ref, d, p),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editPlan(BuildContext context, WidgetRef ref, FeeDetail d) async {
    final student = d.student;
    if (student == null) return;
    final settings = ref.read(settingsProvider);
    final plan = await showFeePlanDialog(
      context,
      title: d.account == null ? 'Set up fee plan' : 'Edit fee plan',
      currency: settings.currencySymbol,
      initial: d.account,
    );
    if (plan == null) return;
    try {
      await ref.read(feeRepoProvider).savePlan(FeeAccount(
            studentId: student.id,
            studentName: student.name,
            section: student.section ?? '',
            totalFee: plan.totalFee,
            discount: plan.discount,
            instalments: plan.instalments,
            paidAmount: d.account?.paidAmount ?? 0,
            note: plan.note,
            updatedAt: DateTime.now(),
          ));
      ref.invalidate(feeDetailProvider(studentId));
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, FeeDetail d) async {
    final account = d.account!;
    final cur = ref.read(settingsProvider).currencySymbol;
    final next = account.nextDue();
    final amountCtrl = TextEditingController(
      text: next == null ? '' : next.outstanding.toStringAsFixed(0),
    );
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    PaymentMode mode = PaymentMode.cash;
    DateTime paidOn = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Record payment'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Balance: ${formatMoney(account.balance, cur)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(labelText: 'Amount', prefixText: '$cur ', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: PaymentMode.values
                        .map((m) => ChoiceChip(label: Text(m.label), selected: mode == m, onSelected: (_) => setState(() => mode = m)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'Reference (UPI ID / cheque no.)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Paid on ${DateFormat('d MMM yyyy').format(paidOn)}'),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final dt = await showDatePicker(
                          context: ctx,
                          initialDate: paidOn,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now(),
                        );
                        if (dt != null) setState(() => paidOn = dt);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    try {
      final me = await ref.read(authRepoProvider).currentUser();
      final payment = await ref.read(feeRepoProvider).recordPayment(
            studentId: studentId,
            amount: amount,
            mode: mode,
            reference: refCtrl.text.trim(),
            note: noteCtrl.text.trim(),
            paidOn: paidOn,
            receivedBy: me?.name ?? '',
          );
      ref.invalidate(feeDetailProvider(studentId));
      final fresh = await ref.read(feeDetailProvider(studentId).future);
      if (context.mounted) await _showReceipt(context, ref, fresh, payment);
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  Future<void> _showReceipt(BuildContext context, WidgetRef ref, FeeDetail d, FeePayment p) {
    final settings = ref.read(settingsProvider);
    final text = receiptText(
      instituteName: settings.name,
      studentName: d.student?.name ?? d.account!.studentName,
      payment: p,
      account: d.account!,
      currency: settings.currencySymbol,
    );
    return showReceiptDialog(context, text: text, extraActions: receiptShareActions(context, d.student, text));
  }

  Future<void> _voidPayment(BuildContext context, WidgetRef ref, FeePayment p) async {
    final cur = ref.read(settingsProvider).currencySymbol;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void this payment?'),
        content: Text('Receipt #${p.receiptNo} for ${formatMoney(p.amount, cur)} will be marked void and '
            'removed from the paid total. The record is kept for audit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(feeRepoProvider).voidPayment(studentId, p);
      ref.invalidate(feeDetailProvider(studentId));
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  void _error(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
    );
  }
}

/// Extra receipt buttons. Filled in by the parent-alerts feature.
List<Widget> receiptShareActions(BuildContext context, UserAccount? student, String text) => const [];
