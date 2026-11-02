// lib/data/fee_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/fee.dart';
import '../core/utils/firebase_error_parser.dart';
import '../main.dart' show appFunctions;

class FeeRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _accounts => _db.collection('fee_accounts');
  DocumentReference<Map<String, dynamic>> get _counters => _db.collection('meta').doc('counters');

  CollectionReference<Map<String, dynamic>> _payments(String studentId) =>
      _accounts.doc(studentId).collection('payments');

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  /// Admin only (enforced by rules).
  Future<List<FeeAccount>> allAccounts() => _guard(() async {
        final snap = await _accounts.get();
        return snap.docs.map((d) => FeeAccount.fromMap(d.id, d.data())).toList();
      });

  Future<FeeAccount?> account(String studentId) => _guard(() async {
        final doc = await _accounts.doc(studentId).get();
        return doc.exists ? FeeAccount.fromMap(doc.id, doc.data()!) : null;
      });

  Future<List<FeePayment>> payments(String studentId) => _guard(() async {
        final snap = await _payments(studentId).orderBy('paidOn', descending: true).get();
        return snap.docs.map((d) => FeePayment.fromMap(d.id, d.data())).toList();
      });

  /// Admin only: every payment with paidOn in [from, to), oldest first, with
  /// the student it belongs to (the payment's parent account).
  Future<List<({String studentId, FeePayment payment})>> paymentsBetween(DateTime from, DateTime to) =>
      _guard(() async {
        final snap = await _db
            .collectionGroup('payments')
            .where('paidOn', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
            .where('paidOn', isLessThan: Timestamp.fromDate(to))
            .orderBy('paidOn')
            .get();
        return snap.docs
            .map((d) => (studentId: d.reference.parent.parent!.id, payment: FeePayment.fromMap(d.id, d.data())))
            .toList();
      });

  /// Creates or updates a fee plan. Never touches `paidAmount`, which only
  /// changes together with a payment.
  Future<void> savePlan(FeeAccount account) => _guard(() async {
        final map = account.toMap()..remove('paidAmount');
        await _accounts.doc(account.studentId).set(map, SetOptions(merge: true));
      });

  /// Applies the same plan to many students at once (batched).
  Future<void> savePlans(List<FeeAccount> accounts) => _guard(() async {
        for (var i = 0; i < accounts.length; i += 400) {
          final batch = _db.batch();
          for (final a in accounts.skip(i).take(400)) {
            final map = a.toMap()..remove('paidAmount');
            batch.set(_accounts.doc(a.studentId), map, SetOptions(merge: true));
          }
          await batch.commit();
        }
      });

  /// Records a payment, assigns the next receipt number and updates the
  /// account's paid total, all atomically. Returns the saved payment.
  Future<FeePayment> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMode mode,
    required String reference,
    required String note,
    required DateTime paidOn,
    required String receivedBy,
  }) =>
      _guard(() async {
        if (amount <= 0) throw Exception('Amount must be more than zero.');
        final accountRef = _accounts.doc(studentId);
        final paymentRef = _payments(studentId).doc();

        return _db.runTransaction((tx) async {
          final account = await tx.get(accountRef);
          if (!account.exists) throw Exception('Set up a fee plan for this student first.');
          final counters = await tx.get(_counters);
          final receiptNo = ((counters.data()?['receiptSeq'] as num?)?.toInt() ?? 0) + 1;

          final payment = FeePayment(
            id: paymentRef.id,
            amount: amount,
            mode: mode,
            reference: reference,
            note: note,
            paidOn: paidOn,
            receiptNo: receiptNo,
            receivedBy: receivedBy,
          );
          tx.set(_counters, {'receiptSeq': receiptNo}, SetOptions(merge: true));
          tx.set(paymentRef, payment.toMap());
          tx.update(accountRef, {
            'paidAmount': FieldValue.increment(amount),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return payment;
        });
      });

  /// Cancels a payment entered by mistake. The record is kept (marked void)
  /// for the audit trail; the amount is removed from the paid total.
  Future<void> voidPayment(String studentId, FeePayment payment) => _guard(() async {
        if (payment.voided) return;
        final accountRef = _accounts.doc(studentId);
        final paymentRef = _payments(studentId).doc(payment.id);
        await _db.runTransaction((tx) async {
          final current = await tx.get(paymentRef);
          if (current.data()?['voided'] == true) return;
          tx.update(paymentRef, {'voided': true});
          tx.update(accountRef, {
            'paidAmount': FieldValue.increment(-payment.amount),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      });

  // ------------------------------------------------------ Razorpay (optional)

  /// Stores Razorpay keys in a doc clients can write but never read back;
  /// only Cloud Functions read it. The key id (public) also goes in settings
  /// so the app knows payment links are available.
  Future<void> saveRazorpayCredentials({
    required String keyId,
    required String keySecret,
    required String webhookSecret,
  }) =>
      _guard(() async {
        await _db.collection('secrets').doc('razorpay').set({
          'keyId': keyId,
          'keySecret': keySecret,
          'webhookSecret': webhookSecret,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _db.collection('settings').doc('institution').set({'razorpayKeyId': keyId}, SetOptions(merge: true));
      });

  Future<void> deleteRazorpayCredentials() => _guard(() async {
        await _db.collection('secrets').doc('razorpay').delete();
        await _db.collection('settings').doc('institution').set({'razorpayKeyId': ''}, SetOptions(merge: true));
      });

  /// Creates a Razorpay payment link for [studentId]. [amount] defaults (on
  /// the server) to what is payable now. The payment is recorded
  /// automatically by the razorpayWebhook function once the parent pays.
  Future<({String url, double amount})> createPaymentLink(String studentId, {double? amount}) =>
      _guard(() async {
        final res = await appFunctions.httpsCallable('createFeePaymentLink').call<Map<String, dynamic>>({
          'studentId': studentId,
          if (amount != null) 'amount': amount,
        });
        return (url: res.data['url'] as String, amount: (res.data['amount'] as num).toDouble());
      });
}
