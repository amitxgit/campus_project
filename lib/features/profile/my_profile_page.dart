// lib/features/profile/my_profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/models/attendance.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/async_error_widget.dart';
import '../../data/settings_repository.dart';

// -----------------------------------------------------------------------------
// ROLE-SPECIFIC & PROFILE PROVIDERS
// -----------------------------------------------------------------------------

// ✅ FIX: Dedicated provider for the profile page.
// This prevents the global auth router from kicking the user to the splash screen on refresh!
final profileUserProvider = FutureProvider.autoDispose<UserAccount?>((ref) async {
  return await ref.watch(authRepoProvider).currentUser();
});

final studentProfileStatsProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) throw Exception('Not logged in');

  final records = await ref.watch(attendanceRepoProvider).forStudent(user.id);
  final total = records.length;

  final present = records.where((r) =>
  r.status == AttendanceStatus.present ||
      r.status == AttendanceStatus.excused ||
      r.status == AttendanceStatus.late).length;

  final pct = total == 0 ? 100 : ((present * 100) / total).round();

  return (total: total, present: present, pct: pct);
});

final teacherProfileSubjectsProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) throw Exception('Not logged in');

  final subjects = await ref.watch(timetableRepoProvider).allSubjects();
  final mySubjects = subjects.where((s) => s.teacherId == user.id).toList();
  final sections = mySubjects.map((s) => s.section).toSet().toList()..sort();

  return (subjects: mySubjects, sections: sections);
});

