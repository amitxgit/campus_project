// lib/features/admin/admin_home_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/role.dart';
import '../../core/models/query_ticket.dart';
import '../../data/settings_repository.dart';

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

    final tools = [
      _AdminItem('Users', Icons.manage_accounts_rounded, '/admin/users', Colors.blue),
      if (settings.feesEnabled) _AdminItem('Fees', Icons.currency_rupee_rounded, '/admin/fees', Colors.green),
      if (settings.parentAlertsEnabled)
        _AdminItem('Parent Alerts', Icons.family_restroom_rounded, '/admin/parent-alerts', Colors.pink),
      // 🔴 ROUTE FIX: Changed to match app_router.dart exactly
      _AdminItem('Queries', Icons.support_agent_rounded, '/admin/query-management', Colors.orange),
      _AdminItem('Timetable', Icons.calendar_month_rounded, '/admin/timetable', Colors.purple),
      _AdminItem('Attendance', Icons.fact_check_rounded, '/admin/attendance-overrides', Colors.teal),
      if (settings.internalMarksEnabled)
        _AdminItem('Internal Marks', Icons.military_tech_rounded, '/admin/internal-marks-overrides', Colors.amber),
      _AdminItem('Passwords', Icons.password_rounded, '/admin/reset-passwords', Colors.red),
      _AdminItem('Students', Icons.school_rounded, '/students/directory', Colors.indigo),
      _AdminItem('Teachers', Icons.history_edu_rounded, '/teachers/directory', Colors.brown),
      _AdminItem('Data Sync', Icons.cloud_sync_rounded, '/admin/import-export', Colors.green),
      _AdminItem('Settings', Icons.tune_rounded, '/admin/settings', Colors.blueGrey),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(adminDashboardProvider),
        ),
        data: (vm) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminDashboardProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Dashboard',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'System status and management tools',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                // Statistics Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ModernStatCard(
                        title: 'Total Users',
                        value: vm.totalUsers.toString(),
                        subtitle: '${vm.totalStudents} Students • ${vm.totalTeachers} Teachers',
                        icon: Icons.people_alt_rounded,
                        gradientColors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        fullWidth: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _ModernStatCard(
                              title: 'Attendance',
                              value: vm.attendanceToday.toString(),
                              subtitle: 'Marked today',
                              icon: Icons.how_to_reg_rounded,
                              gradientColors: const [Color(0xFF0D9488), Color(0xFF059669)],
                              fullWidth: false,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ModernStatCard(
                              title: 'Queries',
                              value: vm.openQueries.toString(),
                              subtitle: vm.openQueries > 0 ? 'Action required' : 'All clear',
                              icon: Icons.notifications_active_rounded,
                              gradientColors: vm.openQueries > 0
                                  ? const [Color(0xFFEA580C), Color(0xFFDC2626)]
                                  : const [Color(0xFF65A30D), Color(0xFF16A34A)],
                              fullWidth: false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Tools Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Quick Actions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: tools.length,
                  itemBuilder: (_, i) => _ModernToolCard(item: tools[i]),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPER MODELS & WIDGETS
// -----------------------------------------------------------------------------

class _AdminItem {
  final String title;
  final IconData icon;
  final String path;
  final MaterialColor colorTheme;
  _AdminItem(this.title, this.icon, this.path, this.colorTheme);
}

class _ModernStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final bool fullWidth;

  const _ModernStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.fullWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              if (fullWidth)
                const Icon(Icons.analytics_rounded, color: Colors.white38, size: 48),
            ],
          ),
          SizedBox(height: fullWidth ? 24 : 16),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ModernToolCard extends StatelessWidget {
  final _AdminItem item;

  const _ModernToolCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(item.path),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? item.colorTheme.shade900.withValues(alpha: 0.5)
                        : item.colorTheme.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    color: isDark ? item.colorTheme.shade200 : item.colorTheme.shade600,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}