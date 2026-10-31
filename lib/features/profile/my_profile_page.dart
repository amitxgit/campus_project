// lib/features/profile/my_profile_page.dart
import 'package:flutter/material.dart';
import '../../core/utils/login_id.dart';
import '../../theme.dart';
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
import '../common/widgets/ui_kit.dart';

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
        title: const Text('Profile'),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(e),
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
                padding: EdgeInsets.zero,
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
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: p.ink,
            foregroundColor: p.background,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            [user.role.label, if (user.role == UserRole.student && (user.section ?? '').isNotEmpty) user.section!].join(' · '),
            style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500),
          ),
        ],
      ),
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
    String? v(String? x) => (x == null || x.trim().isEmpty) ? null : x;
    final enrolment = <_InfoRow>[
      if (v(user.section) != null) _InfoRow(label: 'Batch', value: user.section!),
      if (v(user.collegeRollNo) != null) _InfoRow(label: 'Roll no.', value: user.collegeRollNo!),
      if (v(user.course) != null) _InfoRow(label: 'Course', value: user.course!),
      if (user.semester != null) _InfoRow(label: 'Semester', value: '${user.semester}'),
      if (v(user.examRollNo) != null) _InfoRow(label: 'Exam roll no.', value: user.examRollNo!),
    ];
    return Column(
      children: [
        _AttendanceSummaryCard(),
        _ModernInfoCard(
          title: 'Contact',
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(label: 'Mobile', value: user.phone),
            if (!LoginId.isPhoneLogin(user.email) && v(user.email) != null) _InfoRow(label: 'Email', value: user.email!),
            if (v(user.gender) != null) _InfoRow(label: 'Gender', value: user.gender!),
            if (user.dateOfBirth != null) _InfoRow(label: 'Date of birth', value: DateFormat('d MMM yyyy').format(user.dateOfBirth!)),
          ],
        ),
        if (enrolment.isNotEmpty) _ModernInfoCard(title: 'Enrolment', icon: Icons.school_outlined, children: enrolment),
        if (v(user.parentName) != null || v(user.parentPhone) != null)
          _ModernInfoCard(
            title: 'Parent',
            icon: Icons.family_restroom_rounded,
            children: [
              if (v(user.parentName) != null) _InfoRow(label: 'Name', value: user.parentName!),
              if (v(user.parentPhone) != null) _InfoRow(label: 'Mobile', value: user.parentPhone!),
            ],
          ),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 48),
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
          title: 'Contact',
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(label: 'Mobile', value: user.phone),
            if (!LoginId.isPhoneLogin(user.email) && (user.email ?? '').isNotEmpty) _InfoRow(label: 'Email', value: user.email!),
            if ((user.gender ?? '').isNotEmpty) _InfoRow(label: 'Gender', value: user.gender!),
          ],
        ),
        _QualificationsCard(user: user),
        _SubjectsSummaryCard(),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 48),
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
        _ModernInfoCard(
          title: 'Contact',
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(label: 'Mobile', value: user.phone),
            if (!LoginId.isPhoneLogin(user.email) && (user.email ?? '').isNotEmpty) _InfoRow(label: 'Email', value: user.email!),
            if ((user.gender ?? '').isNotEmpty) _InfoRow(label: 'Gender', value: user.gender!),
          ],
        ),
        _CommonSettingsSection(user: user),
        const SizedBox(height: 48),
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
      title: 'Attendance',
      icon: Icons.analytics_outlined,
      children: [
        asyncStats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(FirebaseErrorParser.getMessage(e), style: TextStyle(color: context.palette.danger)),
          data: (stats) {
            final threshold = ref.watch(settingsProvider).attendanceThreshold;
            final p = context.palette;
            final tone = stats.pct < threshold ? p.danger : (stats.pct < threshold + 10 ? p.warning : p.success);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${stats.pct}%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: tone)),
                  const Spacer(),
                  Text('${stats.present} of ${stats.total} classes', style: TextStyle(color: p.inkMuted)),
                ]),
                const SizedBox(height: 10),
                ProgressLine(value: stats.pct / 100, color: tone),
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
      title: 'Teaching',
      icon: Icons.class_outlined,
      padding: EdgeInsets.zero,
      children: [
        asyncData.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: Text(FirebaseErrorParser.getMessage(e), style: TextStyle(color: context.palette.danger))),
          data: (data) {
            if (data.subjects.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No subjects assigned yet.'),
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
                        decoration: BoxDecoration(color: context.palette.accentSoft, borderRadius: BorderRadius.circular(8)),
                        child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.accent)),
                      )).toList(),
                    ),
                  ),
                ],
                ...data.subjects.map((s) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.code, style: TextStyle(color: context.palette.inkMuted)),
                  trailing: Text(s.section, style: TextStyle(fontWeight: FontWeight.w500, color: context.palette.inkMuted)),
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
      title: 'Institute',
      icon: Icons.dashboard_outlined,
      children: [
        asyncData.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(FirebaseErrorParser.getMessage(e), style: TextStyle(color: context.palette.danger)),
          data: (data) => Row(
            children: [
              _StatBlock(value: data.users.toString(), label: 'Users'),
              _StatBlock(value: data.subjects.toString(), label: 'Subjects'),
              _StatBlock(value: data.records.toString(), label: 'Attendance records'),
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
            child: Text('No qualifications added yet.'),
          )
        else
          ...user.qualifications.map(
                (q) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(q, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              child: const Text('Edit qualifications'),
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
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Qualifications'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_quals.isNotEmpty)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _quals.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      title: Text(_quals[i], style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.close_rounded, color: context.palette.inkMuted, size: 20),
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
                labelText: 'Add a qualification',
                hintText: 'e.g. M.Sc. Physics',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  color: context.palette.accent,
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
      title: 'Account',
      icon: Icons.settings_outlined,
      padding: EdgeInsets.zero,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: const Text('Edit details', style: TextStyle(fontWeight: FontWeight.w500)),
          trailing: Icon(Icons.chevron_right_rounded, color: context.palette.inkFaint),
          onTap: () async {
            await GoRouter.of(context).push('/profile/update');
            ref.invalidate(profileUserProvider);
          },
        ),
        Divider(height: 1, indent: 20, endIndent: 20, color: context.palette.line),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w500)),
          trailing: Icon(Icons.chevron_right_rounded, color: context.palette.inkFaint),
          onTap: () => _showChangePasswordDialog(context, ref, user.email ?? ''),
        ),
        Divider(height: 1, indent: 20, endIndent: 20, color: context.palette.line),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text('Sign out', style: TextStyle(color: context.palette.danger, fontWeight: FontWeight.w600)),
          onTap: () async {
            await ref.read(authRepoProvider).logout();
          },
        ),

        // 🔴 SECURITY FIX: Only show "Delete Account" if the user is an Admin
        if (user.role == UserRole.admin) ...[
          Divider(height: 1, indent: 20, endIndent: 20, color: context.palette.line),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Text('Delete my account', style: TextStyle(color: context.palette.danger, fontWeight: FontWeight.w500)),
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
    // Mobile-number logins use an internal address with no inbox, so a
    // reset link would go nowhere. The office sets a new password instead.
    if (email.isEmpty || LoginId.isPhoneLogin(email)) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change password'),
          content: const Text('You sign in with your mobile number. Ask the office to set a new password for you.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change password'),
        content: Text('We\'ll email a reset link to $email.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(authRepoProvider).requestPasswordReset(email);
                if (!context.mounted) return;
                Navigator.pop(context);
                showMessage(context, 'Reset link sent.', success: true);
              } catch (e) {
                if (!context.mounted) return;
                showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
              }
            },
            child: const Text('Send link'),
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
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You will be signed out and can\'t sign in again. This can\'t be undone.', style: TextStyle(color: p.inkMuted, height: 1.45)),
          const SizedBox(height: 16),
          TextField(
            controller: _verifyCtrl,
            enabled: !_isProcessing,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _isProcessing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
          onPressed: (_canDelete && !_isProcessing) ? _executeDelete : null,
          child: _isProcessing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED UI WIDGETS
// -----------------------------------------------------------------------------

/// Section label over a soft panel. [icon] is kept for call sites; the
/// label alone is enough.
class _ModernInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _ModernInfoCard({
    required this.title,
    required this.icon,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 4),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title, padding: const EdgeInsets.fromLTRB(20, 20, 20, 10)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ),
      ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(color: context.palette.inkMuted))),
          Expanded(
            flex: 3,
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;

  const _StatBlock({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: context.palette.inkMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
