// lib/core/attendance/device_id.dart
//
// A random ID for this installation of the app, sent with every check-in.
// The server keeps only its hash, and links a student account to the first
// phone it checks in from (see firebase_functions/checkin.js).
//
// It stays the same across sign-out and sign-in, so it is not cleared by
// LocalStorage.clearSession. Reinstalling the app or clearing its data makes a
// new one, and the institute then resets the student's phone link.
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceId {
  DeviceId._();

  static const _key = 'checkin_device_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.length < 16) {
      final rnd = Random.secure();
      id = base64UrlEncode(List<int>.generate(24, (_) => rnd.nextInt(256)));
      await prefs.setString(_key, id);
    }
    return _cached = id;
  }
}
