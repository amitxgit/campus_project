// lib/features/fees/fee_plan_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/utils/money.dart';

class FeePlanInput {
  final double totalFee;
  final double discount;
  final List<FeeInstalment> instalments;
  final String note;
  const FeePlanInput(this.totalFee, this.discount, this.instalments, this.note);
}

/// Collects a fee plan: total, discount and an evenly split instalment
/// schedule. Used for one student and for a whole batch.
Future<FeePlanInput?> showFeePlanDialog(
  BuildContext context, {
  required String title,
  required String currency,
  FeeAccount? initial,
  Widget? header,
}) {
  final totalCtrl = TextEditingController(text: initial == null ? '' : initial.totalFee.toStringAsFixed(0));
  final discountCtrl = TextEditingController(text: initial == null || initial.discount == 0 ? '' : initial.discount.toStringAsFixed(0));
  final noteCtrl = TextEditingController(text: initial?.note ?? '');
  int count = initial?.instalments.length ?? 3;
  if (count < 1) count = 1;
  int gap = 1;
  DateTime firstDue = initial?.instalments.isNotEmpty == true
      ? (initial!.instalments.map((i) => i.dueDate).reduce((a, b) => a.isBefore(b) ? a : b))
      : DateTime.now();

  return showDialog<FeePlanInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final total = double.tryParse(totalCtrl.text) ?? 0;
        final discount = double.tryParse(discountCtrl.text) ?? 0;
        final net = total - discount;
        final preview = net > 0
            ? FeeInstalment.split(total: net, count: count, firstDue: firstDue, monthsApart: gap)
            : <FeeInstalment>[];

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header != null) ...[header, const SizedBox(height: 12)],
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: totalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Total fee', prefixText: '$currency ', border: const OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: discountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Discount', prefixText: '$currency ', border: const OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: count,
                        decoration: const InputDecoration(labelText: 'Instalments', border: OutlineInputBorder()),
                        items: List.generate(12, (i) => i + 1)
                            .map((n) => DropdownMenuItem(value: n, child: Text(n == 1 ? 'One-time' : '$n'))).toList(),
                        onChanged: (v) => setState(() => count = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: gap,
                        decoration: const InputDecoration(labelText: 'Every', border: OutlineInputBorder()),
                        items: const [1, 2, 3, 6]
                            .map((m) => DropdownMenuItem(value: m, child: Text(m == 1 ? 'Month' : '$m months'))).toList(),
                        onChanged: count == 1 ? null : (v) => setState(() => gap = v!),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_rounded),
                    title: Text('First due ${DateFormat('d MMM yyyy').format(firstDue)}'),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: firstDue,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (d != null) setState(() => firstDue = d);
                      },
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Sibling discount', border: OutlineInputBorder()),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Net fee ${formatMoney(net, currency)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...preview.map((i) => Text(
                          '${i.label}: ${formatMoney(i.amount, currency)} • ${DateFormat('d MMM yyyy').format(i.dueDate)}',
                          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 13),
                        )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (total <= 0 || discount < 0 || net <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter a total fee, and a discount smaller than it.')),
                  );
                  return;
                }
                Navigator.pop(ctx, FeePlanInput(total, discount, preview, noteCtrl.text.trim()));
              },
              child: const Text('Save plan'),
            ),
          ],
        );
      },
    ),
  );
  // Controllers are left to the GC: disposing them here would race the
  // dialog's closing animation, which still rebuilds the text fields.
}
