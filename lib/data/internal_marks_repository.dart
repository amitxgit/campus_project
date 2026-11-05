// lib/data/internal_marks_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/institution_settings.dart';
import '../core/models/internal_marks.dart';

class InternalMarksRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<InternalMarks> get _marksRef =>
      _db.collection('internal_marks').withConverter<InternalMarks>(
        fromFirestore: (snap, _) => InternalMarks.fromDoc(snap),
        toFirestore: (marks, _) => marks.toMap(),
      );

  // ---------------- READ METHODS ----------------

  Future<List<InternalMarks>> getAllMarks() async {
    final snapshot = await _marksRef.get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<List<InternalMarks>> getMarksForSubject(String subjectId) async {
    final snapshot =
    await _marksRef.where('subjectId', isEqualTo: subjectId).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<List<InternalMarks>> getVisibleMarksForStudent(
      String studentId) async {
    final snapshot = await _marksRef
        .where('studentId', isEqualTo: studentId)
        .where('isVisibleToStudent', isEqualTo: true)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  // ---------------- WRITE METHODS ----------------

  /// Clamps each component to the institute's marks scheme before saving.
  Future<void> updateMarks(InternalMarks marks, InstitutionSettings scheme) async {
    final safeAssign = marks.assignmentMarks.clamp(0.0, scheme.assignmentMax);
    final safeTest = marks.testMarks.clamp(0.0, scheme.testMax);
    final safeAtt = marks.attendanceMarks.clamp(0.0, scheme.attendanceMax);
    final safeTotal = safeAssign + safeTest + safeAtt;

    final safeMarks = marks.copyWith(
      assignmentMarks: safeAssign,
      testMarks: safeTest,
      attendanceMarks: safeAtt,
      totalMarks: safeTotal,
    );

    final docId = safeMarks.id.isNotEmpty ? safeMarks.id : '${safeMarks.subjectId}_${safeMarks.studentId}';

    await _marksRef.doc(docId).set(
      safeMarks,
      SetOptions(merge: true),
    );
  }

  Future<void> publishMarksForSubject(
      String subjectId, bool isVisible) async {
    final snapshot =
    await _marksRef.where('subjectId', isEqualTo: subjectId).get();
    if (snapshot.docs.isEmpty) return;

    const int batchLimit = 500;
    final docs = snapshot.docs;

    for (var i = 0; i < docs.length; i += batchLimit) {
      final batch = _db.batch();
      final end =
      (i + batchLimit < docs.length) ? i + batchLimit : docs.length;
      final chunk = docs.sublist(i, end);

      for (final doc in chunk) {
        batch.update(doc.reference, {'isVisibleToStudent': isVisible});
      }

      await batch.commit();
    }
  }

  Future<void> adminOverride(InternalMarks marks, InstitutionSettings scheme) async {
    await updateMarks(marks, scheme);
  }

  Future<void> deleteMarks(String id) async {
    await _marksRef.doc(id).delete();
  }
}