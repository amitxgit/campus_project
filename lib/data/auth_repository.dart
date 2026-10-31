// lib/data/auth_repository.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';

import '../core/models/user.dart';
import '../core/models/role.dart';
import '../core/services/local_storage.dart';
import '../core/utils/firebase_error_parser.dart';
import '../core/utils/login_id.dart';
import '../main.dart' show appFunctions;

class AuthRepository {
  final LocalStorage _storage;
  final fb_auth.FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthRepository(
      this._storage, {
        fb_auth.FirebaseAuth? auth,
        FirebaseFirestore? db,
      })  : _auth = auth ?? fb_auth.FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  // ============================
  // 🔹 COLLECTION REFERENCE
  // ============================
  CollectionReference<UserAccount> get _usersRef =>
      _db.collection('users').withConverter<UserAccount>(
        fromFirestore: (snap, _) =>
            UserAccount.fromMap(snap.id, snap.data()!),
        toFirestore: (user, _) => user.toMap(),
      );

  // ============================
  // 🔹 AUTH STATE STREAM
  // ============================
  Stream<UserAccount?> authStateChanges() {
    return _auth.authStateChanges().asyncMap(_mapFirebaseUserToAppUser);
  }

  /// The signed-in user's profile, kept from the last read so the many
  /// screens that call [currentUser] don't each fetch it again.
  UserAccount? _cachedUser;

  Future<UserAccount?> _mapFirebaseUserToAppUser(
      fb_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      _cachedUser = null;
      return null;
    }

