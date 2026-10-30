// lib/features/admin/reset_passwords_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/utils/login_id.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/async_error_widget.dart';

// DEFINED HERE TO FIX "Undefined name" ERROR
final allUsersProvider = FutureProvider.autoDispose<List<UserAccount>>((ref) async {
  return ref.watch(authRepoProvider).allUsers();
});

class ResetPasswordsPage extends ConsumerStatefulWidget {
  const ResetPasswordsPage({super.key});

  @override
  ConsumerState<ResetPasswordsPage> createState() => _ResetPasswordsPageState();
}

class _ResetPasswordsPageState extends ConsumerState<ResetPasswordsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final asyncUsers = ref.watch(allUsersProvider);

    const tabs = [
      Tab(text: '1st Year'),
      Tab(text: '2nd Year'),
      Tab(text: '3rd Year'),
      Tab(text: '4th Year'),
      Tab(text: 'Teachers'),
      Tab(text: 'Admins'),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: const Text('Reset Passwords'),
          bottom: const TabBar(isScrollable: true, tabs: tabs),
          actions: const [ProfileAvatarAction()],
        ),
        drawer: const AppDrawer(),
        body: asyncUsers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorWidget(
            // FIXED: Removed 'const' keyword
            message: err.toString(),
            onRetry: () => ref.invalidate(allUsersProvider),
          ),
          data: (users) {
            List<UserAccount> studentsByYear(int year) => users
                .where((u) => u.role == UserRole.student && u.year == year)
                .toList()
              ..sort((a, b) =>
                  (a.collegeRollNo ?? '').compareTo(b.collegeRollNo ?? ''));

            final teachers = users
                .where((u) => u.role == UserRole.teacher)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            final admins = users
                .where((u) => u.role == UserRole.admin)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name, roll, email, phone',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ResetList(
                        list: _filter(studentsByYear(1)),
                        onReset: _resetPassword,
                      ),
                      _ResetList(
                        list: _filter(studentsByYear(2)),
                        onReset: _resetPassword,
                      ),
                      _ResetList(
                        list: _filter(studentsByYear(3)),
                        onReset: _resetPassword,
                      ),
                      _ResetList(
                        list: _filter(studentsByYear(4)),
                        onReset: _resetPassword,
                      ),
                      _ResetList(
                        list: _filter(teachers),
                        onReset: _resetPassword,
                      ),
                      _ResetList(
                        list: _filter(admins),
                        onReset: _resetPassword,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  List<UserAccount> _filter(List<UserAccount> list) {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return list;

    return list.where((u) {
      return u.name.toLowerCase().contains(q) ||
          (u.collegeRollNo ?? '').toLowerCase().contains(q) ||
          (u.examRollNo ?? '').toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q) ||
          (u.email ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _resetPassword(BuildContext context, UserAccount user) async {
    // Mobile-number logins have no inbox, so set a new password directly.
    if (LoginId.isPhoneLogin(user.email)) {
      await _setPassword(context, user);
      return;
    }
    if (user.email == null || user.email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email available for this user')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset ${user.name}\'s password?'),
        content: Text('A password reset link will be sent to:\n${user.email}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await ref.read(authRepoProvider).requestPasswordReset(user.email!);
        // FIXED: Use context.mounted
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset link sent')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

extension on _ResetPasswordsPageState {
  Future<void> _setPassword(BuildContext context, UserAccount user) async {
    final ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New password for ${user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${user.name} signs in with mobile number ${LoginId.display(user.email)}.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'New password (min 6 characters)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Set password')),
        ],
      ),
    );
    if (password == null) return;
    try {
      await ref.read(authRepoProvider).setPassword(user.id, password);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password updated. Share it with ${user.name}.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e))));
      }
    }
  }
}

// -----------------------------------------------------------------------------
// RESET LIST
// -----------------------------------------------------------------------------

class _ResetList extends StatelessWidget {
  final List<UserAccount> list;
  final Future<void> Function(BuildContext, UserAccount) onReset;

  const _ResetList({
    required this.list,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Center(child: Text('No users found'));
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (_, i) {
        final u = list[i];
        final ids = [
          if (u.collegeRollNo != null) 'CR: ${u.collegeRollNo}',
          if (u.examRollNo != null) 'ER: ${u.examRollNo}',
        ].join(' • ');

        return ListTile(
          leading: const Icon(Icons.lock_reset),
          title: Text(u.name),
          subtitle: Text(
            '${u.role.label} • ${u.email ?? u.phone}'
                '${ids.isNotEmpty ? ' • $ids' : ''}',
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => onReset(context, u),
        );
      },
    );
  }
}