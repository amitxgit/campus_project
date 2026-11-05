// lib/core/utils/firebase_error_parser.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class FirebaseErrorParser {
  /// Translates a Firebase error or general error into a user-friendly message.
  static String getMessage(Object e) {
    // Handle Firebase Authentication errors
    if (e is FirebaseAuthException) {
      return _authError(e);
    }

    // Cloud Functions errors carry a message written for the user by the server
    if (e is FirebaseFunctionsException) {
      return e.message ?? 'Server error. Please try again.';
    }

    // Handle Firestore & general Firebase errors
    if (e is FirebaseException) {
      return _firestoreError(e);
    }

    // Clean generic Dart exceptions
    final rawMessage = e.toString();
    if (rawMessage.contains('Exception:') ||
        rawMessage.contains('FirebaseException:') ||
        rawMessage.contains('FirebaseAuthException:')) {
      return _clean(rawMessage);
    }

    // Fallback generic error message
    return 'An unexpected error occurred. Please try again.';
  }

  // Auth error messages with security-best-practice generic messages
  static String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Invalid email or password. Please try again.';

      case 'email-already-in-use':
        return 'An account with this email address already exists.';

      case 'weak-password':
        return 'The password is too weak. Please use at least 6 characters.';

      case 'user-disabled':
        return 'This account has been disabled by an administrator.';

      case 'operation-not-allowed':
        return 'Email/Password login is not enabled. Please contact support.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'invalid-verification-code':
        return 'Invalid OTP code. Please try again.';

      case 'invalid-verification-id':
      case 'session-expired':
        return 'OTP session expired. Please request a new code.';

      default:
        return e.message ?? 'An unexpected authentication error occurred.';
    }
  }

  // Firestore error messages for common error codes
  static String _firestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action.';

      case 'unavailable':
        return 'Service temporarily unavailable. Please try again later.';

      case 'not-found':
        return 'Requested data was not found.';

      case 'already-exists':
        return 'This record already exists.';

      case 'deadline-exceeded':
        return 'The server took too long to respond. Please retry.';

      default:
        return 'A server error occurred. Please try again.';
    }
  }

  // Removes technical prefixes from generic error messages
  static String _clean(String raw) {
    return raw
        .replaceAll('Exception:', '')
        .replaceAll('FirebaseException:', '')
        .replaceAll('FirebaseAuthException:', '')
        .trim();
  }
}
