// lib/core/utils/upi.dart
//
// UPI "intent" links (upi://pay?...) open any UPI app (GPay, PhonePe, Paytm,
// BHIM) with the payee, amount and note filled in. WhatsApp doesn't make
// upi:// links tappable, so messages carry an https link to web/pay.html,
// which shows a button that opens the same upi:// link.

/// Where web/pay.html is served. Defaults to the Firebase Hosting site of
/// the project; override with --dart-define=PAY_PAGE_BASE=https://... if the
/// web app is hosted elsewhere.
const String kPayPageBase = String.fromEnvironment(
  'PAY_PAGE_BASE',
  defaultValue: 'https://batchwise-2bd30.web.app',
);

class UpiPayment {
  /// The payee's virtual payment address, e.g. apexclasses@okhdfcbank.
  final String upiId;
  final String payeeName;

  /// Rupees. Null lets the payer type the amount.
  final double? amount;

  /// Shows up in the institute's bank statement / UPI app history.
  final String note;

  const UpiPayment({required this.upiId, required this.payeeName, this.amount, this.note = ''});

  // Banks reject long notes; 50 characters is safe for every app we tried.
  static const maxNoteLength = 50;

  static final _upiIdPattern = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9]{1,64}$');

  static bool isValidUpiId(String? id) => id != null && _upiIdPattern.hasMatch(id.trim());

  /// "Fees Riya Sharma 12", trimmed to a length every UPI app accepts.
  static String feeNote(String studentName, [String? roll]) {
    final parts = ['Fees', studentName.trim(), if (roll != null && roll.trim().isNotEmpty) roll.trim()];
    final note = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
    return note.length <= maxNoteLength ? note : note.substring(0, maxNoteLength).trimRight();
  }

  /// "1500.00": UPI apps expect two decimals and no grouping.
  static String formatAmount(double amount) => amount.toStringAsFixed(2);

  Map<String, String> get _params => {
        'pa': upiId.trim(),
        'pn': payeeName.trim(),
        if (amount != null && amount! > 0) 'am': formatAmount(amount!),
        'cu': 'INR',
        if (note.trim().isNotEmpty) 'tn': note.trim(),
      };

  // Spaces as %20, not '+' (some UPI apps show a literal '+'), and a plain
  // '@' in the UPI ID as in NPCI's examples (some apps reject '%40').
  String get _query => _params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value).replaceAll('%40', '@')}')
      .join('&');

  /// Opens a UPI app directly. Use in the app and in QR codes.
  Uri get intentUri => Uri.parse('upi://pay?$_query');

  /// An https link to the pay page, safe to put in WhatsApp/SMS.
  Uri payPageUri([String base = kPayPageBase]) {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$trimmed/pay.html?$_query');
  }
}
