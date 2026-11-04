import 'package:campus_track/core/attendance/ble_token.dart';
import 'package:flutter_test/flutter_test.dart';

// Vectors generated with firebase_functions/checkin.js buildBleToken, so the
// app and the server agree byte for byte.
void main() {
  test('matches the server encoding', () {
    expect(
      BleToken.build(secret: 'test-secret-0123456789abcdef', sessionId: 'sessABC', bleCode: 0xDEADBEEF, step: 42),
      'ba7cdead-beef-002a-869d-44095e3709e4',
    );
    expect(
      BleToken.build(secret: 'k', sessionId: 's', bleCode: 1, step: 65535),
      'ba7c0000-0001-ffff-98e5-0e7008c1ec6b',
    );
  });

  test('step wraps at 16 bits like the server', () {
    final a = BleToken.build(secret: 'k', sessionId: 's', bleCode: 1, step: 65536);
    expect(a.substring(14, 18), '0000'.substring(0, 4));
  });

  test('recognises only Batchwise tokens', () {
    expect(BleToken.looksLikeToken('BA7CDEAD-BEEF-002A-869D-44095E3709E4'), isTrue);
    expect(BleToken.looksLikeToken('0000180f-0000-1000-8000-00805f9b34fb'), isFalse);
    expect(BleToken.looksLikeToken('ba7c'), isFalse);
  });
}
