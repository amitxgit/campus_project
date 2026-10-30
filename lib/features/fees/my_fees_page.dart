// lib/features/fees/my_fees_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/fee.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/money.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import 'fee_widgets.dart';

final myFeesProvider = FutureProvider.autoDispose<({FeeAccount? account, List<FeePayment> payments, String name})>((ref) async {
  final me = await ref.watch(authRepoProvider).currentUser();
  if (me == null) throw Exception('Not logged in');
  final repo = ref.watch(feeRepoProvider);
  final account = await repo.account(me.id);
  final payments = account == null ? <FeePayment>[] : await repo.payments(me.id);
  return (account: account, payments: payments, name: me.name);
});

class MyFeesPage extends ConsumerWidget {
  const MyFeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myFeesProvider);
    final settings = ref.watch(settingsProvider);
    final cur = settings.currencySymbol;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Fees')),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(myFeesProvider)),
        data: (d) {
          final account = d.account;
          if (account == null) {
            return const Center(child: Text('No fee details have been added for you yet.'));
          }
          final next = account.nextDue();
          final overdue = account.overdueAmount();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myFeesProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (overdue > 0 || next != null)
                  Card(
                    color: overdue > 0 ? cs.errorContainer : cs.primaryContainer,
                    child: ListTile(
                      leading: Icon(overdue > 0 ? Icons.warning_amber_rounded : Icons.event_rounded,
                          color: overdue > 0 ? cs.onErrorContainer : cs.onPrimaryContainer),
                      title: Text(
                        overdue > 0
                            ? '${formatMoney(overdue, cur)} is overdue'
                            : '${formatMoney(next!.outstanding, cur)} due ${DateFormat('d MMM').format(next.instalment.dueDate)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: overdue > 0 ? cs.onErrorContainer : cs.onPrimaryContainer,
                        ),
                      ),
                      subtitle: const Text('Please pay at the office.'),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FeeSummaryRow(account: account, currency: cur),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Instalments', style: TextStyle(fontWeight: FontWeight.w900)),
                InstalmentList(account: account, currency: cur),
                const SizedBox(height: 16),
                const Text('Receipts', style: TextStyle(fontWeight: FontWeight.w900)),
                if (d.payments.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No payments yet.')),
                ...d.payments.where((p) => !p.voided).map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_rounded, color: Colors.green),
                      title: Text('${formatMoney(p.amount, cur)} • ${p.mode.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('#${p.receiptNo} • ${DateFormat('d MMM yyyy').format(p.paidOn)}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showReceiptDialog(
                        context,
                        text: receiptText(
                          instituteName: settings.name,
                          studentName: d.name,
                          payment: p,
                          account: account,
                          currency: cur,
                        ),
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
