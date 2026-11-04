// lib/features/teacher/generate_qr_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:secure_application/secure_application.dart';
import 'package:crypto/crypto.dart';

import '../../core/attendance/ble_broadcaster.dart';
import '../../core/attendance/ble_token.dart';
import '../../core/models/attendance_session.dart';
import '../../main.dart';
import '../common/widgets/async_error_widget.dart';
import '../../theme.dart';
import '../../core/utils/firebase_error_parser.dart';

class GenerateQRPage extends ConsumerStatefulWidget {
  final String entryId;

  const GenerateQRPage({
    super.key,
    required this.entryId,
  });

  @override
  ConsumerState<GenerateQRPage> createState() => _GenerateQRPageState();
}

class _GenerateQRPageState extends ConsumerState<GenerateQRPage> {
  // Must match QR_STEP_MS in firebase_functions/index.js
  static const _qrStep = Duration(seconds: 5);

  AttendanceSession? _session;
  String? _secret;
  int? _bleCode;

  // Bluetooth check-in runs alongside the QR. "Bluetooth only" hides the QR
  // and tells the server to refuse QR scans for this session.
  final BleBroadcaster _ble = BleBroadcaster();
  bool _bleOn = false;
  String? _bleProblem;
  bool _bluetoothOnly = false;
  bool _savingMode = false;
  final Stopwatch _sinceStart = Stopwatch();
  Object? _error;
  bool _loading = true;

