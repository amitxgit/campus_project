// lib/features/teacher/review_attendance_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/attendance.dart';
import '../../core/models/attendance_session.dart';
import '../../main.dart';

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

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(reviewProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Save Attendance'),
        actions: [
          // QR scans and fingerprint / face punches arrive while the class runs.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(reviewProvider(widget.sessionId)),
          ),
          TextButton(
            onPressed: () =>
            asyncData.hasValue ? _save(asyncData.value!) : null,
            child: const Text(
              'SAVE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.refresh(reviewProvider(widget.sessionId)),
        ),
        data: (data) {
          final students = data['students'] as List;
          final initialMap = data['initialStatus'] as Map<String, AttendanceStatus>;
          final subjectName = data['subjectName'] as String;

          int presentCount = 0;
          for (final s in students) {
            final status = _overrides[s.id] ?? initialMap[s.id]!;
            if (status == AttendanceStatus.present ||
                status == AttendanceStatus.late) {
              presentCount++;
            }
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        subjectName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text('$presentCount / ${students.length} Present'),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = students[index];
                    // Display override if exists, otherwise display permanent status
                    final status = _overrides[student.id] ?? initialMap[student.id]!;

                    return ListTile(
                      title: Text(student.name),
                      subtitle: Text(student.collegeRollNo ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusBtn(
                            label: 'P',
                            color: Colors.green,
                            selected: status == AttendanceStatus.present,
                            onTap: () =>
                                _set(student.id, AttendanceStatus.present),
                          ),
                          const SizedBox(width: 4),
                          _StatusBtn(
                            label: 'A',
                            color: Colors.red,
                            selected: status == AttendanceStatus.absent,
                            onTap: () =>
                                _set(student.id, AttendanceStatus.absent),
                          ),
                          const SizedBox(width: 4),
                          _StatusBtn(
                            label: 'L',
                            color: Colors.orange,
                            selected: status == AttendanceStatus.late,
                            onTap: () =>
                                _set(student.id, AttendanceStatus.late),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved successfully')),
      );

      // Navigate back to teacher home
      context.go('/home/teacher');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }
}

// -----------------------------------------------------------------------------
// STATUS BUTTON
// -----------------------------------------------------------------------------

class _StatusBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusBtn({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(color: selected ? color : Colors.grey),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}