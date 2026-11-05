// lib/features/admin/user_form_dialog.dart
import 'package:flutter/material.dart';

import '../../core/models/institution_settings.dart';
import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/utils/login_id.dart';
import '../../core/utils/phone.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';

/// What the Add/Edit user form returns. [password] is only set for new users.
typedef UserFormResult = ({UserAccount user, String password});

Widget _sectionHeader(String title) => SectionLabel(title, padding: const EdgeInsets.only(top: 12));

InputDecoration _input(String label, IconData icon) => InputDecoration(labelText: label);

/// The Add/Edit user form. Shared by Users and by Enquiries ("Convert to
/// student"), which passes a profile pre-filled from the enquiry.
Future<UserFormResult?> showUserFormDialog(
  BuildContext context,
  InstitutionSettings settings,
  UserAccount u, {
  bool isNew = false,
  VoidCallback? onDelete,
  // Students only: unlink the phone they check in from (new handset or a
  // reinstall). See lib/core/attendance/device_id.dart.
  VoidCallback? onResetPhoneLink,
}) async {
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
                    Text(isNew ? 'Add user' : u.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _sectionHeader('Basics'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<UserRole>(
                            initialValue: role,
                            items:
                                UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                            onChanged: (v) => setState(() => role = v!),
                            decoration: _input('Role', Icons.badge_rounded),
                          ),
                        ),
                        if (role == UserRole.teacher) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Admin access',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                      decoration: _input('Full name', Icons.person_rounded),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: _input('Email (optional)', Icons.email_rounded),
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
                      decoration: _input('Mobile number', Icons.phone_rounded),
                    ),
                    if (isNew) ...[
                      const SizedBox(height: 24),
                      _sectionHeader('Sign-in'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passCtrl,
                        decoration: _input('Password', Icons.lock_rounded),
                        obscureText: true,
                        validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
                      ),
                    ],
                    if (role == UserRole.student) ...[
                      const SizedBox(height: 24),
                      _sectionHeader('Parent'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: TextFormField(
                                  controller: parentNameCtrl,
                                  decoration: _input('Parent name', Icons.family_restroom_rounded))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: parentPhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: _input('Parent WhatsApp no.', Icons.phone_android_rounded),
                              validator: (v) => (v == null || v.trim().isEmpty || PhoneNumber.normalize(v) != null)
                                  ? null
                                  : 'Enter a valid mobile number',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader('Enrolment'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: TextFormField(
                                  controller: collegeCtrl,
                                  decoration: _input(
                                      isCollege ? 'College roll no.' : 'Roll no. (optional)', Icons.tag_rounded))),
                          if (isCollege) ...[
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextFormField(
                                    controller: examCtrl,
                                    decoration: _input('Exam roll no.', Icons.numbers_rounded))),
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
                                items: [1, 2, 3, 4, 5]
                                    .map((y) => DropdownMenuItem(value: y, child: Text('Year $y')))
                                    .toList(),
                                onChanged: (v) => year = v,
                                decoration: _input('Year', Icons.calendar_today_rounded),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: groups.isEmpty
                                // No groups configured yet: let the admin type one.
                                ? TextFormField(
                                    controller: sectionCtrl,
                                    decoration: _input(settings.groupLabel, Icons.grid_view_rounded),
                                    onChanged: (v) => section = v.trim(),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                  )
                                : DropdownButtonFormField<String>(
                                    initialValue: section,
                                    items: groups.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (v) => section = v,
                                    decoration: _input(settings.groupLabel, Icons.grid_view_rounded),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                          ),
                        ],
                      ),
                    ],
                    if (!isNew && role == UserRole.student && onResetPhoneLink != null) ...[
                      const SizedBox(height: 24),
                      _sectionHeader('Check-in phone'),
                      const SizedBox(height: 4),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.phonelink_erase_rounded),
                        title: const Text('Reset phone link'),
                        subtitle: const Text(
                            'Attendance can only be marked from the phone this student first checked in with. '
                            'Reset it if they changed phones or reinstalled the app.'),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onResetPhoneLink();
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        if (!isNew && onDelete != null)
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: context.palette.danger),
                            onPressed: () {
                              Navigator.pop(context);
                              onDelete();
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

  if (updated == null) return null;
  return (user: updated, password: passCtrl.text);
}

/// Creates the login and profile for a new user from the form. Users without
/// an email sign in with their mobile number. Returns the new uid.
Future<String> createUserFromForm(Future<String> Function(UserAccount, String) create, UserFormResult r) {
  final login = r.user.email?.isNotEmpty == true ? r.user.email! : LoginId.toEmail(r.user.phone);
  return create(r.user.copyWith(email: login), r.password);
}
