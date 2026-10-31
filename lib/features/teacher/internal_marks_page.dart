// lib/features/teacher/internal_marks_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/user.dart';
import '../../core/models/subject.dart';
import '../../core/models/attendance.dart';
import '../../core/models/internal_marks.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../core/utils/firebase_error_parser.dart';

class SubjectGradingData {
  final UserAccount teacher;
  final Subject subject;
  final List<UserAccount> students;
  final Map<String, InternalMarks> marks;
  final Map<String, int> attendancePercentages;
  final bool isPublished;

  SubjectGradingData({
    required this.teacher,
    required this.subject,
    required this.students,
    required this.marks,
    required this.attendancePercentages,
    required this.isPublished,
  });
}


final subjectGradingProvider = FutureProvider.autoDispose.family<SubjectGradingData, String>((ref, subjectId) async {
  final authRepo = ref.read(authRepoProvider);
  final attRepo = ref.read(attendanceRepoProvider);
  final marksRepo = ref.read(internalMarksRepoProvider);
  final ttRepo = ref.read(timetableRepoProvider);

  final teacher = await authRepo.currentUser();
  if (teacher == null) throw Exception('Not logged in');

  final subject = await ttRepo.subjectById(subjectId);
  if (subject == null) throw Exception('Subject not found');

  final settings = await ref.watch(settingsFutureProvider.future);
  final students = await authRepo.studentsInSection(subject.section);
  final subjectAttendance = await attRepo.forSubject(subjectId);
  final existingMarks = await marksRepo.getMarksForSubject(subjectId);

  final marksMap = {for (var m in existingMarks) m.studentId: m};
  final attendancePercentages = <String, int>{};

  for (final student in students) {
    final studentRecords = subjectAttendance
        .where((r) => r.studentId == student.id)
        .toList();

    final total = studentRecords.length;
    final present = studentRecords
        .where((r) => r.status == AttendanceStatus.present || r.status == AttendanceStatus.excused)
        .length;
    final pct = total == 0 ? 100 : ((present * 100) / total).round();

    attendancePercentages[student.id] = pct;
    final calculatedAttMarks = settings.attendanceMarksFor(pct);

    if (marksMap.containsKey(student.id)) {
      final m = marksMap[student.id]!;
      marksMap[student.id] = m.copyWith(
        attendanceMarks: calculatedAttMarks.toDouble(),
        // FIXED: Explicitly calculate totalMarks instead of recalculateTotal()
        totalMarks: m.assignmentMarks + m.testMarks + calculatedAttMarks.toDouble(),
      );
    } else {
      marksMap[student.id] = InternalMarks.empty(
          subjectId: subjectId,
          studentId: student.id,
          teacherId: teacher.id
      ).copyWith(
        attendanceMarks: calculatedAttMarks.toDouble(),
        // FIXED: Explicitly calculate totalMarks instead of recalculateTotal()
        totalMarks: calculatedAttMarks.toDouble(),
      );
    }
  }

  // Uses native firstOrNull from Dart 3
  final isPublished = existingMarks.firstOrNull?.isVisibleToStudent ?? false;

  return SubjectGradingData(
    teacher: teacher,
    subject: subject,
    students: students..sort((a,b) => a.name.compareTo(b.name)),
    marks: marksMap,
    attendancePercentages: attendancePercentages,
    isPublished: isPublished,
  );
});

final teacherSubjectsProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) throw Exception('Not logged in');
  final allSubjects = await ref.watch(timetableRepoProvider).allSubjects();
  return allSubjects.where((s) => s.teacherId == user.id).toList()..sort((a,b) => a.name.compareTo(b.name));
});

class InternalMarksPage extends ConsumerStatefulWidget {
  const InternalMarksPage({super.key});

  @override
  ConsumerState<InternalMarksPage> createState() => _InternalMarksPageState();
}

class _InternalMarksPageState extends ConsumerState<InternalMarksPage> {
  String? _selectedSubjectId;

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(teacherSubjectsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Internal Marks'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: subjectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text(FirebaseErrorParser.getMessage(err)),
              data: (subjects) {
                if (subjects.isEmpty) {
                  return const Center(child: Text('You are not the lead teacher for any subjects.'));
                }

                return InputDecorator(
                  decoration: const InputDecoration(labelText: 'Subject'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSubjectId,
                      isExpanded: true,
                      hint: const Text('Select a subject to grade...'),
                      items: subjects.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.name} (${s.section})', overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (value) {
                        setState(() => _selectedSubjectId = value);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedSubjectId != null)
            Expanded(
              child: _GradingList(subjectId: _selectedSubjectId!),
            )
          else
            const Expanded(
              child: Center(child: Text('Please select a subject to continue.')),
            ),
        ],
      ),
    );
  }
}

