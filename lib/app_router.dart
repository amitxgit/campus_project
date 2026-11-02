// lib/app_router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models/role.dart';
import 'main.dart';

// Pages
import 'features/auth/splash_page.dart';
import 'features/auth/login_page.dart';
import 'features/about/about_page.dart';
import 'features/profile/my_profile_page.dart';
import 'features/profile/update_profile_page.dart';
import 'features/notifications/notification_page.dart';
import 'features/notices/notices_page.dart';
import 'features/assignments/assignments_page.dart';
import 'features/people/students_directory_page.dart';
import 'features/people/teacher_directory_page.dart';

// Student
import 'features/student/student_home_page.dart';
import 'features/student/student_attendance_page.dart';
import 'features/student/timetable_page.dart';
import 'features/student/raise_query_page.dart';
import 'features/student/scan_qr_page.dart';
import 'features/student/internal_marks_page.dart' as student_marks;

// Teacher
import 'features/teacher/teacher_home_page.dart';
import 'features/teacher/generate_qr_page.dart';
import 'features/teacher/review_attendance_page.dart';
import 'features/teacher/remarks_board_page.dart';
import 'features/teacher/internal_marks_page.dart' as teacher_marks;

// Admin
import 'features/admin/admin_home_page.dart';
import 'features/admin/user_management_page.dart';
import 'features/admin/timetable_builder_page.dart';
import 'features/admin/attendance_overrides_page.dart';
import 'features/admin/internal_marks_overrides_page.dart';
import 'features/admin/import_export_page.dart';
import 'features/admin/reset_passwords_page.dart';
import 'features/admin/query_management_page.dart';
import 'features/admin/institution_settings_page.dart';
import 'features/admin/import_students_page.dart';
import 'features/fees/fees_admin_page.dart';
import 'features/fees/fee_detail_page.dart';
import 'features/enquiries/enquiries_page.dart';
import 'features/reports/reports_page.dart';
import 'features/legal/legal_page.dart';
import 'features/admin/deletion_requests_page.dart';
import 'features/fees/my_fees_page.dart';
import 'features/parent_alerts/parent_alerts_page.dart';
import 'features/tests/tests_page.dart';
import 'features/tests/test_detail_page.dart';
import 'features/tests/my_results_page.dart';

// ============================
// 🔹 ROUTE CONSTANTS
// ============================
class AppRoutes {
  static const splash = '/';
  static const login = '/login';

  static const studentHome = '/home/student';
  static const teacherHome = '/home/teacher';
  static const adminHome = '/home/admin';

  static const student = '/student';
  static const teacher = '/teacher';
  static const admin = '/admin';

  static const studentsDirectory = '/students/directory';
  static const teachersDirectory = '/teachers/directory';
  static const tests = '/tests';
}

// ============================
// 🔹 SESSION STATE (WORKSPACE SWITCHER)
// ============================
// Tracks the active workspace without modifying the database role
final sessionRoleProvider = StateProvider<UserRole?>((ref) => null);

// ============================
// 🔹 ROUTE GUARD SERVICE
// ============================
class RouteGuard {
  static String? checkAccess({
    required String location,
    required UserRole role,
    required Map<String, List<UserRole>> permissions,
  }) {
    final sortedKeys = permissions.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final prefix in sortedKeys) {
      if (location.startsWith(prefix)) {
        final allowed = permissions[prefix]!;
        if (!allowed.contains(role)) {
          return _home(role);
        }
        break;
      }
    }

    return null;
  }

  static String _home(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return AppRoutes.adminHome;
      case UserRole.teacher:
        return AppRoutes.teacherHome;
      case UserRole.student:
        return AppRoutes.studentHome;
    }
  }
}

// ============================
// 🔹 ROUTE CONFIG
// ============================
class RouteConfig {
  static final permissions = <String, List<UserRole>>{
    AppRoutes.admin: [UserRole.admin],
    AppRoutes.adminHome: [UserRole.admin],
    AppRoutes.teacher: [UserRole.teacher],
    AppRoutes.teacherHome: [UserRole.teacher],
    AppRoutes.student: [UserRole.student],
    AppRoutes.studentHome: [UserRole.student],
    AppRoutes.studentsDirectory: [UserRole.admin, UserRole.teacher],
    AppRoutes.teachersDirectory: [UserRole.admin, UserRole.teacher, UserRole.student],
    AppRoutes.tests: [UserRole.admin, UserRole.teacher],
  };
}

