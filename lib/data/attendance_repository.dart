// lib/data/attendance_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/attendance.dart';
import '../core/models/attendance_session.dart';
import '../core/utils/firebase_error_parser.dart';

class AttendanceRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // COLLECTION REFERENCES
  // ---------------------------------------------------------------------------
  CollectionReference<AttendanceSession> get sessionsRef =>
      _db.collection('attendance_sessions').withConverter<AttendanceSession>(
        fromFirestore: (snap, _) => AttendanceSession.fromMap(snap.id, snap.data()!),
        toFirestore: (session, _) => session.toMap(),
      );

  CollectionReference<AttendanceRecord> get _attRef =>
      _db.collection('attendance').withConverter<AttendanceRecord>(
        fromFirestore: (snap, _) => AttendanceRecord.fromMap(snap.id, snap.data()!),
        toFirestore: (record, _) => record.toMap(),
      );

  // ---------------------------------------------------------------------------
  // WRITE METHODS
  // ---------------------------------------------------------------------------
  /// Records a QR scan. The `verifyQrScan` Cloud Function checks the code against
  /// server time, its signature and the student's section, then marks the
  /// student present (see firebase_functions/attendance_core.js).
  Future<void> markPresentSecure({
    required String sessionId,
    required String studentId,
    required String rawCode,
  }) async {
    try {
      await _db.collection('attendance_scans').add({
        'sessionId': sessionId,
        'studentId': studentId,
        'payload': rawCode,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Batch update attendance records securely. Used by Admin overrides.
  Future<void> batchUpdateStatus(Map<String, AttendanceStatus> updates, String adminId) async {
    if (updates.isEmpty) return;

    final batch = _db.batch();
    updates.forEach((recordId, newStatus) {
      final ref = _attRef.doc(recordId);
      batch.update(ref, {
        'status': newStatus.name,
        'markedByTeacherId': adminId,
        'markedAt': FieldValue.serverTimestamp(),
      });
    });

    try {
      await batch.commit();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ---------------------------------------------------------------------------
  // READ METHODS
  // ---------------------------------------------------------------------------
  Future<List<AttendanceRecord>> forStudent(String studentId) async {
    try {
      final snapshot = await _attRef
          .where('studentId', isEqualTo: studentId)
          .orderBy('date', descending: true)
          .limit(300) // Performance constraint
          .get();
      return snapshot.docs.map((e) => e.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<List<AttendanceRecord>> getRecordsForSession(String sessionId) async {
    try {
      final snapshot = await _attRef.where('sessionId', isEqualTo: sessionId).get();
      return snapshot.docs.map((e) => e.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Safety limit on querying all records to prevent massive data reads
  Future<List<AttendanceRecord>> allRecords({int limit = 1000}) async {
    try {
      final snapshot = await _attRef
          .orderBy('date', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((e) => e.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }
}