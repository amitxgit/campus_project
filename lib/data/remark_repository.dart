// lib/data/remark_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/remark.dart';

class RemarkRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Remarks are private to the teacher who wrote them (admins can audit),
  /// so saving one deliberately does not notify the student.
  RemarkRepository();

  CollectionReference<StudentRemark> get _remarksRef =>
      _db.collection('remarks').withConverter<StudentRemark>(
        // FIX: Pass snapshot.id to fromMap
        fromFirestore: (snapshot, _) => StudentRemark.fromMap(snapshot.id, snapshot.data()!),
        toFirestore: (remark, _) => remark.toMap(),
      );

  // Predictable document ID to ensure unique remark per teacher/student pair
  String _docId(String teacherId, String studentId) => '${teacherId}_$studentId';

  // --- READ METHODS ---

  /// Get remark for specific teacher-student pair
  Future<StudentRemark?> getRemark(String teacherId, String studentId) async {
    final doc = await _remarksRef.doc(_docId(teacherId, studentId)).get();
    return doc.data();
  }

  /// Get all remarks given by a teacher
  Future<List<StudentRemark>> forTeacher(String teacherId) async {
    final snapshot = await _remarksRef.where('teacherId', isEqualTo: teacherId).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// Get all remarks received by a student, sorted newest first
  Future<List<StudentRemark>> forStudent(String studentId) async {
    final snapshot = await _remarksRef
        .where('studentId', isEqualTo: studentId)
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  // --- WRITE METHODS ---

  /// Create or update the teacher's remark on a student.
  Future<void> upsertRemark({
    required String teacherId,
    required String studentId,
    required String tag,
  }) async {
    final docId = _docId(teacherId, studentId);
    final now = DateTime.now();

    final remark = StudentRemark(
      id: docId,
      teacherId: teacherId,
      studentId: studentId,
      tag: tag,
      updatedAt: now,
    );

    await _remarksRef.doc(docId).set(remark, SetOptions(merge: true));
  }

  /// Delete a remark by teacher-student pair
  Future<void> deleteRemark(String teacherId, String studentId) async {
    await _remarksRef.doc(_docId(teacherId, studentId)).delete();
  }
}