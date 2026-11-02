// lib/data/attendance_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/models/attendance.dart';
import '../core/models/attendance_session.dart';
import '../core/utils/firebase_error_parser.dart';
import '../main.dart' show appFunctions;

class AttendanceRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = appFunctions;

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

  /// Creates a session on the server and returns its id plus the secret the
  /// teacher's device uses to sign the rotating QR code.
  Future<({String sessionId, String secret})> startSession(String entryId) async {
    try {
      final res = await _functions
          .httpsCallable('startAttendanceSession')
          .call<Map<String, dynamic>>({'entryId': entryId});
      return (
        sessionId: res.data['sessionId'] as String,
        secret: res.data['secret'] as String,
      );
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> endSession(String sessionId) async {
    await sessionsRef.doc(sessionId).update({'isActive': false});
  }

  /// Sends a scanned QR payload to the server, which verifies the signature,
  /// freshness and section before writing the attendance record.
  /// Returns true if the student had already been marked for this session.
  Future<bool> markPresentFromQr(Map<String, dynamic> payload) async {
    try {
      final res = await _functions
          .httpsCallable('markAttendance')
          .call<Map<String, dynamic>>(payload);
      return res.data['alreadyMarked'] == true;
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
  /// Newest first. [limit] null reads everything (report cards).
  Future<List<AttendanceRecord>> forStudent(String studentId, {int? limit = 300}) async {
    try {
      var query = _attRef.where('studentId', isEqualTo: studentId).orderBy('date', descending: true);
      if (limit != null) query = query.limit(limit); // Performance constraint
      final snapshot = await query.get();
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

  Future<List<AttendanceRecord>> forSubject(String subjectId) async {
    try {
      final snapshot = await _attRef.where('subjectId', isEqualTo: subjectId).get();
      return snapshot.docs.map((e) => e.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Admin only: records dated in [from, to).
  Future<List<AttendanceRecord>> between(DateTime from, DateTime to) async {
    try {
      final snapshot = await _attRef
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('date', isLessThan: Timestamp.fromDate(to))
          .get();
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