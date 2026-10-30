// lib/features/common/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/role.dart';
import '../../../main.dart';
import '../../../app_router.dart'; // Needed for sessionRoleProvider
import '../../../core/models/institution_settings.dart';
import '../../../data/settings_repository.dart';
import 'animated_theme_switcher.dart';

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
          error: (e, _) => Center(child: Text('Error: $e')),
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
              const _DrawerItem('Teachers', Icons.school_outlined, '/teachers/directory'),
              const _DrawerItem('My Profile', Icons.person_outline, '/profile'),
              const _DrawerItem('About', Icons.info_outline, '/about'),
            ];

            return Column(
              children: [
                // 1. Premium Header
                _buildHeader(context, user.name, user.email ?? user.phone, effectiveRole.label),

                // 2. Workspace Switcher (If Applicable)
                if (user.isAdmin || user.role == UserRole.admin)
                  _buildWorkspaceSwitcher(context, ref, effectiveRole),

                // 3. Scrollable Navigation List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // ✅ FIX: Passed context here
                      _buildSectionTitle(context, roleMenu.title),
                      ...roleMenu.items.map((item) => _buildItem(context, item)),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      // ✅ FIX: Passed context here
                      _buildSectionTitle(context, 'General'),
                      ...commonMenu.map((item) => _buildItem(context, item)),
                    ],
                  ),
                ),

                // 4. Footer (Theme Switcher & Logout)
                _buildFooter(context, ref),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PREMIUM HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, String name, String subtitle, String role) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
            ),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.primary,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrentlyAdmin = currentEffectiveRole == UserRole.admin;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final newRole = isCurrentlyAdmin ? UserRole.teacher : UserRole.admin;
            ref.read(sessionRoleProvider.notifier).state = newRole;
            Navigator.pop(context); // Close drawer
            context.go(newRole == UserRole.admin ? '/home/admin' : '/home/teacher');
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Workspace',
                        style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCurrentlyAdmin ? 'Switch to Teacher' : 'Switch to Admin',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION TITLE
  // ---------------------------------------------------------------------------
  // ✅ FIX: Added BuildContext context parameter
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          letterSpacing: 1.2,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(
            item.icon,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 22,
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
          hoverColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          onTap: () {
            Navigator.pop(context);
            if (item.isHome) {
              context.go(item.route);
            } else {
              context.push(item.route);
            }
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER (THEME & LOGOUT)
  // ---------------------------------------------------------------------------
  Widget _buildFooter(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AnimatedThemeSwitcher(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              ref.invalidate(sessionRoleProvider); // Clear session
              await ref.read(authRepoProvider).logout();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
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
        return _RoleMenu('Admin Tools', [
          const _DrawerItem('Dashboard', Icons.dashboard_rounded, '/home/admin', isHome: true),
          const _DrawerItem('Users', Icons.people_rounded, '/admin/users'),
          const _DrawerItem('Students Directory', Icons.badge_rounded, '/students/directory'),
          const _DrawerItem('Timetable & Subjects', Icons.calendar_month_rounded, '/admin/timetable'),
          const _DrawerItem('Query Tickets', Icons.support_agent_rounded, '/admin/query-management'),
          const _DrawerItem('Attendance Overrides', Icons.edit_calendar_rounded, '/admin/attendance-overrides'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Marks Overrides', Icons.edit_document, '/admin/internal-marks-overrides'),
          const _DrawerItem('Reset Passwords', Icons.lock_reset_rounded, '/admin/reset-passwords'),
          const _DrawerItem('Import Data', Icons.upload_file_rounded, '/admin/import-export'),
          const _DrawerItem('Institute Settings', Icons.tune_rounded, '/admin/settings'),
        ]);

      case UserRole.teacher:
        return _RoleMenu('Faculty Tools', [
          const _DrawerItem('Dashboard', Icons.dashboard_rounded, '/home/teacher', isHome: true),
          const _DrawerItem('Students Directory', Icons.badge_rounded, '/students/directory'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Internal Marks', Icons.grading_rounded, '/teacher/internal-marks'),
          if (s.remarksEnabled)
            const _DrawerItem('Remarks Board', Icons.label_important_rounded, '/teacher/remarks-board'),
        ]);

      case UserRole.student:
        return _RoleMenu('Student Portal', [
          const _DrawerItem('Dashboard', Icons.dashboard_rounded, '/home/student', isHome: true),
          const _DrawerItem('Scan QR', Icons.qr_code_scanner_rounded, '/student/scan-qr'),
          const _DrawerItem('Attendance', Icons.fact_check_rounded, '/student/attendance'),
          if (s.internalMarksEnabled)
            const _DrawerItem('Internal Marks', Icons.score_rounded, '/student/internal-marks'),
          const _DrawerItem('Timetable', Icons.calendar_month_rounded, '/student/timetable'),
          const _DrawerItem('Raise Query', Icons.live_help_rounded, '/student/raise-query'),
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