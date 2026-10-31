// lib/features/admin/user_management_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/models/institution_settings.dart';
import '../../data/settings_repository.dart';
import '../../core/utils/login_id.dart';
import '../../core/utils/phone.dart';
import '../../main.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../common/widgets/class_card.dart' show EmptyNote;

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final allUsersProvider = FutureProvider.autoDispose<List<UserAccount>>((ref) async {
  return ref.watch(authRepoProvider).allUsers();
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------
class UserManagementPage extends ConsumerStatefulWidget {
  final bool addStudentOnOpen;
  const UserManagementPage({super.key, this.addStudentOnOpen = false});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> with SingleTickerProviderStateMixin {
  String _query = '';
  bool _openedAddOnce = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Add listener to rebuild when tab changes
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.addStudentOnOpen && !_openedAddOnce) {
      _openedAddOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAddDialog(initialRole: UserRole.student);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncUsers = ref.watch(allUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name, phone or email',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(text: 'All'),
                    Tab(text: 'Students'),
                    Tab(text: 'Teachers'),
                    Tab(text: 'Admins'),
                  ],
                ),
              ],
            ),
          ),

          // --- USER LIST ---
          Expanded(
            child: asyncUsers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => AsyncErrorWidget(
                message: FirebaseErrorParser.getMessage(err),
                onRetry: () => ref.invalidate(allUsersProvider),
              ),
              data: (users) {
                final filtered = users.where((u) {
                  final matchesSearch = u.name.toLowerCase().contains(_query.toLowerCase()) ||
                      (u.email?.contains(_query) ?? false) ||
                      u.phone.contains(_query) ||
                      (u.collegeRollNo?.toLowerCase().contains(_query.toLowerCase()) ?? false);

                  if (!matchesSearch) return false;

                  switch (_tabController.index) {
                    case 1: return u.role == UserRole.student;
                    case 2: return u.role == UserRole.teacher;
                    case 3: return (u.role == UserRole.admin || u.isAdmin);
                    default: return true;
                  }
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: EmptyNote(icon: Icons.person_search_outlined, text: 'No users match.'));
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(allUsersProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 104),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => FadeSlideIn(
                      index: index,
                      child: _UserCard(user: filtered[index], onEdit: () => _showEditDialog(filtered[index])),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add user'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOG LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _showAddDialog({UserRole? initialRole}) async {
    final newId = const Uuid().v4();
    final newUser = UserAccount(
      id: newId,
      role: initialRole ?? UserRole.student,
      name: '',
      email: '',
      phone: '',
      createdAt: DateTime.now(),
      isActive: true,
    );
    await _showEditDialog(newUser, isNew: true);
  }

  Future<void> _showEditDialog(UserAccount u, {bool isNew = false}) async {
    final form = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: u.name);
    // Mobile-number logins use an internal address; don't show it as an email.
    // Leaving the field empty keeps it (copyWith ignores null).
    final emailCtrl = TextEditingController(text: LoginId.isPhoneLogin(u.email) ? '' : u.email);
    final phoneCtrl = TextEditingController(text: u.phone);
    final parentNameCtrl = TextEditingController(text: u.parentName);
    final parentPhoneCtrl = TextEditingController(text: u.parentPhone);
    final collegeCtrl = TextEditingController(text: u.collegeRollNo);
    final examCtrl = TextEditingController(text: u.examRollNo);
    final passCtrl = TextEditingController();

    final settings = ref.read(settingsProvider);
    final isCollege = settings.type == InstitutionType.college;
    // Include the user's current group even if it was removed from settings.
    final groups = <String>{...settings.groups, if (u.section?.isNotEmpty == true) u.section!}.toList();
    String? section = u.section?.isNotEmpty == true ? u.section : (groups.isNotEmpty ? groups.first : null);
    final sectionCtrl = TextEditingController(text: section ?? '');
    int? year = u.year;
    UserRole role = u.role;
    bool adminPrivilege = u.isAdmin;

    final updated = await showDialog<UserAccount>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isNew ? 'Add user' : u.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      _buildSectionHeader('Basics'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<UserRole>(
                              initialValue: role,
                              items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                              onChanged: (v) => setState(() => role = v!),
                              decoration: _buildInputDecoration('Role', Icons.badge_rounded),
                            ),
                          ),
                          if (role == UserRole.teacher) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Admin access', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                value: adminPrivilege,
                                onChanged: (bool value) {
                                  setState(() => adminPrivilege = value);
                                },
                              ),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: _buildInputDecoration('Full name', Icons.person_rounded),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: _buildInputDecoration('Email (optional)', Icons.email_rounded),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final email = v?.trim() ?? '';
                          if (email.isNotEmpty && !email.contains('@')) return 'Enter a valid email';
                          if (isNew && email.isEmpty && PhoneNumber.normalize(phoneCtrl.text) == null) {
                            return 'Email or mobile number is needed to sign in';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: _buildInputDecoration('Mobile number', Icons.phone_rounded),
                      ),

                      if (isNew) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader('Sign-in'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passCtrl,
                          decoration: _buildInputDecoration('Password', Icons.lock_rounded),
                          obscureText: true,
                          validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
                        ),
                      ],

                      if (role == UserRole.student) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader('Parent'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: parentNameCtrl, decoration: _buildInputDecoration('Parent name', Icons.family_restroom_rounded))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: parentPhoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: _buildInputDecoration('Parent WhatsApp no.', Icons.phone_android_rounded),
                                validator: (v) => (v == null || v.trim().isEmpty || PhoneNumber.normalize(v) != null)
                                    ? null
                                    : 'Enter a valid mobile number',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Enrolment'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: collegeCtrl, decoration: _buildInputDecoration(isCollege ? 'College roll no.' : 'Roll no. (optional)', Icons.tag_rounded))),
                            if (isCollege) ...[
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: examCtrl, decoration: _buildInputDecoration('Exam roll no.', Icons.numbers_rounded))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (isCollege) ...[
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: year,
                                  items: [1, 2, 3, 4, 5].map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
                                  onChanged: (v) => year = v,
                                  decoration: _buildInputDecoration('Year', Icons.calendar_today_rounded),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: groups.isEmpty
                                  // No groups configured yet: let the admin type one.
                                  ? TextFormField(
                                      controller: sectionCtrl,
                                      decoration: _buildInputDecoration(settings.groupLabel, Icons.grid_view_rounded),
                                      onChanged: (v) => section = v.trim(),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                    )
                                  : DropdownButtonFormField<String>(
                                      initialValue: section,
                                      items: groups.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                      onChanged: (v) => section = v,
                                      decoration: _buildInputDecoration(settings.groupLabel, Icons.grid_view_rounded),
                                      validator: (v) => v == null ? 'Required' : null,
                                    ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 32),

                      Row(
                        children: [
                          if (!isNew)
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: context.palette.danger),
                              onPressed: () {
                                Navigator.pop(context);
                                _confirmDeleteUser(u);
                              },
                              child: const Text('Delete'),
                            ),
                          const Spacer(),
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () {
                              if (!form.currentState!.validate()) return;
                              Navigator.pop(
                                context,
                                u.copyWith(
                                  role: role,
                                  isAdmin: adminPrivilege,
                                  name: nameCtrl.text.trim(),
                                  email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim(),
                                  collegeRollNo: collegeCtrl.text.trim().isEmpty ? null : collegeCtrl.text.trim(),
                                  examRollNo: examCtrl.text.trim().isEmpty ? null : examCtrl.text.trim(),
                                  section: role == UserRole.student ? section : null,
                                  year: role == UserRole.student ? year : null,
                                  parentName: role == UserRole.student ? parentNameCtrl.text.trim() : null,
                                  parentPhone: role == UserRole.student ? parentPhoneCtrl.text.trim() : null,
                                ),
                              );
                            },
                            child: Text(isNew ? 'Create' : 'Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (updated != null) {
      try {
        if (mounted) showMessage(context, isNew ? 'Creating account…' : 'Saving…');
        if (isNew) {
          // No email: the student signs in with their mobile number.
          final login = updated.email?.isNotEmpty == true ? updated.email! : LoginId.toEmail(updated.phone);
          await ref.read(authRepoProvider).createAccount(updated.copyWith(email: login), passCtrl.text);
        } else {
          await ref.read(authRepoProvider).updateUser(updated);
        }
        if (!mounted) return;
        showMessage(context, isNew ? 'Account created. They can sign in now.' : 'Saved.', success: true);
      } catch (e) {
        if (!mounted) return;
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
      ref.invalidate(allUsersProvider);
    }
  }

  Widget _buildSectionHeader(String title) => SectionLabel(title, padding: const EdgeInsets.only(top: 12));

  // [icon] is kept for call-site readability but not drawn: labels are enough.
  InputDecoration _buildInputDecoration(String label, IconData icon) => InputDecoration(labelText: label);

  Future<void> _confirmDeleteUser(UserAccount user) async {
    final bool? deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdminSecureDeleteDialog(user: user),
    );
    if (deleted == true) ref.invalidate(allUsersProvider);
  }
}

