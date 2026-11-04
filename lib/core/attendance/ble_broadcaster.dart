// lib/core/attendance/ble_broadcaster.dart
//
// Broadcasts the rotating check-in token from the teacher's phone (see
// ble_token.dart). On iOS the broadcast only runs while the app is open on
// screen, so the attendance page asks teachers to keep it open.
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

class BleBroadcaster {
  final FlutterBlePeripheral _p = FlutterBlePeripheral();
  bool _running = false;

  /// Asks for permission and checks the radio. Returns null when ready, or a
  /// short reason the teacher can act on.
  Future<String?> prepare() async {
    if (kIsWeb) return 'Bluetooth check-in needs the phone app.';
    try {
      if (!await _p.isSupported) return 'This phone can\'t broadcast over Bluetooth.';
      var state = await _p.hasPermission();
      if (state != PeripheralBluetoothState.granted && state != PeripheralBluetoothState.ready) {
        state = await _p.requestPermission();
      }
      if (state == PeripheralBluetoothState.turnedOff && defaultTargetPlatform == TargetPlatform.android) {
        await _p.enableBluetooth();
        state = await _p.hasPermission();
      }
      switch (state) {
        case PeripheralBluetoothState.granted:
        case PeripheralBluetoothState.ready:
          return null;
        case PeripheralBluetoothState.turnedOff:
          return 'Turn on Bluetooth to let students check in.';
        case PeripheralBluetoothState.unsupported:
          return 'This phone can\'t broadcast over Bluetooth.';
        default:
          return 'Allow Bluetooth (Nearby devices) for Batchwise in Settings.';
      }
    } catch (e) {
      debugPrint('BleBroadcaster.prepare: $e');
      return 'Bluetooth isn\'t available right now.';
    }
  }

  /// Starts or replaces the broadcast with [uuid]. Returns false on failure.
  Future<bool> broadcast(String uuid) async {
    try {
      if (_running) await _p.stop();
      final state = await _p.start(
        advertiseData: AdvertiseDataCore(serviceUuid: uuid),
        androidSettings: const AndroidAdvertiseSettings(
          advertiseSettings: AdvertiseSettings(
            advertiseMode: AdvertiseMode.advertiseModeLowLatency,
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
            connectable: false,
            timeout: 0,
          ),
        ),
      );
      _running = true;
      // On iOS a radio that is still coming up queues the broadcast.
      return state == PeripheralBluetoothState.ready || state == PeripheralBluetoothState.granted;
    } catch (e) {
      debugPrint('BleBroadcaster.broadcast: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _p.stop();
    } catch (_) {}
  }
}
