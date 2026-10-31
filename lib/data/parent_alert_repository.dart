// lib/data/parent_alert_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/parent_alert.dart';
import '../core/utils/firebase_error_parser.dart';
import '../main.dart' show appFunctions;

class ParentAlertRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _alerts => _db.collection('parent_alerts');

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Queues automatic WhatsApp messages; the processParentAlert Cloud
  /// Function sends them and records the outcome on each doc.
  Future<void> queue({
    required List<({String studentId, String studentName, List<String> params})> items,
    required ParentAlertKind kind,
    required String requestedBy,
  }) =>
      _guard(() async {
        for (var i = 0; i < items.length; i += 400) {
          final batch = _db.batch();
          for (final item in items.skip(i).take(400)) {
            batch.set(_alerts.doc(), {
              'studentId': item.studentId,
              'studentName': item.studentName,
              'kind': kind.name,
              'params': item.params,
              'requestedBy': requestedBy,
              'status': ParentAlertStatus.pending.name,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
      });

  Future<List<ParentAlert>> recent({int limit = 100}) => _guard(() async {
        final snap = await _alerts.orderBy('createdAt', descending: true).limit(limit).get();
        return snap.docs.map((d) => ParentAlert.fromMap(d.id, d.data())).toList();
      });

  /// Stores WhatsApp Cloud API credentials in a doc clients can write but
  /// never read back; only Cloud Functions read it.
  Future<void> saveWhatsAppCredentials({required String phoneNumberId, required String token}) =>
      _guard(() => _db.collection('secrets').doc('whatsapp').set({
            'phoneNumberId': phoneNumberId,
            'token': token,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  Future<void> deleteWhatsAppCredentials() => _guard(() => _db.collection('secrets').doc('whatsapp').delete());

  /// Sends Meta's built-in "hello_world" template to [to] to check the setup.
  Future<void> sendTest(String to) => _guard(() async {
        await appFunctions.httpsCallable('testWhatsApp').call<Map<String, dynamic>>({'to': to});
      });
}