class _GradingList extends ConsumerWidget {
  final String subjectId;
  const _GradingList({required this.subjectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(subjectGradingProvider(subjectId));

    return asyncData.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => AsyncErrorWidget(
        message: FirebaseErrorParser.getMessage(err),
        onRetry: () => ref.invalidate(subjectGradingProvider(subjectId)),
      ),
      data: (data) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SwitchListTile(
                title: const Text('Publish marks to students', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(data.isPublished ? 'Students can see these marks' : 'Marks are hidden'),
                value: data.isPublished,
                onChanged: (isVisible) async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isVisible ? 'Publish Marks?' : 'Hide Marks?'),
                      content: Text(isVisible
                          ? 'Are you sure you want to publish? Students will see their grades.'
                          : 'Are you sure you want to hide these marks?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isVisible ? 'Publish' : 'Hide')),
                      ],
                    ),
                  );

                  if (confirm != true) return;
                  await ref.read(internalMarksRepoProvider).publishMarksForSubject(subjectId, isVisible);
                  ref.invalidate(subjectGradingProvider(subjectId));
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: data.students.length,
                itemBuilder: (context, index) {
                  final student = data.students[index];
                  final marks = data.marks[student.id]!;
                  final attPct = data.attendancePercentages[student.id] ?? 0;

                  return _StudentMarkTile(
                    student: student,
                    marks: marks,
                    attendancePct: attPct,
                    onSave: (assignment, test) {
                      _saveMarks(
                        ref,
                        marks.copyWith(
                          assignmentMarks: assignment,
                          testMarks: test,
                          // FIXED: Calculate total inline
                          totalMarks: assignment + test + marks.attendanceMarks,
                          updatedAt: DateTime.now(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveMarks(WidgetRef ref, InternalMarks marks) async {
    await ref.read(internalMarksRepoProvider).updateMarks(marks, ref.read(settingsProvider));
    // UI FIX: Do NOT invalidate the provider here. This prevents the list from
    // rebuilding and stealing focus, allowing smooth continuous grading.
    if (ref.context.mounted) {
      ScaffoldMessenger.of(ref.context).showSnackBar(const SnackBar(
        content: Text('Saved Successfully'),
        duration: Duration(milliseconds: 1000),
      ));
    }
  }
}

class _StudentMarkTile extends ConsumerStatefulWidget {
  final UserAccount student;
  final InternalMarks marks;
  final int attendancePct;
  final Function(double assignment, double test) onSave;

  const _StudentMarkTile({
    required this.student,
    required this.marks,
    required this.attendancePct,
    required this.onSave,
  });

  @override
  ConsumerState<_StudentMarkTile> createState() => _StudentMarkTileState();
}

class _StudentMarkTileState extends ConsumerState<_StudentMarkTile> {
  final TextEditingController _assignmentCtrl = TextEditingController();
  final TextEditingController _testCtrl = TextEditingController();

  // Local state to keep UI updated without full rebuilds
  double _localTotal = 0;

  @override
  void initState() {
    super.initState();
    _localTotal = widget.marks.totalMarks;
    _updateControllers();
  }

  @override
  void didUpdateWidget(covariant _StudentMarkTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marks != widget.marks) {
      _localTotal = widget.marks.totalMarks;
      _updateControllers();
    }
  }

  void _updateControllers() {
    if (double.tryParse(_assignmentCtrl.text) != widget.marks.assignmentMarks) {
      _assignmentCtrl.text = widget.marks.assignmentMarks.toStringAsFixed(0);
    }
    if (double.tryParse(_testCtrl.text) != widget.marks.testMarks) {
      _testCtrl.text = widget.marks.testMarks.toStringAsFixed(0);
    }
  }

  void _onSavePressed() {
    FocusScope.of(context).unfocus();
    final scheme = ref.read(settingsProvider);
    final assign = (double.tryParse(_assignmentCtrl.text) ?? 0.0).clamp(0.0, scheme.assignmentMax);
    final test = (double.tryParse(_testCtrl.text) ?? 0.0).clamp(0.0, scheme.testMax);

    _assignmentCtrl.text = assign.toStringAsFixed(0);
    _testCtrl.text = test.toStringAsFixed(0);

    // Update local total instantly for the teacher
    setState(() {
      _localTotal = assign + test + widget.marks.attendanceMarks;
    });

    widget.onSave(assign, test);
  }

  @override
  void dispose() {
    _assignmentCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: CircleAvatar(
        child: Text(widget.student.name.isNotEmpty ? widget.student.name[0] : '?'),
      ),
      title: Text(widget.student.name),
      subtitle: Text('CR: ${widget.student.collegeRollNo ?? 'N/A'}'),
      trailing: Text(
        '${_localTotal.toStringAsFixed(0)} / ${ref.watch(settingsProvider).totalMarksMax.toStringAsFixed(0)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _MarkInput(label: 'Assignment', max: ref.watch(settingsProvider).assignmentMax.round(), controller: _assignmentCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _MarkInput(label: 'Test/PPT', max: ref.watch(settingsProvider).testMax.round(), controller: _testCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _MarkInput(
                      label: 'Attendance',
                      max: ref.watch(settingsProvider).attendanceMax.round(),
                      value: '${widget.marks.attendanceMarks.toStringAsFixed(0)} (${widget.attendancePct}%)',
                      isReadOnly: true
                  )),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _onSavePressed,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Marks'),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkInput extends StatelessWidget {
  final String label;
  final int max;
  final String? value;
  final bool isReadOnly;
  final TextEditingController? controller;

  const _MarkInput({
    required this.label,
    required this.max,
    this.value,
    this.isReadOnly = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: isReadOnly ? TextEditingController(text: value) : controller,
      readOnly: isReadOnly,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: '$label (/$max)',
        filled: true,
        isDense: true,
      ),
    );
  }
}