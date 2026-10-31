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
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/class_card.dart' show EmptyNote;

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
  String? _batch;

  @override
  Widget build(BuildContext context) {
    final asyncUsers = ref.watch(allUsersProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reset passwords'),
          bottom: const TabBar(tabs: [Tab(text: 'Students'), Tab(text: 'Teachers'), Tab(text: 'Admins')]),
          actions: const [ProfileAvatarAction()],
        ),
        drawer: const AppDrawer(),
        body: asyncUsers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorWidget(
            message: FirebaseErrorParser.getMessage(err),
            onRetry: () => ref.invalidate(allUsersProvider),
          ),
          data: (users) {
            // Grouped by batch rather than college year, so every institute
            // type finds its students.
            final students = users.where((u) => u.role == UserRole.student).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            final batches = students.map((u) => u.section ?? '').where((b) => b.isNotEmpty).toSet().toList()..sort();
            final teachers = users.where((u) => u.role == UserRole.teacher).toList()..sort((a, b) => a.name.compareTo(b.name));
            final admins = users.where((u) => u.role == UserRole.admin).toList()..sort((a, b) => a.name.compareTo(b.name));

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search name, phone or email',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      Column(children: [
                        if (batches.length > 1)
                          SizedBox(
                            height: 48,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              children: [
                                for (final b in <String?>[null, ...batches])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(b ?? 'All'),
                                      selected: _batch == b,
                                      showCheckmark: false,
                                      onSelected: (_) => setState(() => _batch = b),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: _ResetList(
                            list: _filter(students.where((u) => _batch == null || u.section == _batch).toList()),
                            onReset: _resetPassword,
                          ),
                        ),
                      ]),
                      _ResetList(list: _filter(teachers), onReset: _resetPassword),
                      _ResetList(list: _filter(admins), onReset: _resetPassword),
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
      showMessage(context, '${user.name} has no email or mobile login.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset ${user.name}\'s password?'),
        content: Text('A reset link goes to ${user.email}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await ref.read(authRepoProvider).requestPasswordReset(user.email!);
        if (!context.mounted) return;
        showMessage(context, 'Reset link sent.', success: true);
      } catch (e) {
        if (!context.mounted) return;
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
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
              decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 6 characters'),
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
        showMessage(context, 'Password updated. Share it with ${user.name}.', success: true);
      }
    } catch (e) {
      if (context.mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
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
    final p = context.palette;
    if (list.isEmpty) {
      return const Center(child: EmptyNote(icon: Icons.person_search_outlined, text: 'No one here.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final u = list[i];
        final login = LoginId.isPhoneLogin(u.email) ? u.phone : (u.email ?? u.phone);
        return InkWell(
          onTap: () => onReset(context, u),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      [login, if ((u.section ?? '').isNotEmpty) u.section!].join(' · '),
                      style: TextStyle(color: p.inkMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.key_outlined, color: p.inkMuted, size: 20),
            ]),
          ),
        );
      },
    );
  }
}
