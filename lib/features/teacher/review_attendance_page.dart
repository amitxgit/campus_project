// lib/features/teacher/review_attendance_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/attendance_toggle.dart';
import '../../core/models/attendance.dart';
import '../../core/models/attendance_session.dart';
import 'package:intl/intl.dart';

import '../../core/models/parent_alert.dart';
import '../../core/models/user.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../parent_alerts/parent_messenger.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

final reviewProvider =
FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
      (ref, sessionId) async {
    final authRepo = ref.watch(authRepoProvider);
    final attRepo = ref.watch(attendanceRepoProvider);
    final ttRepo = ref.watch(timetableRepoProvider);

    // 1. Get Session Data
    final sessionDoc = await attRepo.sessionsRef.doc(sessionId).get();
    if (!sessionDoc.exists) {
      throw Exception('Attendance session not found');
    }
    final session = sessionDoc.data()!;

    // 2. Get Metadata
    final subject = await ttRepo.subjectById(session.subjectId);
    final students = await authRepo.studentsInSection(session.section);

    // 3. Get Permanent Records (Created by QR Code or Finalize Step)
    final existingRecords = await attRepo.getRecordsForSession(sessionId);

    // Maps for easy lookup
    final Map<String, AttendanceStatus> initialStatus = {};
    final Map<String, String> recordIds = {}; // <-- BUG FIX: Capture actual Document IDs

    // Default all to absent if no record found (safety fallback)
    for (final s in students) {
      initialStatus[s.id] = AttendanceStatus.absent;
    }

    // Overwrite with actual permanent statuses AND capture their exact document IDs
    for (final r in existingRecords) {
      initialStatus[r.studentId] = r.status;
      recordIds[r.studentId] = r.id; // Map the exact Firestore document ID!
    }

    return {
      'session': session,
      'subjectName': subject?.name ?? 'Unknown Subject',
      'students': students,
      'initialStatus': initialStatus,
      'recordIds': recordIds, // <-- Pass IDs to UI
    };
  },
);

// -----------------------------------------------------------------------------
// PAGE
// -----------------------------------------------------------------------------

class ReviewAttendancePage extends ConsumerStatefulWidget {
  final String sessionId;

  const ReviewAttendancePage({
    super.key,
    required this.sessionId,
  });

  @override
  ConsumerState<ReviewAttendancePage> createState() =>
      _ReviewAttendancePageState();
}

class _ReviewAttendancePageState extends ConsumerState<ReviewAttendancePage> {
  // Local overrides for manual edits
  final Map<String, AttendanceStatus> _overrides = {};

  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(reviewProvider(widget.sessionId));
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review attendance'),
        actions: [
          // QR scans and fingerprint / face punches keep arriving while the class runs.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(reviewProvider(widget.sessionId)),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      bottomNavigationBar: asyncData.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(asyncData.value!),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save attendance'),
                ),
              ),
            )
          : null,
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.refresh(reviewProvider(widget.sessionId)),
        ),
        data: (data) {
          final students = data['students'] as List;
          final initialMap = data['initialStatus'] as Map<String, AttendanceStatus>;
          final subjectName = data['subjectName'] as String;

          int presentCount = 0;
          for (final s in students) {
            final status = _overrides[s.id] ?? initialMap[s.id]!;
            if (status == AttendanceStatus.present || status == AttendanceStatus.late) presentCount++;
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: students.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subjectName, style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                          text: '$presentCount',
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.4),
                        ),
                        TextSpan(text: ' of ${students.length} present', style: TextStyle(fontSize: 15, color: p.inkMuted)),
                      ])),
                      const SizedBox(height: 10),
                      ProgressLine(value: students.isEmpty ? 0 : presentCount / students.length),
                    ],
                  ),
                );
              }
              final student = students[index - 1];
              final status = _overrides[student.id] ?? initialMap[student.id]!;
              final roll = (student.collegeRollNo ?? '') as String;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          if (roll.isNotEmpty) Text(roll, style: TextStyle(fontSize: 13, color: p.inkMuted)),
                        ],
                      ),
                    ),
                    AttendanceToggle(
                      value: status,
                      onChanged: (v) => _set(student.id as String, v),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _set(String id, AttendanceStatus status) {
    setState(() => _overrides[id] = status);
  }

  // ---------------------------------------------------------------------------
  // SAVE (Updates existing records strictly)
  // ---------------------------------------------------------------------------

  Future<void> _save(Map<String, dynamic> data) async {
    setState(() => _saving = true);
    try {
      final session = data['session'] as AttendanceSession;
      final initialMap = data['initialStatus'] as Map<String, AttendanceStatus>;
      final recordIds = data['recordIds'] as Map<String, String>; // Existing IDs
      final students = data['students'] as List;

      // Access DB directly via batch for atomicity in this view
      final batch = FirebaseFirestore.instance.batch();
      final attRef = FirebaseFirestore.instance.collection('attendance');

      // Iterate through all students to save changes
      for (final s in students) {
        final currentStatus = _overrides[s.id] ?? initialMap[s.id]!;

        // 🔴 BUG FIX: Use the EXACT existing document ID to prevent duplicates!
        // If a record doesn't exist yet, gracefully fall back to the sessionId format.
        final docId = recordIds[s.id] ?? '${widget.sessionId}_${s.id}';

        final record = AttendanceRecord(
          id: docId,
          sessionId: widget.sessionId,
          studentId: s.id,
          subjectId: session.subjectId,
          date: session.createdAt,
          slot: session.slot,
          status: currentStatus,
          markedByTeacherId: session.teacherId,
          markedAt: DateTime.now(),
        );

        batch.set(attRef.doc(docId), record.toMap(), SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;

      showMessage(context, 'Attendance saved.', success: true);

      // Offer to tell parents of absentees, unless the server already does it.
      final settings = ref.read(settingsProvider);
      final absentees = students
          .cast<UserAccount>()
          .where((s) => (_overrides[s.id] ?? initialMap[s.id]) == AttendanceStatus.absent)
          .toList();
      final automatic = settings.whatsappConnected && settings.autoAbsenceAlerts;
      if (absentees.isNotEmpty && settings.parentAlertsEnabled && !automatic) {
        final notify = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${absentees.length} absent'),
            content: const Text('Send a WhatsApp message to their parents?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Notify parents')),
            ],
          ),
        );
        if (notify == true && mounted) {
          final day = DateFormat('d MMM yyyy').format(session.createdAt);
          await ParentMessenger.send(context, ref, kind: ParentAlertKind.absence, messages: [
            for (final s in absentees) ParentMessage(s, [s.name, day, settings.name]),
          ]);
        }
        if (!mounted) return;
      }

      // Navigate back to teacher home
      context.go('/home/teacher');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    }
  }
}
