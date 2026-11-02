// lib/features/fees/fee_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/money.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/ui_kit.dart';
import '../../core/models/parent_alert.dart';
import '../parent_alerts/parent_messenger.dart';
import 'fee_messages.dart';
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
          if (async.valueOrNull?.account?.nextDue() != null && async.value!.student != null)
            IconButton(
              tooltip: 'Remind parent',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () {
                final d = async.value!;
                final next = d.account!.nextDue()!;
                ParentMessenger.send(context, ref, kind: ParentAlertKind.feeReminder, messages: [
                  ParentMessage(
                    d.student!,
                    feeReminderParams(ref.read(settingsProvider),
                        studentName: d.student!.name, roll: d.student!.collegeRollNo, due: next),
                  ),
                ]);
              },
            ),
          if (settings.razorpayConnected &&
              async.valueOrNull?.account?.isFullyPaid == false &&
              async.value!.student != null)
            IconButton(
              tooltip: 'Send payment link',
              icon: const Icon(Icons.link_rounded),
              onPressed: () => _sendPaymentLink(context, ref, async.value!),
            ),
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
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 40, color: context.palette.inkFaint),
                    const SizedBox(height: 12),
                    const Text('No fee plan yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _editPlan(context, ref, d),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Set up fee plan'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 104),
            children: [
              FeeHero(
                account: account,
                currency: cur,
                footnote: [
                  if (d.student?.section?.isNotEmpty == true) d.student!.section!,
                  if (account.discount > 0) '${formatMoney(account.discount, cur)} off ${formatMoney(account.totalFee, cur)}',
                  if (account.note.isNotEmpty) account.note,
                ].join(' · '),
              ),
              const SectionLabel('Instalments'),
              InstalmentList(account: account, currency: cur),
              const SectionLabel('Payments', padding: EdgeInsets.fromLTRB(20, 32, 20, 4)),
              if (d.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('No payments recorded yet.', style: TextStyle(color: context.palette.inkMuted)),
                ),
              for (final p in d.payments)
                PaymentRow(
                  payment: p,
                  currency: cur,
                  onTap: () => _showReceipt(context, ref, d, p),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: context.palette.inkMuted),
                    onSelected: (v) => v == 'receipt' ? _showReceipt(context, ref, d, p) : _voidPayment(context, ref, p),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'receipt', child: Text('View receipt')),
                      if (!p.voided) const PopupMenuItem(value: 'void', child: Text('Void payment')),
                    ],
                  ),
                ),
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
                  Text('Balance ${formatMoney(account.balance, cur)}', style: TextStyle(color: ctx.palette.inkMuted)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(labelText: 'Amount', prefixText: '$cur '),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: PaymentMode.values
                        .where((m) => m != PaymentMode.online) // gateway payments record themselves
                        .map((m) => ChoiceChip(label: Text(m.label), selected: mode == m, onSelected: (_) => setState(() => mode = m)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'Reference (UPI ID / cheque no.)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
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

  /// Razorpay payment link: the parent pays by UPI, card or netbanking and
  /// the razorpayWebhook function records the payment here by itself.
  Future<void> _sendPaymentLink(BuildContext context, WidgetRef ref, FeeDetail d) async {
    final account = d.account!;
    final student = d.student!;
    final settings = ref.read(settingsProvider);
    final cur = settings.currencySymbol;
    final suggested = account.payableNow();
    final amountCtrl = TextEditingController(text: suggested > 0.5 ? suggested.toStringAsFixed(0) : '');

    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment link'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The parent pays by UPI, card or netbanking, and the payment is recorded here automatically.',
                style: TextStyle(color: ctx.palette.inkMuted, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$cur ',
                helperText: 'Balance ${formatMoney(account.balance, cur)}',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(amountCtrl.text.trim()) ?? 0),
            child: const Text('Create link'),
          ),
        ],
      ),
    );
    if (amount == null || !context.mounted) return;
    if (amount < 1 || amount > account.balance + 0.5) {
      _error(context, 'Enter an amount between ${formatMoney(1, cur)} and ${formatMoney(account.balance, cur)}.');
      return;
    }

    final ({String url, double amount}) link;
    try {
      showMessage(context, 'Creating link…');
      link = await ref.read(feeRepoProvider).createPaymentLink(student.id, amount: amount);
    } catch (e) {
      if (context.mounted) _error(context, e);
      return;
    }
    if (!context.mounted) return;

    // The fee_reminder template carries the link, so no extra Meta template.
    final due = account.nextDue() ??
        InstalmentStatus(FeeInstalment(label: 'Fee', amount: account.balance, dueDate: DateTime.now()), 0,
            InstalmentState.upcoming);
    final params = feeReminderParams(settings,
        studentName: student.name, roll: student.collegeRollNo, due: due, amount: link.amount, payLink: link.url);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Link for ${formatMoney(link.amount, cur)}'),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: ctx.palette.surface, borderRadius: BorderRadius.circular(14)),
          child: SelectableText(link.url, style: const TextStyle(fontSize: 15)),
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link.url));
              showMessage(ctx, 'Link copied');
            },
          ),
          if (settings.parentAlertsEnabled)
            TextButton.icon(
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Send to parent'),
              onPressed: () => ParentMessenger.send(ctx, ref,
                  kind: ParentAlertKind.feeReminder, messages: [ParentMessage(student, params)]),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
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
    final student = d.student;
    return showReceiptDialog(context, text: text, extraActions: [
      if (student != null && !p.voided && settings.parentAlertsEnabled)
        TextButton.icon(
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: const Text('Send to parent'),
          onPressed: () => ParentMessenger.send(context, ref, kind: ParentAlertKind.feeReceipt, messages: [
            ParentMessage(
              student,
              feeReceiptParams(settings,
                  studentName: student.name, roll: student.collegeRollNo, payment: p, account: d.account!),
            ),
          ]),
        ),
    ]);
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.palette.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void'),
          ),
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
    showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
  }
}
