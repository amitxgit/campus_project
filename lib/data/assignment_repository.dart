// lib/data/assignment_repository.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/models/assignment.dart';
import '../core/utils/firebase_error_parser.dart';

class AssignmentRepository {
  /// Must match the limit in storage.rules.
  static const int maxFileBytes = 20 * 1024 * 1024;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Assignment> get _assignmentsRef =>
      _db.collection('assignments').withConverter<Assignment>(
        fromFirestore: (snap, _) => Assignment.fromMap(snap.id, snap.data()!),
        toFirestore: (a, _) => a.toMap(),
      );

  CollectionReference<AssignmentSubmission> _submissionsRef(String assignmentId) =>
      _db
          .collection('assignments')
          .doc(assignmentId)
          .collection('submissions')
          .withConverter<AssignmentSubmission>(
            fromFirestore: (snap, _) => AssignmentSubmission.fromMap(snap.data()!),
            toFirestore: (s, _) => s.toMap(),
          );

  // ---------------------------------------------------------------------------
  // ASSIGNMENTS
  // ---------------------------------------------------------------------------
  Future<List<Assignment>> forSection(String section) async {
    try {
      final snapshot = await _assignmentsRef
          .where('section', isEqualTo: section)
          .orderBy('dueDate', descending: true)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Staff only (enforced by rules).
  Future<List<Assignment>> recent({int limit = 300}) async {
    try {
      final snapshot = await _assignmentsRef
          .orderBy('dueDate', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> create(Assignment assignment) async {
    try {
      await _assignmentsRef.add(assignment);
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _assignmentsRef.doc(id).delete();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ---------------------------------------------------------------------------
  // SUBMISSIONS
  // ---------------------------------------------------------------------------
  Future<AssignmentSubmission?> submissionOf(String assignmentId, String studentId) async {
    try {
      final doc = await _submissionsRef(assignmentId).doc(studentId).get();
      return doc.data();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<List<AssignmentSubmission>> submissions(String assignmentId) async {
    try {
      final snapshot = await _submissionsRef(assignmentId).get();
      return snapshot.docs.map((d) => d.data()).toList()
        ..sort((a, b) => a.studentName.compareTo(b.studentName));
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Uploads the optional file to Storage first, then records the submission.
  /// Turning in again replaces the previous submission.
  Future<void> submit({
    required String assignmentId,
    required String studentId,
    required String studentName,
    required String text,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    try {
      final previous = await submissionOf(assignmentId, studentId);

      String? filePath = previous?.filePath;
      String? storedName = previous?.fileName;
      if (fileBytes != null && fileName != null) {
        if (fileBytes.length > maxFileBytes) {
          throw Exception('File is too large. The limit is 20 MB.');
        }
        final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        filePath = 'submissions/$assignmentId/$studentId/$safeName';
        storedName = fileName;
        await _storage.ref(filePath).putData(fileBytes);
        if (previous?.filePath != null && previous!.filePath != filePath) {
          await _storage.ref(previous.filePath!).delete().catchError((_) {});
        }
      }

      await _submissionsRef(assignmentId).doc(studentId).set(AssignmentSubmission(
        studentId: studentId,
        studentName: studentName,
        text: text,
        filePath: filePath,
        fileName: storedName,
        submittedAt: DateTime.now(),
      ));
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<String> fileUrl(String filePath) async {
    try {
      return await _storage.ref(filePath).getDownloadURL();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }
}
