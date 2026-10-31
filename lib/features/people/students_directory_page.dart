// lib/features/people/students_directory_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/models/remark.dart';
import '../../main.dart';

// -------------------- PROVIDER --------------------
final directoryProvider = FutureProvider.autoDispose((ref) async {
  final authRepo = ref.watch(authRepoProvider);
  final me = await authRepo.currentUser();
  if (me == null) throw Exception('Not logged in');

  final allStudents = await authRepo.allStudents();

  List<StudentRemark> remarks = [];
  // Only fetch remarks if the user is a teacher
  if (me.role == UserRole.teacher) {
    final remarkRepo = ref.watch(remarkRepoProvider);
    remarks = await remarkRepo.forTeacher(me.id);
  }

  return {
    'me': me,
    'students': allStudents,
    'remarks': remarks,
  };
});

// =====================================================
//               STUDENTS DIRECTORY PAGE
// =====================================================

class StudentsDirectoryPage extends ConsumerStatefulWidget {
  const StudentsDirectoryPage({super.key});

  @override
  ConsumerState<StudentsDirectoryPage> createState() =>
      _StudentsDirectoryPageState();
}

class _StudentsDirectoryPageState extends ConsumerState<StudentsDirectoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(directoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.refresh(directoryProvider),
        ),
        data: (data) {
          final me = data['me'] as UserAccount;
          final students = data['students'] as List<UserAccount>;
          final remarks = data['remarks'] as List<StudentRemark>;

          final filtered = students.where((s) {
            final q = _query.toLowerCase();
            return s.name.toLowerCase().contains(q) ||
                (s.collegeRollNo ?? '').toLowerCase().contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name or roll number...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = filtered[index];
                    final studentRemarks =
                    remarks.where((r) => r.studentId == student.id).toList();

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(student.name.isNotEmpty ? student.name[0] : '?'),
                      ),
                      title: Text(student.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${student.section ?? "N/A"} • ${student.collegeRollNo ?? "No Roll"}'),
                          if (studentRemarks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 4,
                                children: studentRemarks
                                    .map((r) => Chip(
                                  label: Text(
                                    r.tag,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ))
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone),
                            onPressed: () => _launchUrl('tel:${student.phone}'),
                          ),
                          if (me.role == UserRole.teacher)
                            IconButton(
                              icon: const Icon(Icons.edit_note),
                              onPressed: () => _addRemark(context, ref, me.id, student.id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _addRemark(
      BuildContext context, WidgetRef ref, String teacherId, String studentId) async {
    final customCtrl = TextEditingController();
    String? selected;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final tags = ['Good Performance', 'Needs Improvement', 'Absentee', 'Late'];

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add Remark',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: tags.map((t) {
                    final isSel = selected == t;
                    return ChoiceChip(
                      label: Text(t),
                      selected: isSel,
                      onSelected: (v) => setState(() => selected = v ? t : null),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(labelText: 'Custom tag (optional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final custom = customCtrl.text.trim();
                        if (custom.isNotEmpty) {
                          selected = custom;
                        }
                        Navigator.pop(context, selected ?? '');
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 16), // Padding for bottom
              ],
            ),
          );
        },
      ),
    ).then((val) async {
      if (val != null && val is String && val.isNotEmpty) {
        await ref.read(remarkRepoProvider).upsertRemark(
            teacherId: teacherId, studentId: studentId, tag: val);
        ref.invalidate(directoryProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Remark saved')));
        }
      }
    });
  }
}