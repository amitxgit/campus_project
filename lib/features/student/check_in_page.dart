// lib/features/student/check_in_page.dart
//
// Bluetooth check-in: listens for the rotating token broadcast by the
// teacher's phone (ble_token.dart) and sends it to markAttendance. The server
// checks it exactly like a QR scan, plus phone binding. Falls back to the QR
// scanner when Bluetooth isn't available.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/attendance/ble_token.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../../theme.dart';

enum _Stage { searching, sending, done, failed }

class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({super.key});

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  static const _searchFor = Duration(seconds: 20);
  // Ignore very faint signals (other rooms, corridors).
  static const _minRssi = -92;

  _Stage _stage = _Stage.searching;
  String _message = '';
  bool _alreadyMarked = false;
  StreamSubscription<List<ScanResult>>? _sub;
  Timer? _giveUp;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _stage = _Stage.failed;
      _message = 'Bluetooth check-in works in the phone app. Scan the QR code instead.';
    } else {
      _search();
    }
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _stopScan() async {
    _giveUp?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void _fail(String message) {
    _stopScan();
    if (mounted) {
      setState(() {
        _stage = _Stage.failed;
        _message = message;
      });
    }
  }

  Future<void> _search() async {
    setState(() {
      _stage = _Stage.searching;
      _message = '';
    });
    try {
      if (!await FlutterBluePlus.isSupported) {
        return _fail('This phone doesn\'t support Bluetooth check-in. Scan the QR code instead.');
      }
      if (defaultTargetPlatform == TargetPlatform.android &&
          FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => FlutterBluePlus.adapterStateNow);
      if (state == BluetoothAdapterState.unauthorized) {
        return _fail('Allow Bluetooth (Nearby devices) for Batchwise in Settings, then try again.');
      }
      if (state != BluetoothAdapterState.on) {
        return _fail('Turn on Bluetooth, then try again.');
      }

      _sub = FlutterBluePlus.onScanResults.listen(_onResults);
      _giveUp = Timer(_searchFor, () => _fail(
          'Couldn\'t find your teacher\'s phone. Move closer and try again, or scan the QR code.'));
      await FlutterBluePlus.startScan(
        timeout: _searchFor,
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      debugPrint('CheckIn scan: $e');
      _fail('Bluetooth isn\'t available right now. Scan the QR code instead.');
    }
  }

  void _onResults(List<ScanResult> results) {
    if (_stage != _Stage.searching) return;
    ScanResult? best;
    String? token;
    for (final r in results) {
      if (r.rssi < _minRssi) continue;
      for (final uuid in r.advertisementData.serviceUuids) {
        final s = uuid.str128;
        if (!BleToken.looksLikeToken(s)) continue;
        // Most recent broadcast wins: tokens rotate every few seconds.
        if (best == null || r.timeStamp.isAfter(best.timeStamp)) {
          best = r;
          token = s;
        }
      }
    }
    if (token != null) _send(token);
  }

  Future<void> _send(String token) async {
    setState(() => _stage = _Stage.sending);
    await _stopScan();
    try {
      final already = await ref.read(attendanceRepoProvider).markPresentFromBle(token);
      if (mounted) {
        setState(() {
          _alreadyMarked = already;
          _stage = _Stage.done;
        });
      }
    } catch (e) {
      _fail(FirebaseErrorParser.getMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color color, String title, String body) = switch (_stage) {
      _Stage.searching => (
          Icons.bluetooth_searching_rounded, p.accent, 'Looking for your teacher\'s phone',
          'Stay in the classroom with this screen open. It takes a few seconds.'),
      _Stage.sending => (Icons.bluetooth_connected_rounded, p.accent, 'Checking you in…', ''),
      _Stage.done => (
          Icons.check_circle_rounded, p.success, _alreadyMarked ? 'Already checked in' : 'You\'re checked in',
          'Your attendance has been verified and recorded.'),
      _Stage.failed => (Icons.error_outline_rounded, p.danger, 'Check-in didn\'t work', _message),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Check in')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: _stage == _Stage.searching || _stage == _Stage.sending
                    ? Stack(alignment: Alignment.center, children: [
                        SizedBox(width: 150, height: 150, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
                        Icon(icon, size: 72, color: color),
                      ])
                    : Icon(icon, size: 72, color: color),
              ),
              const SizedBox(height: 28),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.inkMuted, height: 1.45)),
              const Spacer(),
              if (_stage == _Stage.done)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
                )
              else ...[
                if (_stage == _Stage.failed && !kIsWeb)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _search, child: const Text('Try again')),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _stage == _Stage.sending
                        ? null
                        : () async {
                            await _stopScan();
                            if (context.mounted) context.pushReplacement('/student/scan-qr');
                          },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan QR instead'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
