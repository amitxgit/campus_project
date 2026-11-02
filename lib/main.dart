// lib/main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme.dart';

import 'core/models/user.dart';
import 'core/services/local_storage.dart';
import 'core/providers/theme_provider.dart';
import 'app_router.dart';
import 'data/settings_repository.dart';

// --- Repositories ---
import 'data/auth_repository.dart';
import 'data/attendance_repository.dart';
import 'data/timetable_repository.dart';
import 'data/internal_marks_repository.dart';
import 'data/remark_repository.dart';
import 'data/query_repository.dart';
import 'data/notification_repository.dart';
import 'data/notice_repository.dart';
import 'data/assignment_repository.dart';
import 'data/fee_repository.dart';
import 'data/enquiry_repository.dart';
import 'data/parent_alert_repository.dart';
import 'data/test_repository.dart';

// --- Services ---
import 'core/services/notification_service.dart';
import 'core/services/firestore_notifier.dart';
import 'core/services/notification_sync_service.dart';

/// Cloud Functions live next to the Firestore database (Mumbai).
const kFunctionsRegion = 'asia-south1';
final FirebaseFunctions appFunctions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);

// -----------------------------------------------------------------------------
// GLOBAL PROVIDERS (Central Registry)
// -----------------------------------------------------------------------------

final notifServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('notifServiceProvider must be overridden in main.dart');
});

final authRepoProvider = Provider<AuthRepository>((ref) {
  final storage = ref.watch(localStorageProvider);
  return AuthRepository(storage);
});

final attendanceRepoProvider = Provider<AttendanceRepository>((ref) => AttendanceRepository());
final timetableRepoProvider = Provider<TimetableRepository>((ref) => TimetableRepository());
final internalMarksRepoProvider = Provider<InternalMarksRepository>((ref) => InternalMarksRepository());

final firestoreNotifierProvider = Provider<FirestoreNotifier>((ref) {
  final local = ref.watch(notifServiceProvider);
  return FirestoreNotifier(localService: local);
});

final remarkRepoProvider = Provider<RemarkRepository>((ref) => RemarkRepository());

final queryRepoProvider = Provider<QueryRepository>((ref) {
  final notifier = ref.watch(firestoreNotifierProvider);
  return QueryRepository(notifier);
});

final notifRepoProvider = Provider<NotificationRepository>((ref) => NotificationRepository());
final noticeRepoProvider = Provider<NoticeRepository>((ref) => NoticeRepository());
final assignmentRepoProvider = Provider<AssignmentRepository>((ref) => AssignmentRepository());
final feeRepoProvider = Provider<FeeRepository>((ref) => FeeRepository());
final parentAlertRepoProvider = Provider<ParentAlertRepository>((ref) => ParentAlertRepository());
final testRepoProvider = Provider<TestRepository>((ref) => TestRepository());
final enquiryRepoProvider = Provider<EnquiryRepository>((ref) => EnquiryRepository());

final notificationSyncServiceProvider = Provider<NotificationSyncService>((ref) {
  return NotificationSyncService(ref, FirebaseFirestore.instance);
});

// -----------------------------------------------------------------------------
// AUTH STATE
// -----------------------------------------------------------------------------

final authStateProvider = StreamProvider<UserAccount?>((ref) {
  final repo = ref.watch(authRepoProvider);
  return repo.authStateChanges();
});

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // `flutter run --dart-define=USE_EMULATORS=true` talks to the local
  // Firebase emulators (firebase emulators:start) instead of production.
  const useEmulators = bool.fromEnvironment('USE_EMULATORS');
  if (useEmulators) {
    const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    appFunctions.useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }

  final prefs = await SharedPreferences.getInstance();
  final localStorage = LocalStorage(prefs);

  final notifService = NotificationService();
  await notifService.init();

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        notifServiceProvider.overrideWithValue(notifService),
      ],
      child: const BatchwiseApp(),
    ),
  );
}

class BatchwiseApp extends ConsumerStatefulWidget {
  const BatchwiseApp({super.key});

  @override
  ConsumerState<BatchwiseApp> createState() => _BatchwiseAppState();
}

class _BatchwiseAppState extends ConsumerState<BatchwiseApp> {
  late NotificationSyncService _notifSync;

  @override
  void initState() {
    super.initState();
    _notifSync = ref.read(notificationSyncServiceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    ref.listen<AsyncValue<UserAccount?>>(authStateProvider, (prev, next) {
      next.whenData((user) {
        if (user != null) {
          _notifSync.start(user.id);
        } else {
          _notifSync.stop();
        }
      });
    });

    return MaterialApp.router(
      title: ref.watch(settingsProvider).name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}