final adminProfileStatsProvider = FutureProvider.autoDispose((ref) async {
  final db = FirebaseFirestore.instance;

  final results = await Future.wait([
    db.collection('users').count().get(),
    db.collection('subjects').count().get(),
    db.collection('attendance').count().get(),
  ]);

  return (
  users: results[0].count ?? 0,
  subjects: results[1].count ?? 0,
  records: results[2].count ?? 0,
  );
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------

class MyProfilePage extends ConsumerWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ FIX: Watch the dedicated profile provider instead of authStateProvider
    final userAsync = ref.watch(profileUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(profileUserProvider),
        ),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('User not found'));
          }

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ModernAestheticProfileHeader(user: user),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: switch (user.role) {
                    UserRole.student => _StudentProfileView(user: user),
                    UserRole.teacher => _TeacherProfileView(user: user),
                    UserRole.admin => _AdminProfileView(user: user),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODERN AESTHETIC HEADER
// -----------------------------------------------------------------------------

class _ModernAestheticProfileHeader extends ConsumerWidget {
  final UserAccount user;
  const _ModernAestheticProfileHeader({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.tertiary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.primary,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 60),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            user.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Text(
            user.role.label.toUpperCase(),
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// STUDENT PROFILE
// -----------------------------------------------------------------------------

class _StudentProfileView extends StatelessWidget {
  final UserAccount user;
  const _StudentProfileView({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AttendanceSummaryCard(),
        const SizedBox(height: 24),
        _ModernInfoCard(
          title: 'Personal Information',
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(label: 'Email', value: user.email ?? 'Not provided'),
            _InfoRow(label: 'Phone Number', value: user.phone),
            _InfoRow(label: 'Gender', value: user.gender ?? 'Not Specified'),
            if (user.dateOfBirth != null)
              _InfoRow(
                label: 'Date of Birth',
                value: DateFormat('dd MMMM yyyy').format(user.dateOfBirth!),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _ModernInfoCard(
          title: 'Academic Profile',
          icon: Icons.school_outlined,
          children: [
            _InfoRow(label: 'Course', value: user.course ?? 'Not Assigned'),
            _InfoRow(label: 'Semester', value: user.semester?.toString() ?? 'Not Assigned'),
            _InfoRow(label: 'College Roll No', value: user.collegeRollNo ?? 'N/A'),
            _InfoRow(label: 'Exam Roll No', value: user.examRollNo ?? 'N/A'),
          ],
        ),
        const SizedBox(height: 24),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 60),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TEACHER PROFILE
// -----------------------------------------------------------------------------

class _TeacherProfileView extends StatelessWidget {
  final UserAccount user;
  const _TeacherProfileView({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModernInfoCard(
          title: 'Personal Information',
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(label: 'Email', value: user.email ?? 'Not provided'),
            _InfoRow(label: 'Phone Number', value: user.phone),
            _InfoRow(label: 'Gender', value: user.gender ?? 'Not Specified'),
          ],
        ),
        const SizedBox(height: 24),
        _QualificationsCard(user: user),
        const SizedBox(height: 24),
        _SubjectsSummaryCard(),
        const SizedBox(height: 24),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 60),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ADMIN PROFILE
// -----------------------------------------------------------------------------

class _AdminProfileView extends StatelessWidget {
  final UserAccount user;
  const _AdminProfileView({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AppSummaryCard(),
        const SizedBox(height: 24),
        _ModernInfoCard(
          title: 'Admin Details',
          icon: Icons.admin_panel_settings_outlined,
          children: [
            _InfoRow(label: 'Email', value: user.email ?? 'Not provided'),
            _InfoRow(label: 'Phone Number', value: user.phone),
            _InfoRow(label: 'Gender', value: user.gender ?? 'Not Specified'),
          ],
        ),
        const SizedBox(height: 24),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 60),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ATTENDANCE SUMMARY (STUDENT)
// -----------------------------------------------------------------------------

class _AttendanceSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStats = ref.watch(studentProfileStatsProvider);

    return _ModernInfoCard(
      title: 'Attendance Overview',
      icon: Icons.analytics_outlined,
      children: [
        asyncStats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AsyncErrorWidget(
            message: e.toString(),
            onRetry: () => ref.invalidate(studentProfileStatsProvider),
          ),
          data: (stats) {
            final threshold = ref.watch(settingsProvider).attendanceThreshold;
            final Color pctColor = stats.pct < threshold
                ? Colors.red
                : (stats.pct < threshold + 10 ? Colors.orange : Colors.green);

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatBlock(value: '${stats.pct}%', label: 'Health', color: pctColor, isLarge: true),
                Container(height: 40, width: 1, color: Theme.of(context).dividerColor),
                _StatBlock(value: stats.present.toString(), label: 'Attended'),
                Container(height: 40, width: 1, color: Theme.of(context).dividerColor),
                _StatBlock(value: stats.total.toString(), label: 'Total'),
              ],
            );
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TEACHER SUBJECT SUMMARY
// -----------------------------------------------------------------------------

class _SubjectsSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(teacherProfileSubjectsProvider);

    return _ModernInfoCard(
      title: 'Teaching Assignments',
      icon: Icons.class_outlined,
      padding: EdgeInsets.zero,
      children: [
        asyncData.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AsyncErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(teacherProfileSubjectsProvider)),
          data: (data) {
            if (data.subjects.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No subjects assigned yet.', style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.sections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: data.sections.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      )).toList(),
                    ),
                  ),
                  const Divider(),
                ],
                ...data.subjects.map((s) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.book_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(s.code),
                  trailing: Text('Sec: ${s.section}', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                )),
              ],
            );
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ADMIN APP SUMMARY
// -----------------------------------------------------------------------------

class _AppSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminProfileStatsProvider);

    return _ModernInfoCard(
      title: 'System Overview',
      icon: Icons.dashboard_outlined,
      children: [
        asyncData.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AsyncErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(adminProfileStatsProvider)),
          data: (data) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBlock(value: data.users.toString(), label: 'Users', color: Colors.blue),
              Container(height: 40, width: 1, color: Theme.of(context).dividerColor),
              _StatBlock(value: data.subjects.toString(), label: 'Subjects', color: Colors.purple),
              Container(height: 40, width: 1, color: Theme.of(context).dividerColor),
              _StatBlock(value: data.records.toString(), label: 'Records', color: Colors.teal),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// QUALIFICATIONS (TEACHER)
// -----------------------------------------------------------------------------

class _QualificationsCard extends ConsumerWidget {
  final UserAccount user;
  const _QualificationsCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModernInfoCard(
      title: 'Qualifications',
      icon: Icons.workspace_premium_outlined,
      padding: EdgeInsets.zero,
      children: [
        if (user.qualifications.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No qualifications added yet.', style: TextStyle(color: Colors.grey)),
          )
        else
          ...user.qualifications.map(
                (q) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text(q, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Manage Qualifications'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _EditQualificationsDialog(user: user),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// EDIT QUALIFICATIONS DIALOG
// -----------------------------------------------------------------------------

class _EditQualificationsDialog extends ConsumerStatefulWidget {
  final UserAccount user;
  const _EditQualificationsDialog({required this.user});

  @override
  ConsumerState<_EditQualificationsDialog> createState() => _EditQualificationsDialogState();
}

class _EditQualificationsDialogState extends ConsumerState<_EditQualificationsDialog> {
  late List<String> _quals;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quals = List.from(widget.user.qualifications);
  }

  void _add() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _quals.add(text);
        _ctrl.clear();
      });
    }
  }

  void _remove(int index) {
    setState(() => _quals.removeAt(index));
  }

  Future<void> _save() async {
    try {
      await ref.read(authRepoProvider).updateUser(
        widget.user.copyWith(qualifications: _quals),
      );

      if (!mounted) return;

      // ✅ FIX: Only pop the dialog and silently invalidate the profile provider.
      // This will visually update the page without hitting the GoRouter redirect!
      Navigator.pop(context);
      ref.invalidate(profileUserProvider);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Manage Qualifications', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_quals.isNotEmpty)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _quals.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      title: Text(_quals[i], style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                        onPressed: () => _remove(i),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: 'Add new qualification',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _add,
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SETTINGS + ACCOUNT ACTIONS
// -----------------------------------------------------------------------------

class _CommonSettingsSection extends ConsumerWidget {
  final UserAccount user;
  const _CommonSettingsSection({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModernInfoCard(
      title: 'Account Settings',
      icon: Icons.settings_outlined,
      padding: EdgeInsets.zero,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: const Icon(Icons.edit_note_rounded),
          title: const Text('Edit Bio & Phone', style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () async {
            await GoRouter.of(context).push('/profile/update');
            ref.invalidate(profileUserProvider);
          },
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: const Icon(Icons.lock_outline),
          title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () => _showChangePasswordDialog(context, ref, user.email ?? ''),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text(
            'Logout',
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
          ),
          onTap: () async {
            await ref.read(authRepoProvider).logout();
          },
        ),

        // 🔴 SECURITY FIX: Only show "Delete Account" if the user is an Admin
        if (user.role == UserRole.admin) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            title: Text(
              'Delete Account',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
            ),
            onTap: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _SecureDeleteDialog(user: user),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context, WidgetRef ref, String email) async {
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email found to reset password.')));
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Password'),
        content: Text('A password reset link will be sent to:\n\n$email'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(authRepoProvider).requestPasswordReset(email);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent!')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red));
              }
            },
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECURE DELETE DIALOG (FOR ADMINS ONLY)
// -----------------------------------------------------------------------------

class _SecureDeleteDialog extends ConsumerStatefulWidget {
  final UserAccount user;
  const _SecureDeleteDialog({required this.user});

  @override
  ConsumerState<_SecureDeleteDialog> createState() => _SecureDeleteDialogState();
}

class _SecureDeleteDialogState extends ConsumerState<_SecureDeleteDialog> {
  final TextEditingController _verifyCtrl = TextEditingController();
  bool _canDelete = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _verifyCtrl.addListener(() {
      setState(() => _canDelete = _verifyCtrl.text.trim() == 'DELETE');
    });
  }

  @override
  void dispose() {
    _verifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _executeDelete() async {
    if (!_canDelete) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(authRepoProvider).deleteCurrentUserAccount();
      await ref.read(authRepoProvider).logout();
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(Icons.warning_rounded, color: colorScheme.error, size: 48),
      title: const Text('Permanently Delete Account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This action is highly destructive and cannot be undone.', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          RichText(
            text: TextSpan(
              style: TextStyle(color: colorScheme.onSurface),
              children: const [
                TextSpan(text: 'To confirm, type '),
                TextSpan(text: 'DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: ' below:'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _verifyCtrl,
            enabled: !_isProcessing,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'DELETE',
              filled: true,
              fillColor: colorScheme.errorContainer.withValues(alpha: 0.2),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.error, width: 2), borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _isProcessing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _canDelete ? colorScheme.error : colorScheme.surfaceContainerHighest,
            foregroundColor: _canDelete ? colorScheme.onError : colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          onPressed: (_canDelete && !_isProcessing) ? _executeDelete : null,
          child: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Delete Permanently'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED UI WIDGETS
// -----------------------------------------------------------------------------

class _ModernInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _ModernInfoCard({
    required this.title,
    required this.icon,
    required this.children,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
          Padding(
            padding: padding,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  final bool isLarge;

  const _StatBlock({
    required this.value,
    required this.label,
    this.color,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isLarge ? 32 : 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}