// lib/data/test_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/test_result.dart';
import '../core/utils/firebase_error_parser.dart';

class TestRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tests => _db.collection('tests');
  DocumentReference<Map<String, dynamic>> _marksDoc(String testId) =>
      _tests.doc(testId).collection('marks').doc('all');
  CollectionReference<Map<String, dynamic>> get _studentResults => _db.collection('student_results');

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<List<TestPaper>> recent({int limit = 200}) => _guard(() async {
        final snap = await _tests.orderBy('date', descending: true).limit(limit).get();
        return snap.docs.map((d) => TestPaper.fromMap(d.id, d.data())).toList();
      });

  Future<TestPaper?> byId(String id) => _guard(() async {
        final doc = await _tests.doc(id).get();
        return doc.exists ? TestPaper.fromMap(doc.id, doc.data()!) : null;
      });

  Future<String> create(TestPaper test) => _guard(() async {
        final ref = await _tests.add(test.toMap());
        return ref.id;
      });

  /// Marks keyed by student id; null means absent. Students not in the map
  /// haven't been entered yet.
  Future<Map<String, double?>> marks(String testId) => _guard(() async {
        final doc = await _marksDoc(testId).get();
        final data = doc.data() ?? {};
        final scores = Map<String, dynamic>.from(data['scores'] as Map? ?? {});
        final absent = List<String>.from(data['absent'] as List? ?? []);
        return {
          for (final e in scores.entries) e.key: (e.value as num).toDouble(),
          for (final id in absent) id: null,
        };
      });

  Future<void> saveMarks(String testId, Map<String, double?> marks) => _guard(() async {
        await _marksDoc(testId).set({
          'scores': {for (final e in marks.entries) if (e.value != null) e.key: e.value},
          'absent': [for (final e in marks.entries) if (e.value == null) e.key],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Saves marks, ranks everyone and copies each student's result to their
  /// own student_results doc so they can read it in one go.
  Future<TestStats> publish(TestPaper test, Map<String, double?> marks) => _guard(() async {
        await saveMarks(test.id, marks);
        final stats = rankScores(marks);
        final ids = marks.keys.toList();
        for (var i = 0; i < ids.length; i += 400) {
          final batch = _db.batch();
          for (final id in ids.skip(i).take(400)) {
            final result = StudentResult(
              testId: test.id,
              testName: test.name,
              subjectName: test.subjectName,
              date: test.date,
              maxMarks: test.maxMarks,
              marks: marks[id],
              rank: stats.ranks[id],
              outOf: stats.appeared,
              average: stats.average,
              highest: stats.highest,
            );
            batch.set(
              _studentResults.doc(id),
              {'results': {test.id: result.toMap()}},
              SetOptions(merge: true),
            );
          }
          await batch.commit();
        }
        await _tests.doc(test.id).update({
          'published': true,
          'appeared': stats.appeared,
          'average': stats.average,
          'highest': stats.highest,
        });
        return stats;
      });

  /// Hides results from students again (marks are kept).
  Future<void> unpublish(String testId, Iterable<String> studentIds) => _guard(() async {
        final ids = studentIds.toList();
        for (var i = 0; i < ids.length; i += 400) {
          final batch = _db.batch();
          for (final id in ids.skip(i).take(400)) {
            batch.set(_studentResults.doc(id), {'results': {testId: FieldValue.delete()}}, SetOptions(merge: true));
          }
          await batch.commit();
        }
        await _tests.doc(testId).update({'published': false});
      });

  Future<void> delete(String testId, Iterable<String> studentIds) => _guard(() async {
        await unpublish(testId, studentIds);
        await _marksDoc(testId).delete();
        await _tests.doc(testId).delete();
      });

  Future<List<StudentResult>> resultsFor(String studentId) => _guard(() async {
        final doc = await _studentResults.doc(studentId).get();
        final results = Map<String, dynamic>.from(doc.data()?['results'] as Map? ?? {});
        return results.entries
            .map((e) => StudentResult.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      });
}