  Timer? _timer;
  int _secondsElapsed = 0;
  String _qrData = '';

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ble.stop();
    super.dispose();
  }

  Future<void> _initSession() async {
    try {
      final authRepo = ref.read(authRepoProvider);
      final attRepo = ref.read(attendanceRepoProvider);
      final ttRepo = ref.read(timetableRepoProvider);

      final me = await authRepo.currentUser();
      if (me == null) throw Exception('Not logged in');

      final entry = await ttRepo.entryById(widget.entryId);
      if (entry == null) throw Exception('Timetable entry not found');

      final started = await attRepo.startSession(widget.entryId);
      _sinceStart
        ..reset()
        ..start();
      final now = DateTime.now();

      final newSession = AttendanceSession(
        id: started.sessionId,
        teacherId: me.id,
        subjectId: entry.subjectId,
        section: entry.section,
        slot: entry.slot,
        createdAt: now,
        isActive: true,
      );

      if (mounted) {
        setState(() {
          _session = newSession;
          _secret = started.secret;
          _bleCode = started.bleCode;
          _loading = false;
        });
        _startTimers();
        _startBluetooth();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _startTimers() {
    _generateDynamicQrData();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsElapsed++;
        // Rotate QR code data to prevent static screenshot sharing
        if (_secondsElapsed % _qrStep.inSeconds == 0) {
          _generateDynamicQrData();
        }
      });
    });
  }

  void _generateDynamicQrData() {
    if (_session == null || _secret == null) return;

    // Sign a step counter rather than a wall-clock timestamp, so a wrong clock
    // on the teacher's phone doesn't invalidate codes. The server derives the
    // expected step from the session's createdAt and checks the HMAC.
    final step = _sinceStart.elapsedMilliseconds ~/ _qrStep.inMilliseconds;
    final hmac = Hmac(sha256, utf8.encode(_secret!));
    final signature = hmac.convert(utf8.encode('${_session!.id}:$step')).toString();

    if (_bleOn) _broadcastStep(step);

    _qrData = jsonEncode({
      'sId': _session!.id,
      'n': step,
      'sig': signature.substring(0, 32),
    });
  }

  int get _currentStep => _sinceStart.elapsedMilliseconds ~/ _qrStep.inMilliseconds;

  Future<void> _startBluetooth() async {
    final problem = await _ble.prepare();
    if (!mounted) return;
    if (problem != null) {
      setState(() => _bleProblem = problem);
      return;
    }
    final ok = await _broadcastStep(_currentStep);
    if (!mounted) return;
    setState(() {
      _bleOn = ok;
      _bleProblem = ok ? null : 'Bluetooth broadcast didn\'t start. Students can scan the QR.';
    });
  }

  Future<bool> _broadcastStep(int step) {
    return _ble.broadcast(BleToken.build(
      secret: _secret!,
      sessionId: _session!.id,
      bleCode: _bleCode!,
      step: step,
    ));
  }

  Future<void> _setBluetoothOnly(bool value) async {
    if (_session == null || _savingMode) return;
    setState(() => _savingMode = true);
    try {
      await ref.read(attendanceRepoProvider).setQrEnabled(_session!.id, !value);
      if (mounted) setState(() => _bluetoothOnly = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _savingMode = false);
    }
  }

  Future<void> _finishAndReview() async {
    if (_session == null) return;
    _timer?.cancel();
    await _ble.stop();
    try {
      await ref.read(attendanceRepoProvider).endSession(_session!.id);
    } catch (_) {
      // The server also stops accepting scans once the session is old enough.
    }
    if (!mounted) return;
    context.pushReplacement('/teacher/review-attendance/${_session!.id}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Attendance')),
        body: AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(_error!),
          onRetry: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _initSession();
          },
        ),
      );
    }

    return SecureApplication(
      nativeRemoveDelay: 100,
      onNeedUnlock: (secureNotifier) async {
        return null;
      },
      child: SecureGate(
        blurr: 60,
        opacity: 0.8,
        lockedBuilder: (context, secureNotifier) =>
        const Center(child: CircularProgressIndicator()),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Attendance'),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  const _LivePill(),
                  const SizedBox(height: 12),
                  Text(
                    _formatTime(_secondsElapsed),
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  if (_bluetoothOnly)
                    _BluetoothOnlyPanel(palette: context.palette)
                  else
                    // White in both themes: scanners need the contrast.
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                      child: QrImageView(
                        data: _qrData,
                        version: QrVersions.auto,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _bluetoothOnly
                        ? 'Students tap "Check in" in the app near you. It only works close to this phone, so it can\'t be shared.'
                        : _bleOn
                            ? 'Students tap "Check in" near you, or scan this code. The code changes every few seconds.'
                            : 'Students scan this in the app. The code changes every few seconds, so a photo of it won\'t work later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.palette.inkMuted, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  _BluetoothStatus(
                    on: _bleOn,
                    problem: _bleProblem,
                    bluetoothOnly: _bluetoothOnly,
                    saving: _savingMode,
                    onBluetoothOnly: _setBluetoothOnly,
                    onRetry: _startBluetooth,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _finishAndReview, child: const Text('Finish and review')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
/// "● Live" with a gently pulsing dot.
class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 8),
        Text('Live', style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Shown instead of the QR in "Bluetooth only" mode.
class _BluetoothOnlyPanel extends StatelessWidget {
  final Palette palette;
  const _BluetoothOnlyPanel({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 276,
      height: 276,
      decoration: BoxDecoration(color: palette.accentSoft, borderRadius: BorderRadius.circular(24)),
      child: Icon(Icons.bluetooth_searching_rounded, size: 96, color: palette.accent),
    );
  }
}

/// Bluetooth state, the "Bluetooth only" switch, and what to do if it's off.
class _BluetoothStatus extends StatelessWidget {
  final bool on;
  final String? problem;
  final bool bluetoothOnly;
  final bool saving;
  final ValueChanged<bool> onBluetoothOnly;
  final VoidCallback onRetry;

  const _BluetoothStatus({
    required this.on,
    required this.problem,
    required this.bluetoothOnly,
    required this.saving,
    required this.onBluetoothOnly,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!on) {
      if (problem == null) {
        return Text('Starting Bluetooth…', style: TextStyle(color: p.inkFaint));
      }
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bluetooth_disabled_rounded, size: 18, color: p.inkFaint),
        const SizedBox(width: 6),
        Flexible(child: Text(problem!, style: TextStyle(color: p.inkMuted))),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]);
    }
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        value: bluetoothOnly,
        onChanged: saving ? null : onBluetoothOnly,
        secondary: Icon(Icons.bluetooth_rounded, color: p.accent),
        title: const Text('Bluetooth only'),
        subtitle: const Text('Hide the QR so only students in the room can check in. Keep this screen open.'),
      ),
    );
  }
}
