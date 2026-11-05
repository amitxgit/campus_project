// lib/features/assignments/assignments_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/assignment.dart';
import '../../core/models/role.dart';
import '../../core/models/subject.dart';
import '../../main.dart';
import 'assignment_detail_page.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';
import '../common/widgets/async_error_widget.dart';

// -----------------------------------------------------------------------------
// PROVIDERS
// -----------------------------------------------------------------------------
final teacherSubjectsProvider = FutureProvider.autoDispose<List<Subject>>((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null || user.role != UserRole.teacher) return [];

  final ttRepo = ref.watch(timetableRepoProvider);
  final allSubjects = await ttRepo.allSubjects();
  final allEntries = await ttRepo.allEntries();

  // Find subject IDs where this teacher is assigned in the timetable
  final myTimetableSubjectIds = allEntries
      .where((e) => e.teacherIds.contains(user.id))
      .map((e) => e.subjectId)
      .toSet();

  return allSubjects.where((s) => s.teacherId == user.id || myTimetableSubjectIds.contains(s.id)).toList();
});

final assignmentsProvider = FutureProvider.autoDispose<List<Assignment>>((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) return [];

  final repo = ref.watch(assignmentRepoProvider);

  if (user.role == UserRole.student) {
    final section = user.section;
    if (section == null || section.isEmpty) return [];
    return repo.forSection(section);
  }

  final all = await repo.recent();
  if (user.role == UserRole.teacher) {
    // Assignments the teacher created, plus any for subjects they teach.
    final mySubjectIds = (await ref.watch(teacherSubjectsProvider.future)).map((s) => s.id).toSet();
    return all.where((a) => a.teacherId == user.id || mySubjectIds.contains(a.subjectId)).toList();
  }

  // Admin sees everything
  return all;
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------
class AssignmentsPage extends ConsumerWidget {
  const AssignmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAssignments = ref.watch(assignmentsProvider);
    final userAsync = ref.watch(authStateProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Assignments')),
      body: asyncAssignments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(assignmentsProvider),
        ),
        data: (assignments) {
          if (assignments.isEmpty) {
            return const Center(child: EmptyNote(icon: Icons.assignment_outlined, text: 'No assignments yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(assignmentsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
              itemCount: assignments.length,
              itemBuilder: (ctx, i) {
                final a = assignments[i];
                return FadeSlideIn(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Pressable(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentDetailPage(assignment: a))),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('d').format(a.dueDate),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.6,
                                      height: 1.1,
                                      color: a.isOverdue ? p.danger : p.ink,
                                    ),
                                  ),
                                  Text(DateFormat('MMM').format(a.dueDate),
                                      style: TextStyle(fontSize: 12, color: p.inkMuted, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text('${a.subjectName} · ${a.section}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: p.inkMuted, fontSize: 13)),
                                ],
                              ),
                            ),
                            if (a.isOverdue) ...[
                              const SizedBox(width: 8),
                              StatusPill(text: 'Past due', color: p.danger, background: p.dangerSoft),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: userAsync.maybeWhen(
        data: (user) {
          if (user != null && user.role == UserRole.teacher) {
            return FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context, ref, user.id),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New assignment'),
            );
          }
          return null;
        },
        orElse: () => null,
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String teacherId) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateAssignmentDialog(teacherId: teacherId),
    );
  }
}

// -----------------------------------------------------------------------------
// DIALOG: CREATE ASSIGNMENT
// -----------------------------------------------------------------------------
class _CreateAssignmentDialog extends ConsumerStatefulWidget {
  final String teacherId;
  const _CreateAssignmentDialog({required this.teacherId});

  @override
  ConsumerState<_CreateAssignmentDialog> createState() => _CreateAssignmentDialogState();
}

class _CreateAssignmentDialogState extends ConsumerState<_CreateAssignmentDialog> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  Subject? selectedSubject;
  DateTime dueDate = DateTime.now().add(const Duration(days: 7));
  bool isLoading = false;

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    // Due at the end of the chosen day.
    setState(() => dueDate = DateTime(date.year, date.month, date.day, 23, 59));
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(teacherSubjectsProvider);
    final p = context.palette;

    return AlertDialog(
      title: const Text('New assignment'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            subjectsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => const Text('Failed to load subjects'),
              data: (subjects) {
                if (subjects.isEmpty) {
                  return Text('You have no subjects yet. Ask the office to assign you one.', style: TextStyle(color: p.danger));
                }
                return DropdownButtonFormField<Subject>(
                  decoration: const InputDecoration(labelText: 'Subject'),
                  initialValue: selectedSubject,
                  items: subjects.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s.name} · ${s.section}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (val) => setState(() => selectedSubject = val),
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title')
            ),
            const SizedBox(height: 16),
            TextField(
                controller: descCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Instructions', alignLabelWithHint: true)
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Due ${DateFormat('EEE, MMM d').format(dueDate)}'),
              trailing: TextButton(onPressed: _pickDueDate, child: const Text('Change')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Assign'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (selectedSubject == null || titleCtrl.text.isEmpty) {
      showMessage(context, 'Pick a subject and add a title.', error: true);
      return;
    }

    setState(() => isLoading = true);
    try {
      await ref.read(assignmentRepoProvider).create(Assignment(
        id: '',
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        teacherId: widget.teacherId,
        subjectId: selectedSubject!.id,
        subjectName: selectedSubject!.name,
        section: selectedSubject!.section,
        dueDate: dueDate,
        createdAt: DateTime.now(),
      ));

      ref.invalidate(assignmentsProvider);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Assignment posted.', success: true);
      }
    } catch (e) {
      if (mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
}