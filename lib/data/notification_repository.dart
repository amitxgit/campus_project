// lib/data/notification_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/models/notification.dart';

class NotificationRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<AppNotification> get _notifRef =>
      _db.collection('notifications').withConverter<AppNotification>(
        fromFirestore: (snap, _) => AppNotification.fromMap(snap.id, snap.data()!),
        toFirestore: (n, _) => n.toMap(),
      );

  // SECURITY FIX: Centralized identity verification to prevent BOLA
  void _verifyIdentity(String requestedUserId) {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid != requestedUserId) {
      throw Exception('Unauthorized: Access control violation. You can only access your own notifications.');
    }
  }

  // --- READ METHODS ---

  Stream<List<AppNotification>> listenForUser(String userId) {
    _verifyIdentity(userId);
    return _notifRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<List<AppNotification>> forUser(String userId) async {
    _verifyIdentity(userId);
    final snapshot = await _notifRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  Future<int> unreadCount(String userId) async {
    _verifyIdentity(userId);
    final snapshot = await _notifRef
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // --- WRITE METHODS ---

  Future<void> markRead(String notificationId) async {
    // SECURITY FIX: Instead of blindly updating, ensure we only update if it belongs to current user.
    // In a production app, this should also be secured via Firestore Security Rules.
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) throw Exception('Unauthorized');

    final docRef = _notifRef.doc(notificationId);
    final doc = await docRef.get();

    if (doc.exists && doc.data()?.userId == currentUid) {
      await docRef.update({'read': true});
    } else {
      throw Exception('Unauthorized: Cannot modify this notification.');
    }
  }

  Future<void> markAllRead(String userId) async {
    _verifyIdentity(userId);
    final snapshot = await _notifRef
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Deletes one of the signed-in user's notifications (rules enforce owner).
  Future<void> delete(String notificationId) => _notifRef.doc(notificationId).delete();

  Future<void> clearForUser(String userId) async {
    _verifyIdentity(userId);
    final snapshot = await _notifRef.where('userId', isEqualTo: userId).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}