// lib/features/fees/fee_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/utils/money.dart';

Color instalmentColor(InstalmentState state, ColorScheme cs) => switch (state) {
      InstalmentState.paid => Colors.green,
      InstalmentState.partial => Colors.orange,
      InstalmentState.overdue => cs.error,
      InstalmentState.upcoming => cs.onSurfaceVariant,
    };

String instalmentLabel(InstalmentState state) => switch (state) {
      InstalmentState.paid => 'Paid',
      InstalmentState.partial => 'Part paid',
      InstalmentState.overdue => 'Overdue',
      InstalmentState.upcoming => 'Upcoming',
    };

/// Instalment schedule with paid/overdue status for each row.
class InstalmentList extends StatelessWidget {
  final FeeAccount account;
  final String currency;
  const InstalmentList({super.key, required this.account, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = account.statuses();
    if (rows.isEmpty) return const Text('No instalments set.');
    return Column(
      children: rows.map((s) {
        final color = instalmentColor(s.state, cs);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(
            s.state == InstalmentState.paid ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: color,
          ),
          title: Text(s.instalment.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Due ${DateFormat('d MMM yyyy').format(s.instalment.dueDate)}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(s.instalment.amount, currency), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                s.state == InstalmentState.partial
                    ? '${formatMoney(s.outstanding, currency)} left'
                    : instalmentLabel(s.state),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Three-figure summary: net fee, paid, balance.
class FeeSummaryRow extends StatelessWidget {
  final FeeAccount account;
  final String currency;
  const FeeSummaryRow({super.key, required this.account, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overdue = account.overdueAmount();
    Widget cell(String label, double value, Color color) => Expanded(
          child: Column(
            children: [
              Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(formatMoney(value, currency),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ),
            ],
          ),
        );
    return Row(
      children: [
        cell('Total fee', account.netFee, cs.onSurface),
        cell('Paid', account.paidAmount, Colors.green),
        cell(overdue > 0 ? 'Overdue' : 'Balance', overdue > 0 ? overdue : account.balance,
            overdue > 0 ? cs.error : (account.isFullyPaid ? Colors.green : Colors.orange)),
      ],
    );
  }
}

String receiptText({
  required String instituteName,
  required String studentName,
  required FeePayment payment,
  required FeeAccount account,
  required String currency,
}) {
  final b = StringBuffer()
    ..writeln('$instituteName — Fee Receipt')
    ..writeln('Receipt No: ${payment.receiptNo}')
    ..writeln('Date: ${DateFormat('d MMM yyyy').format(payment.paidOn)}')
    ..writeln('Student: $studentName${account.section.isNotEmpty ? ' (${account.section})' : ''}')
    ..writeln('Amount: ${formatMoney(payment.amount, currency)} via ${payment.mode.label}');
  if (payment.reference.isNotEmpty) b.writeln('Ref: ${payment.reference}');
  b.writeln('Balance due now: ${formatMoney(account.balance.clamp(0, double.infinity), currency)}');
  if (payment.voided) b.writeln('*** VOID ***');
  return b.toString().trim();
}

/// Receipt preview with copy and optional extra actions (e.g. WhatsApp).
Future<void> showReceiptDialog(
  BuildContext context, {
  required String text,
  List<Widget> extraActions = const [],
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Receipt'),
      content: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', height: 1.5)),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Receipt copied')));
          },
        ),
        ...extraActions,
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
      ],
    ),
  );
}
