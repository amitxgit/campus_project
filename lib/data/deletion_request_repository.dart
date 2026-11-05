// lib/data/deletion_request_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/user.dart';
import '../core/models/role.dart';
import '../core/utils/date_parser.dart';
import '../core/utils/firebase_error_parser.dart';
import '../core/utils/login_id.dart';

enum DeletionStatus { pending, done, rejected }

/// A user's request to delete their account (deletion_requests/{uid}).
class DeletionRequest {
  final String userId;
  final String name;
  final String role;
  final String contact;
  final String reason;
  final DeletionStatus status;
  final DateTime createdAt;

  const DeletionRequest({
    required this.userId,
    required this.name,
    required this.role,
    required this.contact,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  factory DeletionRequest.fromMap(String id, Map<String, dynamic> m) => DeletionRequest(
        userId: id,
        name: m['name'] ?? '',
        role: m['role'] ?? '',
        contact: m['contact'] ?? '',
        reason: m['reason'] ?? '',
        status: DeletionStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => DeletionStatus.pending),
        createdAt: DateParser.parse(m['createdAt'], fieldName: 'DeletionRequest.createdAt'),
      );
}

class DeletionRequestRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('deletion_requests');

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// The signed-in user's own request, if any.
  Stream<DeletionRequest?> watchMine(String uid) =>
      _col.doc(uid).snapshots().map((d) => d.exists ? DeletionRequest.fromMap(d.id, d.data()!) : null);

  /// Asks for deletion. A rejected request is reopened.
  Future<void> request(UserAccount me, String reason) => _guard(() async {
        final data = {
          'userId': me.id,
          'name': me.name,
          'role': me.role == UserRole.admin || me.isAdmin ? 'admin' : me.role.name,
          'contact': LoginId.isPhoneLogin(me.email) ? me.phone : (me.email ?? me.phone),
          'reason': reason.length > 500 ? reason.substring(0, 500) : reason,
          'status': DeletionStatus.pending.name,
          'createdAt': FieldValue.serverTimestamp(),
        };
        final existing = await _col.doc(me.id).get();
        if (existing.exists) {
          await _col.doc(me.id).update(data);
        } else {
          await _col.doc(me.id).set(data);
        }
      });

  Future<void> cancel(String uid) => _guard(() => _col.doc(uid).delete());

  /// Admin: open requests, oldest first.
  Stream<List<DeletionRequest>> watchPending() => _col
      .where('status', isEqualTo: DeletionStatus.pending.name)
      .snapshots()
      .map((s) => s.docs.map((d) => DeletionRequest.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  Future<void> reject(String uid, String adminId) => _guard(() => _col.doc(uid).update({
        'status': DeletionStatus.rejected.name,
        'handledBy': adminId,
        'handledAt': FieldValue.serverTimestamp(),
      }));
}