    try {
      final doc = await _usersRef.doc(firebaseUser.uid).get();

      if (!doc.exists) {
        debugPrint('⚠️ No Firestore profile found for UID: ${firebaseUser.uid}');
        return null;
      }

      final user = doc.data();
      _cachedUser = user;
      if (user != null) {
        await _storage.writeString('session_user_id', user.id);
      }

      return user;
    } catch (e) {
      debugPrint('❌ Error mapping user: $e');
      return null;
    }
  }

  // ============================
  // 🔹 CURRENT USER
  // ============================
  Future<UserAccount?> currentUser() async {
    final fbUser = _auth.currentUser;
    final cached = _cachedUser;
    if (fbUser != null && cached != null && cached.id == fbUser.uid) return cached;
    return _mapFirebaseUserToAppUser(fbUser);
  }

  // ============================
  // 🔹 FETCH USERS (SAFE LIMITS)
  // ============================
  Future<List<UserAccount>> allUsers({int limit = 1000}) async {
    final snapshot = await _usersRef.orderBy('name').limit(limit).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<UserAccount?> userById(String uid) async {
    final doc = await _usersRef.doc(uid).get();
    return doc.data();
  }

  /// Teacher profiles only. Use this from screens students can open, so they
  /// never download other students' personal details.
  Future<List<UserAccount>> allTeachers() async {
    final snapshot = await _usersRef
        .where('role', isEqualTo: UserRole.teacher.key)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<UserAccount>> allStudents({int limit = 1000}) async {
    final snapshot = await _usersRef
        .where('role', isEqualTo: UserRole.student.key)
        .limit(limit)
        .get();

    final students = snapshot.docs.map((doc) => doc.data()).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return students;
  }

  Future<List<UserAccount>> studentsInSection(
      String section, {
        int limit = 200,
      }) async {
    final snapshot = await _usersRef
        .where('role', isEqualTo: UserRole.student.key)
        .where('section', isEqualTo: section)
        .limit(limit)
        .get();

    final students = snapshot.docs.map((doc) => doc.data()).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return students;
  }

  // ============================
  // 🔹 LOGIN (PRODUCTION SAFE)
  // ============================
  Future<void> loginWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: LoginId.toEmail(email),
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        throw Exception('Authentication failed. Please try again.');
      }

      final doc = await _db.collection('users').doc(user.uid).get();

      // 🔴 CRITICAL CHECK 1: Firestore doc exists
      if (!doc.exists) {
        await _auth.signOut();
        throw Exception(
          'No profile found. Contact admin or ensure UID matches Firestore.',
        );
      }

      final data = doc.data();

      // 🔴 CRITICAL CHECK 2: role exists
      if (data == null || !data.containsKey('role')) {
        await _auth.signOut();
        throw Exception('User profile is corrupted (missing role).');
      }

      final role = data['role'];

      // 🔴 CRITICAL CHECK 3: enforce lowercase roles
      if (role is String && role != role.toLowerCase()) {
        await _auth.signOut();
        throw Exception(
            'Invalid role format. Must be lowercase (e.g. "admin").');
      }
    } catch (e) {
      if (e is Exception &&
          (e.toString().contains('profile') ||
              e.toString().contains('role'))) {
        rethrow;
      }
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 LOGOUT
  // ============================
  Future<void> logout() async {
    try {
      _cachedUser = null;
      await Future.wait([
        _storage.clearSession(),
        _auth.signOut(),
      ]);
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 UPDATE USER
  // ============================
  Future<void> updateUser(UserAccount user) async {
    try {
      await _usersRef.doc(user.id).set(
        user,
        SetOptions(merge: true),
      );
      if (user.id == _cachedUser?.id) _cachedUser = user;
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 CONTACT DETAILS (SELF-EDITABLE)
  // ============================
  Future<({String bio, String phone})> contactDetails(String uid) async {
    try {
      final data = (await _db.collection('users').doc(uid).get()).data() ?? {};
      return (bio: data['bio']?.toString() ?? '', phone: data['phone']?.toString() ?? '');
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> updateContactDetails(String uid, {required String bio, required String phone}) async {
    try {
      await _db.collection('users').doc(uid).update({'bio': bio, 'phone': phone});
      if (uid == _cachedUser?.id) _cachedUser = _cachedUser!.copyWith(phone: phone);
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 PASSWORD RESET
  // ============================
  Future<void> requestPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 DELETE CURRENT ACCOUNT
  // ============================
  Future<void> deleteCurrentUserAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _usersRef.doc(user.uid).delete();
      await user.delete();
      await _storage.clearSession();
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'Please re-login before deleting your account.',
        );
      }
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 CREATE (ADMIN, VIA CLOUD FUNCTION)
  // ============================
  /// Creates the Firebase Auth login and the Firestore profile under the same
  /// UID. Returns the new UID.
  Future<String> createAccount(UserAccount user, String password) async {
    final profile = user.toMap()..remove('createdAt');
    try {
      final res = await appFunctions
          .httpsCallable('createUserAccount')
          .call<Map<String, dynamic>>({'password': password, 'profile': profile});
      return res.data['uid'] as String;
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 BULK IMPORT / SET PASSWORD (ADMIN, VIA CLOUD FUNCTION)
  // ============================
  /// Creates logins for up to 200 students. Each result has ok, login and,
  /// when the server generated one, the password to hand to the student.
  Future<List<Map<String, dynamic>>> bulkCreateStudents(List<Map<String, dynamic>> rows) async {
    try {
      final res = await appFunctions
          .httpsCallable('bulkCreateStudents', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
          .call<Map<String, dynamic>>({'rows': rows});
      return (res.data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> setPassword(String uid, String password) async {
    try {
      await appFunctions
          .httpsCallable('setUserPassword')
          .call<Map<String, dynamic>>({'uid': uid, 'password': password});
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }

  // ============================
  // 🔹 DELETE (ADMIN, VIA CLOUD FUNCTION)
  // ============================
  /// Removes both the login and the profile. Permission checks happen
  /// server-side.
  Future<void> deleteAccount(String userId) async {
    try {
      await appFunctions
          .httpsCallable('deleteUserAccount')
          .call<Map<String, dynamic>>({'uid': userId});
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }
}