// ============================
// 🔹 ROUTER PROVIDER
// ============================
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final sessionRole = ref.watch(sessionRoleProvider); // ✅ Listen to workspace toggles

  return GoRouter(
    initialLocation: AppRoutes.splash,

    redirect: (context, state) {
      final isLoading = authState.isLoading;
      final user = authState.valueOrNull;

      final location = state.matchedLocation;
      final isLogin = location == AppRoutes.login;
      final isSplash = location == AppRoutes.splash;

      if (isLoading) return AppRoutes.splash;

      // Privacy policy and terms are public (linked from the login screen).
      final isLegal = location.startsWith('/legal/');

      if (user == null) {
        return isLogin || isLegal ? null : AppRoutes.login;
      }

      // ✅ Use the selected workspace role, or default to the database role
      final effectiveRole = sessionRole ?? user.role;

      if (isLogin || isSplash) {
        return RouteGuard._home(effectiveRole);
      }

      final blockedRoute = RouteGuard.checkAccess(
        location: location,
        role: effectiveRole,
        permissions: RouteConfig.permissions,
      );

      return blockedRoute;
    },

    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashPage()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginPage()),

      // ===== COMMON =====
      GoRoute(path: '/about', builder: (_, __) => const AboutPage()),
      GoRoute(path: '/legal/:slug', builder: (_, state) => LegalPage(slug: state.pathParameters['slug'] ?? '')),
      GoRoute(path: '/profile', builder: (_, __) => const MyProfilePage()),
      GoRoute(path: '/profile/update', builder: (_, __) => const UpdateProfilePage()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),
      GoRoute(path: '/notices', builder: (_, __) => const NoticesPage()),
      GoRoute(path: '/assignments', builder: (_, __) => const AssignmentsPage()),
      GoRoute(path: AppRoutes.teachersDirectory, builder: (_, __) => const TeacherDirectoryPage()),

      // ===== RESTRICTED =====
      GoRoute(path: AppRoutes.studentsDirectory, builder: (_, __) => const StudentsDirectoryPage()),

      // ===== STUDENT =====
      GoRoute(path: AppRoutes.studentHome, builder: (_, __) => const StudentHomePage()),
      GoRoute(path: '/student/attendance', builder: (_, __) => const StudentAttendancePage()),
      GoRoute(path: '/student/timetable', builder: (_, __) => const TimetablePage()),
      GoRoute(path: '/student/raise-query', builder: (_, __) => const RaiseQueryPage()),
      GoRoute(path: '/student/internal-marks', builder: (_, __) => const student_marks.InternalMarksPage()),
      GoRoute(path: '/student/scan-qr', builder: (_, __) => const ScanQRPage()),
      GoRoute(path: '/student/fees', builder: (_, __) => const MyFeesPage()),
      GoRoute(path: '/student/results', builder: (_, __) => const MyResultsPage()),
      GoRoute(path: AppRoutes.tests, builder: (_, __) => const TestsPage()),
      GoRoute(
        path: '/tests/:testId',
        builder: (_, state) => TestDetailPage(testId: state.pathParameters['testId'] ?? ''),
      ),

      // ===== TEACHER =====
      GoRoute(path: AppRoutes.teacherHome, builder: (_, __) => const TeacherHomePage()),
      GoRoute(
        path: '/teacher/generate-qr/:entryId',
        builder: (_, state) {
          final entryId = state.pathParameters['entryId'] ?? '';
          return GenerateQRPage(entryId: entryId);
        },
      ),
      GoRoute(
        path: '/teacher/review-attendance/:sessionId',
        builder: (_, state) {
          final sessionId = state.pathParameters['sessionId'] ?? '';
          return ReviewAttendancePage(sessionId: sessionId);
        },
      ),
      GoRoute(path: '/teacher/remarks-board', builder: (_, __) => const RemarksBoardPage()),
      GoRoute(path: '/teacher/internal-marks', builder: (_, __) => const teacher_marks.InternalMarksPage()),

      // ===== ADMIN =====
      GoRoute(path: AppRoutes.adminHome, builder: (_, __) => const AdminHomePage()),
      GoRoute(
        path: '/admin/users',
        builder: (_, state) {
          final addStudent = state.uri.queryParameters['add'] == 'student';
          return UserManagementPage(addStudentOnOpen: addStudent);
        },
      ),
      GoRoute(path: '/admin/timetable', builder: (_, __) => const TimetableBuilderPage()),
      GoRoute(path: '/admin/attendance-overrides', builder: (_, __) => const AttendanceOverridesPage()),
      GoRoute(path: '/admin/internal-marks-overrides', builder: (_, __) => const InternalMarksOverridesPage()),
      GoRoute(path: '/admin/import-export', builder: (_, __) => const ImportExportPage()),
      GoRoute(path: '/admin/reset-passwords', builder: (_, __) => const ResetPasswordsPage()),
      GoRoute(path: '/admin/query-management', builder: (_, __) => const QueryManagementPage()),
      GoRoute(path: '/admin/settings', builder: (_, __) => const InstitutionSettingsPage()),
      GoRoute(path: '/admin/fees', builder: (_, __) => const FeesAdminPage()),
      GoRoute(path: '/admin/import-students', builder: (_, __) => const ImportStudentsPage()),
      GoRoute(path: '/admin/parent-alerts', builder: (_, __) => const ParentAlertsPage()),
      GoRoute(path: '/admin/enquiries', builder: (_, __) => const EnquiriesPage()),
      GoRoute(path: '/admin/reports', builder: (_, __) => const ReportsPage()),
      GoRoute(path: '/admin/deletion-requests', builder: (_, __) => const DeletionRequestsPage()),
      GoRoute(
        path: '/admin/fees/:studentId',
        builder: (_, state) => FeeDetailPage(studentId: state.pathParameters['studentId'] ?? ''),
      ),
    ],

    errorBuilder: (_, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found\n${state.error}',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
});