// lib/features/fees/upi_pay.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/money.dart';
import '../../core/utils/upi.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';

/// "Pay ₹X" (opens a UPI app) next to a QR button (to pay from another phone).
class UpiPayBar extends StatelessWidget {
  final UpiPayment payment;
  final String currency;

  const UpiPayBar({super.key, required this.payment, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = payment.amount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
              onPressed: () => openUpiApp(context, payment, currency),
              icon: const Icon(Icons.arrow_outward_rounded, size: 20),
              label: Text(amount == null ? 'Pay by UPI' : 'Pay ${formatMoney(amount, currency)}'),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.outlined(
            tooltip: 'QR code',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              side: BorderSide(color: p.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => showUpiQrSheet(context, payment, currency),
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
        ],
      ),
    );
  }
}

/// Opens the phone's UPI app, or shows the QR where there isn't one (web,
/// desktop, or no UPI app installed).
Future<void> openUpiApp(BuildContext context, UpiPayment payment, String currency) async {
  if (!kIsWeb) {
    try {
      if (await launchUrl(payment.intentUri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // No app handles upi:// — fall through to the QR.
    }
  }
  if (context.mounted) await showUpiQrSheet(context, payment, currency);
}

Future<void> showUpiQrSheet(BuildContext context, UpiPayment payment, String currency) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final p = ctx.palette;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                payment.amount == null ? 'Scan to pay' : formatMoney(payment.amount!, currency),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8),
              ),
              const SizedBox(height: 4),
              Text(payment.payeeName, style: TextStyle(color: p.inkMuted)),
              const SizedBox(height: 20),
              // Always dark on white: scanners struggle with inverted codes.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(
                  data: payment.intentUri.toString(),
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              Text('Scan with any UPI app', style: TextStyle(color: p.inkMuted, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: payment.upiId));
                  showMessage(ctx, 'UPI ID copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(payment.upiId),
              ),
              if (payment.note.isNotEmpty)
                Text('Note: ${payment.note}', style: TextStyle(color: p.inkFaint, fontSize: 12)),
            ],
          ),
        ),
      );
    },
  );
}
