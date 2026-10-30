// lib/data/notice_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/notice.dart';
import '../core/models/role.dart';
import '../core/utils/firebase_error_parser.dart';

class NoticeRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Notice> get _noticesRef =>
      _db.collection('notices').withConverter<Notice>(
        fromFirestore: (snap, _) => Notice.fromMap(snap.id, snap.data()!),
        toFirestore: (notice, _) => notice.toMap(),
      );

  /// Students only get notices addressed to everyone or to students (the
  /// security rules reject any wider query). Staff see all notices.
  Future<List<Notice>> visibleTo(UserRole role, {int limit = 100}) async {
    try {
      Query<Notice> query = _noticesRef;
      if (role == UserRole.student) {
        query = query.where('targetAudience',
            whereIn: [NoticeAudience.all.name, NoticeAudience.students.name]);
      }
      final snapshot = await query.orderBy('createdAt', descending: true).limit(limit).get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> create(Notice notice) async {
    try {
      await _noticesRef.add(notice);
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _noticesRef.doc(id).delete();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }
}