class _UserCard extends StatelessWidget {
  final UserAccount user;
  final VoidCallback onEdit;

  const _UserCard({required this.user, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isAdmin = user.isAdmin || user.role == UserRole.admin;
    final login = LoginId.isPhoneLogin(user.email) ? user.phone : (user.email ?? user.phone);
    final (String roleText, Color fg, Color bg) = isAdmin
        ? ('Admin', p.accent, p.accentSoft)
        : user.role == UserRole.teacher
            ? ('Teacher', p.ink, p.surfaceRaised)
            : ('Student', p.inkMuted, p.surface);

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    [login, if (user.role == UserRole.student && (user.section ?? '').isNotEmpty) user.section!].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.inkMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(text: roleText, color: fg, background: bg),
          ],
        ),
      ),
    );
  }
}

class _AdminSecureDeleteDialog extends ConsumerStatefulWidget {
  final UserAccount user;
  const _AdminSecureDeleteDialog({required this.user});

  @override
  ConsumerState<_AdminSecureDeleteDialog> createState() => _AdminSecureDeleteDialogState();
}

class _AdminSecureDeleteDialogState extends ConsumerState<_AdminSecureDeleteDialog> {
  final TextEditingController _verifyCtrl = TextEditingController();
  bool _canDelete = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _verifyCtrl.addListener(() {
      if (mounted) setState(() => _canDelete = _verifyCtrl.text.trim() == 'DELETE');
    });
  }

  @override
  void dispose() {
    _verifyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text('Delete ${widget.user.name}?'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Their sign-in and profile are removed. Past attendance and marks stay in your records. This can\'t be undone.',
              style: TextStyle(color: p.inkMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _verifyCtrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
          onPressed: _canDelete && !_isProcessing ? _executeDelete : null,
          child: _isProcessing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete'),
        ),
      ],
    );
  }

  Future<void> _executeDelete() async {
    setState(() => _isProcessing = true);
    try {
      await ref.read(authRepoProvider).deleteAccount(widget.user.id);
      if (mounted) {
        Navigator.pop(context, true);
        showMessage(context, 'Account deleted.', success: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}