// lib/features/fees/fee_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/utils/money.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';

Color instalmentColor(InstalmentState state, Palette p) => switch (state) {
      InstalmentState.paid => p.success,
      InstalmentState.partial => p.warning,
      InstalmentState.overdue => p.danger,
      InstalmentState.upcoming => p.inkMuted,
    };

String instalmentLabel(InstalmentState state) => switch (state) {
      InstalmentState.paid => 'Paid',
      InstalmentState.partial => 'Part paid',
      InstalmentState.overdue => 'Overdue',
      InstalmentState.upcoming => 'Upcoming',
    };

/// The one number that matters (what's left, or "Paid in full"), a bar
/// showing how much is paid, and a line on what's due next.
class FeeHero extends StatelessWidget {
  final FeeAccount account;
  final String currency;
  final String? footnote;

  const FeeHero({super.key, required this.account, required this.currency, this.footnote});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final overdue = account.overdueAmount();
    final next = account.nextDue();
    final paidShare = account.netFee <= 0 ? 1.0 : account.paidAmount / account.netFee;

    final (String headline, Color tone) = account.isFullyPaid
        ? ('Paid in full', p.success)
        : (formatMoney(account.balance, currency), overdue > 0 ? p.danger : p.ink);

    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!account.isFullyPaid)
              Text('Balance', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
            Text(
              headline,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
                height: 1.15,
                color: tone,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 14),
            ProgressLine(value: paidShare, color: account.isFullyPaid ? p.success : p.accent),
            const SizedBox(height: 8),
            Text(
              'Paid ${formatMoney(account.paidAmount, currency)} of ${formatMoney(account.netFee, currency)}',
              style: TextStyle(fontSize: 13, color: p.inkMuted),
            ),
            if (overdue > 0 || next != null) ...[
              const SizedBox(height: 16),
              _DueStrip(
                overdue: overdue > 0,
                text: overdue > 0
                    ? '${formatMoney(overdue, currency)} overdue'
                    : '${formatMoney(next!.outstanding, currency)} due ${DateFormat('d MMM').format(next.instalment.dueDate)}',
              ),
            ],
            if (footnote != null && footnote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(footnote!, style: TextStyle(fontSize: 13, color: p.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DueStrip extends StatelessWidget {
  final bool overdue;
  final String text;
  const _DueStrip({required this.overdue, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = overdue ? p.danger : p.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: overdue ? p.dangerSoft : p.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(overdue ? Icons.error_outline_rounded : Icons.event_rounded, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Instalment schedule as a compact timeline: a status dot, label and due
/// date, and the amount on the right.
class InstalmentList extends StatelessWidget {
  final FeeAccount account;
  final String currency;
  const InstalmentList({super.key, required this.account, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = account.statuses();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('No instalments set.', style: TextStyle(color: p.inkMuted)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          FadeSlideIn(
            index: i,
            child: _InstalmentRow(status: rows[i], currency: currency, last: i == rows.length - 1),
          ),
      ],
    );
  }
}

class _InstalmentRow extends StatelessWidget {
  final InstalmentStatus status;
  final String currency;
  final bool last;
  const _InstalmentRow({required this.status, required this.currency, required this.last});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = status;
    final color = instalmentColor(s.state, p);
    final paid = s.state == InstalmentState.paid;

    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dot + connecting line.
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: paid ? color : Colors.transparent,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                  if (!last) Expanded(child: Container(width: 2, color: p.line)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.instalment.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('d MMM yyyy').format(s.instalment.dueDate),
                            style: TextStyle(fontSize: 13, color: p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(s.instalment.amount, currency),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: paid ? p.inkMuted : p.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // Part-paid (whether due yet or overdue): say what's left.
                          !paid && s.covered > 0
                              ? '${formatMoney(s.outstanding, currency)} left'
                              : instalmentLabel(s.state),
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One payment in a list: amount and mode, receipt number and date.
class PaymentRow extends StatelessWidget {
  final FeePayment payment;
  final String currency;
  final VoidCallback onTap;
  final Widget? trailing;

  const PaymentRow({super.key, required this.payment, required this.currency, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pay = payment;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, trailing == null ? 20 : 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatMoney(pay.amount, currency),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: pay.voided ? p.inkFaint : p.ink,
                          decoration: pay.voided ? TextDecoration.lineThrough : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(pay.mode.label, style: TextStyle(fontSize: 13, color: p.inkMuted)),
                      if (pay.voided) ...[
                        const SizedBox(width: 8),
                        StatusPill(text: 'Void', color: p.danger, background: p.dangerSoft),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      'Receipt #${pay.receiptNo}',
                      DateFormat('d MMM yyyy').format(pay.paidOn),
                      if (pay.reference.isNotEmpty) pay.reference,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.inkMuted),
                  ),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: p.inkFaint),
          ],
        ),
      ),
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

/// Receipt preview with copy, PDF ([pdf] builds it) and optional extra
/// actions (e.g. WhatsApp).
Future<void> showReceiptDialog(
  BuildContext context, {
  required String text,
  Future<void> Function()? pdf,
  List<Widget> extraActions = const [],
}) {
  return showDialog(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return AlertDialog(
        title: const Text('Receipt'),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
          child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6)),
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              showMessage(ctx, 'Receipt copied');
            },
          ),
          if (pdf != null)
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
              onPressed: () async {
                try {
                  await pdf();
                } catch (_) {
                  if (ctx.mounted) showMessage(ctx, 'Could not create the PDF.', error: true);
                }
              },
            ),
          ...extraActions,
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      );
    },
  );
}
