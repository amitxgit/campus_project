// lib/data/enquiry_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/enquiry.dart';
import '../core/utils/firebase_error_parser.dart';

/// Admins read and change enquiries; teachers can only add them (rules).
class EnquiryRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('enquiries');

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Admin only. Newest first.
  Stream<List<Enquiry>> watchAll() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Enquiry.fromMap(d.id, d.data())).toList());

  /// Admin only: enquiries created since the start of this month.
  Future<EnquiryConversion> conversionThisMonth([DateTime? now]) => _guard(() async {
        final at = now ?? DateTime.now();
        final snap = await _col
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(EnquiryConversion.monthStart(at)))
            .get();
        return EnquiryConversion.forMonth(snap.docs.map((d) => Enquiry.fromMap(d.id, d.data())), at);
      });

  /// Staff (teachers too). New enquiries always start as "new".
  Future<void> add(Enquiry e) => _guard(() async {
        final map = e.toMap()
          ..['status'] = EnquiryStatus.newEnquiry.key
          ..remove('studentId')
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();
        await _col.add(map);
      });

  Future<void> save(Enquiry e) => _guard(() async {
        final map = e.toMap()
          ..remove('createdAt')
          ..remove('createdBy')
          ..['updatedAt'] = FieldValue.serverTimestamp();
        await _col.doc(e.id).update(map);
      });

  Future<void> setStatus(String id, EnquiryStatus status) => _guard(() => _col.doc(id).update({
        'status': status.key,
        // Nothing left to follow up once they've joined or been lost.
        if (!status.isOpen) 'nextFollowUp': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }));

  /// After "Convert to student": joined, linked to the new student.
  Future<void> markJoined(String id, String studentId) => _guard(() => _col.doc(id).update({
        'status': EnquiryStatus.joined.key,
        'studentId': studentId,
        'nextFollowUp': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }));

  Future<void> delete(String id) => _guard(() => _col.doc(id).delete());
}
