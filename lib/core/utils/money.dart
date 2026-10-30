// lib/core/utils/money.dart
import 'package:intl/intl.dart';

/// Formats an amount with Indian digit grouping (₹1,25,000). Whole amounts
/// are shown without paise.
String formatMoney(double amount, String symbol) {
  final whole = amount == amount.roundToDouble();
  return NumberFormat.currency(locale: 'en_IN', symbol: symbol, decimalDigits: whole ? 0 : 2)
      .format(amount);
}
