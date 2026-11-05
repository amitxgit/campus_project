// lib/core/attendance/ble_token.dart
//
// The Bluetooth check-in token: 16 bytes carried as one 128-bit service UUID,
// because that is all iOS lets an app broadcast.
//
//   bytes 0-1   magic 0xBA 0x7C   (marks the UUID as a Batchwise check-in)
//   bytes 2-5   bleCode            (random u32 per session, big-endian)
//   bytes 6-7   step               (u16, same 5 s step as the QR)
//   bytes 8-15  HMAC-SHA256(secret, "ble:<sessionId>:<step>"), first 8 bytes
//
// Must match firebase_functions/checkin.js, which verifies it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class BleToken {
  BleToken._();

  static const int magic0 = 0xBA;
  static const int magic1 = 0x7C;

  /// Lower-case UUID string, e.g. "ba7c1234-5678-...".
  static String build({
    required String secret,
    required String sessionId,
    required int bleCode,
    required int step,
  }) {
    final b = Uint8List(16);
    b[0] = magic0;
    b[1] = magic1;
    final view = ByteData.sublistView(b);
    view.setUint32(2, bleCode & 0xFFFFFFFF);
    view.setUint16(6, step & 0xFFFF);
    final mac = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('ble:$sessionId:$step'))
        .bytes;
    b.setRange(8, 16, mac);
    return _uuid(b);
  }

  /// Whether a 128-bit UUID string looks like one of our tokens. The server
  /// does the real check.
  static bool looksLikeToken(String uuid) {
    final hex = uuid.replaceAll('-', '').toLowerCase();
    return hex.length == 32 && hex.startsWith('ba7c');
  }

  static String _uuid(Uint8List b) {
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
