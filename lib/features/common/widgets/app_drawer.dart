// lib/features/common/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import '../../../core/utils/login_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/role.dart';
import '../../../main.dart';
import '../../../app_router.dart'; // Needed for sessionRoleProvider
import '../../../core/models/institution_settings.dart';
import '../../../data/settings_repository.dart';
import '../../../theme.dart';
import 'animated_theme_switcher.dart';
import '../../../core/utils/firebase_error_parser.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authStateProvider);
    final sessionRole = ref.watch(sessionRoleProvider); // Active workspace

    return Drawer(
      child: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(FirebaseErrorParser.getMessage(e))),
          data: (user) {
            if (user == null) {
              return const Center(child: Text('Not logged in'));
            }

            // Determine effective role for menu generation
            final effectiveRole = sessionRole ?? user.role;
            final settings = ref.watch(settingsProvider);
            final roleMenu = _getMenuForRole(effectiveRole, settings);

            final commonMenu = [
              const _DrawerItem('Notices', Icons.campaign_outlined, '/notices'),
              const _DrawerItem('Assignments', Icons.assignment_outlined, '/assignments'),
              const _DrawerItem('Teachers', Icons.co_present_outlined, '/teachers/directory'),
              const _DrawerItem('Profile', Icons.person_outline_rounded, '/profile'),
              const _DrawerItem('About', Icons.info_outline_rounded, '/about'),
            ];

            return Column(
              children: [
                _buildHeader(context, user.name, LoginId.isPhoneLogin(user.email) ? user.phone : (user.email ?? user.phone), effectiveRole.label),

                if (user.isAdmin || user.role == UserRole.admin)
                  _buildWorkspaceSwitcher(context, ref, effectiveRole),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    children: [
                      ...roleMenu.items.map((item) => _buildItem(context, item)),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        child: Divider(color: context.palette.line),
                      ),
                      ...commonMenu.map((item) => _buildItem(context, item)),
                    ],
                  ),
                ),

                _buildFooter(context, ref),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, String name, String subtitle, String role) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: p.ink,
            foregroundColor: p.background,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.2, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isEmpty ? role : '$role  ·  $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WORKSPACE SWITCHER
  // ---------------------------------------------------------------------------
  Widget _buildWorkspaceSwitcher(BuildContext context, WidgetRef ref, UserRole currentEffectiveRole) {
    final current = currentEffectiveRole == UserRole.admin ? UserRole.admin : UserRole.teacher;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<UserRole>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: UserRole.admin, label: Text('Admin')),
            ButtonSegment(value: UserRole.teacher, label: Text('Teacher')),
          ],
          selected: {current},
          onSelectionChanged: (sel) {
            final newRole = sel.first;
            if (newRole == current) return;
            ref.read(sessionRoleProvider.notifier).state = newRole;
            Navigator.pop(context); // Close drawer
            context.go(newRole == UserRole.admin ? '/home/admin' : '/home/teacher');
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MENU ITEM TILE
  // ---------------------------------------------------------------------------
  Widget _buildItem(BuildContext context, _DrawerItem item) {
    final currentRoute = GoRouterState.of(context).uri.path;
    final isSelected = currentRoute == item.route || (item.isHome && currentRoute.startsWith('/home'));
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -0.5),
        leading: Icon(item.icon, color: isSelected ? p.accent : p.inkMuted, size: 22),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? p.accent : p.ink,
            fontSize: 15,
          ),
        ),
        selected: isSelected,
        selectedTileColor: p.accentSoft,
        onTap: () {
          Navigator.pop(context);
          if (item.isHome) {
            context.go(item.route);
          } else {
            context.push(item.route);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER (THEME & LOGOUT)
  // ---------------------------------------------------------------------------
  Widget _buildFooter(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AnimatedThemeSwitcher(),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: p.danger),
            onPressed: () async {
              ref.invalidate(sessionRoleProvider); // Clear session
              await ref.read(authRepoProvider).logout();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MENU CONFIGURATIONS
  // ---------------------------------------------------------------------------
  /// Menu entries for features an institute has switched off are hidden.
  _RoleMenu _getMenuForRole(UserRole role, InstitutionSettings s) {
    switch (role) {
      case UserRole.admin:
        return _RoleMenu('Admin', [
          const _DrawerItem('Home', Icons.home_outlined, '/home/admin', isHome: true),
          const _DrawerItem('Attendance', Icons.fact_check_outlined, '/admin/attendance-overrides'),
          if (s.feesEnabled) const _DrawerItem('Fees', Icons.currency_rupee_rounded, '/admin/fees'),
          const _DrawerItem('Enquiries', Icons.person_search_outlined, '/admin/enquiries'),
          const _DrawerItem('Reports', Icons.insert_chart_outlined_rounded, '/admin/reports'),
          if (s.testsEnabled) const _DrawerItem('Tests', Icons.quiz_outlined, '/tests'),
          if (s.parentAlertsEnabled) const _DrawerItem('Parent alerts', Icons.chat_outlined, '/admin/parent-alerts'),
          const _DrawerItem('Queries', Icons.support_agent_rounded, '/admin/query-management'),
          const _DrawerItem('Timetable', Icons.calendar_month_outlined, '/admin/timetable'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Internal marks', Icons.military_tech_outlined, '/admin/internal-marks-overrides'),
          const _DrawerItem('Students', Icons.school_outlined, '/students/directory'),
          const _DrawerItem('Users', Icons.manage_accounts_outlined, '/admin/users'),
          const _DrawerItem('Import students', Icons.upload_file_outlined, '/admin/import-students'),
          const _DrawerItem('Reset passwords', Icons.key_outlined, '/admin/reset-passwords'),
          const _DrawerItem('Backup', Icons.cloud_sync_outlined, '/admin/import-export'),
          const _DrawerItem('Settings', Icons.tune_rounded, '/admin/settings'),
        ]);

      case UserRole.teacher:
        return _RoleMenu('Teacher', [
          const _DrawerItem('Home', Icons.home_outlined, '/home/teacher', isHome: true),
          const _DrawerItem('Students', Icons.school_outlined, '/students/directory'),
          if (s.testsEnabled) const _DrawerItem('Tests', Icons.quiz_outlined, '/tests'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Internal marks', Icons.assessment_outlined, '/teacher/internal-marks'),
          if (s.remarksEnabled)
            const _DrawerItem('Remarks', Icons.rate_review_outlined, '/teacher/remarks-board'),
        ]);

      case UserRole.student:
        return _RoleMenu('Student', [
          const _DrawerItem('Home', Icons.home_outlined, '/home/student', isHome: true),
          const _DrawerItem('Scan QR', Icons.qr_code_scanner_rounded, '/student/scan-qr'),
          const _DrawerItem('Attendance', Icons.fact_check_outlined, '/student/attendance'),
          const _DrawerItem('Timetable', Icons.calendar_month_outlined, '/student/timetable'),
          if (s.testsEnabled) const _DrawerItem('Results', Icons.emoji_events_outlined, '/student/results'),
          if (s.feesEnabled) const _DrawerItem('Fees', Icons.currency_rupee_rounded, '/student/fees'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Internal marks', Icons.score_outlined, '/student/internal-marks'),
          const _DrawerItem('Ask a question', Icons.help_outline_rounded, '/student/raise-query'),
        ]);
    }
  }
}

class _RoleMenu {
  final String title;
  final List<_DrawerItem> items;
  _RoleMenu(this.title, this.items);
}

class _DrawerItem {
  final String title;
  final IconData icon;
  final String route;
  final bool isHome;
  const _DrawerItem(this.title, this.icon, this.route, {this.isHome = false});
}
