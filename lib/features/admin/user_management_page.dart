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
import '../../main.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Directory Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => ref.invalidate(allUsersProvider),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // --- PREMIUM HEADER & SEARCH ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  isDark ? colorScheme.tertiary.withValues(alpha: 0.6) : colorScheme.tertiary.withValues(alpha: 0.8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or roll no...',
                    hintStyle: const TextStyle(color: Colors.black54),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.black54),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.95),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: Colors.white70,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  tabs: const [
                    Tab(text: '  All Users  '),
                    Tab(text: '  Students  '),
                    Tab(text: '  Faculty  '),
                    Tab(text: '  Admins  '),
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
                message: err.toString(),
                onRetry: () => ref.invalidate(allUsersProvider),
              ),
              data: (users) {
                final filtered = users.where((u) {
                  final matchesSearch = u.name.toLowerCase().contains(_query.toLowerCase()) ||
                      (u.email?.contains(_query) ?? false) ||
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
                  return _buildEmptyState(colorScheme);
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final u = filtered[index];
                    return _UserCard(
                      user: u,
                      onEdit: () => _showEditDialog(u),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add User', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_rounded, size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          const Text('No users found matching your criteria', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
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
    final emailCtrl = TextEditingController(text: u.email);
    final phoneCtrl = TextEditingController(text: u.phone);
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
          final colorScheme = Theme.of(context).colorScheme;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                      Text(isNew ? 'Create New Profile' : 'Edit User Profile', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 24),

                      _buildSectionHeader(colorScheme, 'Basic Information'),
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
                                title: const Text('Admin Access', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                        decoration: _buildInputDecoration('Full Name', Icons.person_rounded),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: _buildInputDecoration('Email Address', Icons.email_rounded),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => isNew && (v == null || !v.contains('@')) ? 'Email is required to sign in' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: _buildInputDecoration('Phone Number', Icons.phone_rounded),
                      ),

                      if (isNew) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(colorScheme, 'Security Credentials'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passCtrl,
                          decoration: _buildInputDecoration('Initial Password', Icons.lock_rounded),
                          obscureText: true,
                          validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
                        ),
                      ],

                      if (role == UserRole.student) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(colorScheme, 'Academic Records'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: collegeCtrl, decoration: _buildInputDecoration(isCollege ? 'College Roll' : 'Roll / Enrolment No.', Icons.tag_rounded))),
                            if (isCollege) ...[
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: examCtrl, decoration: _buildInputDecoration('Exam Roll', Icons.numbers_rounded))),
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
                                  decoration: _buildInputDecoration('Current Year', Icons.calendar_today_rounded),
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
                            IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _confirmDeleteUser(u);
                              },
                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                            ),
                          const Spacer(),
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          const SizedBox(width: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                                ),
                              );
                            },
                            child: const Text('Apply Changes'),
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
        if (isNew) {
          await ref.read(authRepoProvider).createAccount(updated, passCtrl.text);
        } else {
          await ref.read(authRepoProvider).updateUser(updated);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isNew ? 'Account created. They can now sign in.' : 'Profile updated.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
        );
      }
      ref.invalidate(allUsersProvider);
    }
  }

  Widget _buildSectionHeader(ColorScheme colors, String title) {
    return Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: colors.primary, letterSpacing: 1));
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color badgeColor;
    switch (user.role) {
      case UserRole.admin: badgeColor = Colors.teal; break;
      case UserRole.teacher: badgeColor = colorScheme.primary; break;
      case UserRole.student: badgeColor = colorScheme.secondary; break;
    }
    if (user.isAdmin) badgeColor = Colors.deepOrange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: badgeColor.withValues(alpha: 0.1),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          _buildRoleBadge(badgeColor, user.isAdmin ? 'ADMIN' : user.role.label.toUpperCase()),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(user.email ?? user.phone, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                      if (user.role == UserRole.student && user.collegeRollNo != null) ...[
                        const SizedBox(height: 4),
                        Text('Roll: ${user.collegeRollNo} • Sec: ${user.section}',
                            style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                      ]
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 48),
      title: const Text('Permanent Deletion', style: TextStyle(fontWeight: FontWeight.w900)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Confirm deletion for ${widget.user.name}. All records will be removed from Directory Service.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const Text('Type DELETE to confirm', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 8),
          TextField(
            controller: _verifyCtrl,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.errorContainer.withValues(alpha: 0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.error)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
          onPressed: _canDelete && !_isProcessing ? _executeDelete : null,
          child: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Delete Permanently'),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account purged successfully.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red));
      }
    }
  }
}