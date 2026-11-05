// lib/core/utils/login_id.dart
import 'phone.dart';

/// Students without an email sign in with their mobile number. Firebase Auth
/// needs an email, so a phone login maps to an internal address on this
/// domain. Must match PHONE_LOGIN_DOMAIN in firebase_functions/index.js.
class LoginId {
  static const phoneDomain = 'students.batchwise.app';

  /// "9876543210" -> "9876543210@students.batchwise.app"; emails pass through.
  static String toEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('@')) return trimmed.toLowerCase();
    final phone = PhoneNumber.normalize(trimmed);
    if (phone == null) return trimmed;
    return '${phone.substring(phone.length - 10)}@$phoneDomain';
  }

  static bool isPhoneLogin(String? email) => email != null && email.endsWith('@$phoneDomain');

  /// What to show users as their login: the mobile number for phone logins.
  static String display(String? email) =>
      isPhoneLogin(email) ? email!.split('@').first : (email ?? '');
}
