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
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

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
  String? _batch;

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
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.refresh(directoryProvider),
        ),
        data: (data) {
          final me = data['me'] as UserAccount;
          final students = data['students'] as List<UserAccount>;
          final remarks = data['remarks'] as List<StudentRemark>;

          final p = context.palette;
          final batches = students.map((s) => s.section ?? '').where((b) => b.isNotEmpty).toSet().toList()..sort();
          final q = _query.toLowerCase();
          final filtered = students
              .where((s) =>
                  (_batch == null || s.section == _batch) &&
                  (q.isEmpty || s.name.toLowerCase().contains(q) || s.phone.contains(q) || (s.collegeRollNo ?? '').toLowerCase().contains(q)))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name or phone', isDense: true),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (batches.length > 1)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                child: filtered.isEmpty
                    ? const Center(child: EmptyNote(icon: Icons.person_search_outlined, text: 'No students match.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 32),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final student = filtered[index];
                          final studentRemarks = remarks.where((r) => r.studentId == student.id).toList();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(student.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                      Text(
                                        [
                                          if ((student.section ?? '').isNotEmpty) student.section!,
                                          if ((student.collegeRollNo ?? '').isNotEmpty) 'Roll ${student.collegeRollNo}',
                                        ].join(' · '),
                                        style: TextStyle(color: p.inkMuted, fontSize: 13),
                                      ),
                                      if (studentRemarks.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Wrap(spacing: 4, runSpacing: 4, children: [
                                          for (final r in studentRemarks) StatusPill(text: r.tag, color: p.accent, background: p.accentSoft),
                                        ]),
                                      ],
                                    ],
                                  ),
                                ),
                                if (student.phone.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Call',
                                    icon: Icon(Icons.call_outlined, color: p.inkMuted),
                                    onPressed: () => _launchUrl('tel:${student.phone}'),
                                  ),
                                if (me.role == UserRole.teacher)
                                  IconButton(
                                    tooltip: 'Add remark',
                                    icon: Icon(Icons.rate_review_outlined, color: p.inkMuted),
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
          final tags = ['Doing well', 'Needs help', 'Often absent', 'Often late'];

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add remark', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags.map((t) {
                    final isSel = selected == t;
                    return ChoiceChip(
                      label: Text(t),
                      selected: isSel,
                      showCheckmark: false,
                      onSelected: (v) => setState(() => selected = v ? t : null),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(labelText: 'Or write your own'),
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
          showMessage(context, 'Remark saved.', success: true);
        }
      }
    });
  }
}