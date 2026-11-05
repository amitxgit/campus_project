// lib/core/utils/phone.dart

class PhoneNumber {
  /// Normalises a mobile number to international digits without '+', as
  /// WhatsApp expects (e.g. "98765 43210" -> "919876543210"). Bare 10-digit
  /// numbers are treated as Indian. Returns null if it can't be a mobile number.
  static String? normalize(String? input, {String defaultCountryCode = '91'}) {
    if (input == null) return null;
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 10) digits = '$defaultCountryCode$digits';
    if (digits.length < 11 || digits.length > 15) return null;
    return digits;
  }
}
