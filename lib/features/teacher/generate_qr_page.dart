// lib/features/teacher/generate_qr_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:secure_application/secure_application.dart';
import 'package:crypto/crypto.dart';

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
          _loading = false;
        });
        _startTimers();
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

    _qrData = jsonEncode({
      'sId': _session!.id,
      'n': step,
      'sig': signature.substring(0, 32),
    });
  }

  Future<void> _finishAndReview() async {
    if (_session == null) return;
    _timer?.cancel();
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
                  // White in both themes: scanners need the contrast.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    child: QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 260,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Students scan this in the app. The code changes every few seconds, so a photo of it won\'t work later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.palette.inkMuted, height: 1.45),
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
