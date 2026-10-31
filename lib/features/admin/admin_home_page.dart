// lib/features/admin/admin_home_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/ui_kit.dart';
import '../../core/models/role.dart';
import '../../core/models/query_ticket.dart';
import '../../data/settings_repository.dart';
import '../../theme.dart';

// -----------------------------------------------------------------------------
// VIEW MODEL & PROVIDER
// -----------------------------------------------------------------------------

class AdminDashboardVM {
  final int totalUsers;
  final int totalStudents;
  final int totalTeachers;
  final int attendanceToday;
  final int openQueries;

  AdminDashboardVM({
    required this.totalUsers,
    required this.totalStudents,
    required this.totalTeachers,
    required this.attendanceToday,
    required this.openQueries,
  });
}

final adminDashboardProvider = FutureProvider.autoDispose<AdminDashboardVM>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), () => link.close());
  ref.onDispose(timer.cancel);

  final db = FirebaseFirestore.instance;

  // Create timestamp boundaries for "Today"
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  // PERFORMANCE FIX: Use Server-Side Aggregation (count) instead of downloading collections
  final results = await Future.wait([
    db.collection('users').count().get(),
    db.collection('users').where('role', isEqualTo: UserRole.student.key).count().get(),
    db.collection('users').where('role', isEqualTo: UserRole.teacher.key).count().get(),
    db.collection('attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .count().get(),
    db.collection('queries')
        .where('status', whereIn: [QueryStatus.open.name, QueryStatus.inProgress.name])
        .count().get(),
  ]);

  return AdminDashboardVM(
    totalUsers: results[0].count ?? 0,
    totalStudents: results[1].count ?? 0,
    totalTeachers: results[2].count ?? 0,
    attendanceToday: results[3].count ?? 0,
    openQueries: results[4].count ?? 0,
  );
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------

class AdminHomePage extends ConsumerWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminDashboardProvider);
    final settings = ref.watch(settingsProvider);
    final p = context.palette;

    // Things done most days come first; one-off setup lives further down.
    final daily = [
      _AdminItem('Attendance', Icons.fact_check_outlined, '/admin/attendance-overrides'),
      if (settings.feesEnabled) _AdminItem('Fees', Icons.currency_rupee_rounded, '/admin/fees'),
      if (settings.testsEnabled) _AdminItem('Tests', Icons.quiz_outlined, '/tests'),
      if (settings.parentAlertsEnabled) _AdminItem('Parent alerts', Icons.chat_outlined, '/admin/parent-alerts'),
      _AdminItem('Queries', Icons.support_agent_rounded, '/admin/query-management'),
      _AdminItem('Timetable', Icons.calendar_month_outlined, '/admin/timetable'),
      if (settings.internalMarksEnabled)
        _AdminItem('Internal marks', Icons.military_tech_outlined, '/admin/internal-marks-overrides'),
    ];
    final setup = [
      _AdminItem('Students', Icons.school_outlined, '/students/directory'),
      _AdminItem('Teachers', Icons.co_present_outlined, '/teachers/directory'),
      _AdminItem('Users', Icons.manage_accounts_outlined, '/admin/users'),
      _AdminItem('Import students', Icons.upload_file_outlined, '/admin/import-students'),
      _AdminItem('Reset passwords', Icons.key_outlined, '/admin/reset-passwords'),
      _AdminItem('Backup', Icons.cloud_sync_outlined, '/admin/import-export'),
      _AdminItem('Settings', Icons.tune_rounded, '/admin/settings'),
    ];

    Widget grid(List<_AdminItem> items) => ActionGrid(
          children: [
            for (final item in items)
              ActionTile(label: item.title, icon: item.icon, onTap: () => context.push(item.path)),
          ],
        );

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(settings.name),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminDashboardProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500)),
            ),
            AnimatedSwitcher(
              duration: Motion.medium,
              child: asyncData.when(
                loading: () => const SizedBox(height: 92, child: Center(child: CircularProgressIndicator())),
                error: (err, _) => AsyncErrorWidget(
                  message: err.toString(),
                  onRetry: () => ref.invalidate(adminDashboardProvider),
                ),
                data: (vm) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatBlock(
                          value: '${vm.totalStudents}',
                          label: 'Students',
                          onTap: () => context.push('/students/directory'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatBlock(
                          value: '${vm.attendanceToday}',
                          label: 'Marked today',
                          tone: p.accent,
                          onTap: () => context.push('/admin/attendance-overrides'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatBlock(
                          value: '${vm.openQueries}',
                          label: 'Open queries',
                          tone: vm.openQueries > 0 ? p.warning : null,
                          onTap: () => context.push('/admin/query-management'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SectionLabel('Today'),
            grid(daily),
            const SectionLabel('Setup'),
            grid(setup),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPER MODELS
// -----------------------------------------------------------------------------

class _AdminItem {
  final String title;
  final IconData icon;
  final String path;
  _AdminItem(this.title, this.icon, this.path);
}
