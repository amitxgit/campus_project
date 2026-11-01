// lib/features/fees/my_fees_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fee.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/ui_kit.dart';
import 'fee_messages.dart';
import 'fee_widgets.dart';
import 'upi_pay.dart';

final myFeesProvider = FutureProvider.autoDispose<({FeeAccount? account, List<FeePayment> payments, String name, String? roll})>((ref) async {
  final me = await ref.watch(authRepoProvider).currentUser();
  if (me == null) throw Exception('Not logged in');
  final repo = ref.watch(feeRepoProvider);
  final account = await repo.account(me.id);
  final payments = account == null ? <FeePayment>[] : await repo.payments(me.id);
  return (account: account, payments: payments, name: me.name, roll: me.collegeRollNo);
});

class MyFeesPage extends ConsumerWidget {
  const MyFeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myFeesProvider);
    final settings = ref.watch(settingsProvider);
    final cur = settings.currencySymbol;
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Fees')),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(myFeesProvider)),
        data: (d) {
          final account = d.account;
          if (account == null) {
            return const Center(
              child: EmptyNote(icon: Icons.receipt_long_outlined, text: 'Your fee details will appear here once the office adds them.'),
            );
          }
          final receipts = d.payments.where((x) => !x.voided).toList();
          final due = account.payableNow();
          final upi = due > 0.5 ? upiPaymentFor(settings, studentName: d.name, roll: d.roll, amount: due) : null;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myFeesProvider),
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
                FeeHero(
                  account: account,
                  currency: cur,
                  footnote: account.isFullyPaid
                      ? null
                      : upi != null
                          ? 'Once the office confirms your UPI payment, the receipt appears here.'
                          : 'Pay at the office and you will get a receipt here.',
                ),
                if (upi != null) UpiPayBar(payment: upi, currency: cur),
                const SectionLabel('Instalments'),
                InstalmentList(account: account, currency: cur),
                const SectionLabel('Receipts', padding: EdgeInsets.fromLTRB(20, 32, 20, 4)),
                if (receipts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('No payments yet.', style: TextStyle(color: p.inkMuted)),
                  ),
                for (final pay in receipts)
                  PaymentRow(
                    payment: pay,
                    currency: cur,
                    onTap: () => showReceiptDialog(
                      context,
                      text: receiptText(
                        instituteName: settings.name,
                        studentName: d.name,
                        payment: pay,
                        account: account,
                        currency: cur,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
