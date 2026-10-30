// lib/data/settings_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/institution_settings.dart';
import '../core/utils/firebase_error_parser.dart';

class SettingsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('settings').doc('institution');

  /// Live settings; falls back to defaults until an admin has saved them.
  Stream<InstitutionSettings> watch() => _doc.snapshots().map((snap) {
        final data = snap.data();
        return data == null ? InstitutionSettings.defaults : InstitutionSettings.fromMap(data);
      });

  Future<void> save(InstitutionSettings settings) async {
    try {
      await _doc.set(settings.toMap());
    } catch (e) {
      throw Exception(FirebaseErrorParser.getMessage(e));
    }
  }
}

final settingsRepoProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

final _settingsStreamProvider = StreamProvider<InstitutionSettings>((ref) {
  return ref.watch(settingsRepoProvider).watch();
});

/// Current institution settings. Always has a value (defaults while loading
/// or offline), so widgets can read it synchronously.
final settingsProvider = Provider<InstitutionSettings>((ref) {
  return ref.watch(_settingsStreamProvider).valueOrNull ?? InstitutionSettings.defaults;
});

/// For async providers that must wait for the real settings before computing.
final settingsFutureProvider = FutureProvider<InstitutionSettings>((ref) {
  return ref.watch(_settingsStreamProvider.future);
});
