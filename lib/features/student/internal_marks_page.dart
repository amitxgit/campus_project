// lib/features/student/internal_marks_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart'; // For groupBy

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/internal_marks.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../main.dart';
import '../../data/settings_repository.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

// Provider to fetch all data needed for this page
final studentMarksProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) throw Exception('Not logged in');

  final marksRepo = ref.read(internalMarksRepoProvider);
  final ttRepo = ref.read(timetableRepoProvider);
  final authRepo = ref.read(authRepoProvider);

  // Fetch all data in parallel
  final results = await Future.wait([
    marksRepo.getVisibleMarksForStudent(user.id),
    ttRepo.allSubjects(),
    authRepo.allTeachers(), // To get teacher names
  ]);

  final marks = results[0] as List<InternalMarks>;
  final subjects = results[1] as List<Subject>;
  final users = results[2] as List<UserAccount>;

  // FIX: Map ID -> Subject Object (so we can access subject.teacherId later)
  final subjectsMap = {for (var s in subjects) s.id: s};
  final teachersMap = {for (var u in users) u.id: u.name};

  // Group marks by subject
  final groupedMarks = groupBy(marks, (InternalMarks m) => m.subjectId);

  return (
  groupedMarks: groupedMarks,
  subjectsMap: subjectsMap,
  teachersMap: teachersMap
  );
});

class InternalMarksPage extends ConsumerWidget {
  const InternalMarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(studentMarksProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Internal marks'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(studentMarksProvider),
        ),
        data: (data) {
          if (data.groupedMarks.isEmpty) {
            return const Center(child: EmptyNote(icon: Icons.military_tech_outlined, text: 'Your internal marks will appear here once they are published.'));
          }

          final subjectIds = data.groupedMarks.keys.toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(studentMarksProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: subjectIds.length,
              itemBuilder: (context, index) {
                final subjectId = subjectIds[index];
                final marksList = data.groupedMarks[subjectId]!;

                // FIX: Get Subject object to retrieve Name and TeacherID
                final subject = data.subjectsMap[subjectId];
                final subjectName = subject?.name ?? 'Unknown Subject';

                // Get Teacher Name via Subject
                final teacherId = subject?.teacherId;
                final teacherName = data.teachersMap[teacherId] ?? 'Unknown Teacher';

                return FadeSlideIn(
                  index: index,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final marks in marksList)
                        _MarkDetailsTile(subjectName: subjectName, marks: marks, teacherName: teacherName),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _MarkDetailsTile extends ConsumerWidget {
  final String subjectName;
  final InternalMarks marks;
  final String teacherName;

  const _MarkDetailsTile({required this.subjectName, required this.marks, required this.teacherName});

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ref.watch(settingsProvider);
    final p = context.palette;
    final maxTotal = scheme.totalMarksMax;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subjectName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    Text(teacherName, style: TextStyle(fontSize: 13, color: p.inkMuted)),
                  ],
                ),
              ),
              Text.rich(TextSpan(children: [
                TextSpan(text: _fmt(marks.totalMarks), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                TextSpan(text: ' / ${_fmt(maxTotal)}', style: TextStyle(color: p.inkMuted, fontSize: 13)),
              ])),
            ],
          ),
          const SizedBox(height: 10),
          ProgressLine(value: maxTotal <= 0 ? 0 : marks.totalMarks / maxTotal, height: 4),
          const SizedBox(height: 8),
          Text(
            'Assignment ${_fmt(marks.assignmentMarks)}/${_fmt(scheme.assignmentMax)} · '
            'Test ${_fmt(marks.testMarks)}/${_fmt(scheme.testMax)} · '
            'Attendance ${_fmt(marks.attendanceMarks)}/${_fmt(scheme.attendanceMax)}',
            style: TextStyle(fontSize: 12, color: p.inkMuted),
          ),
        ],
      ),
    );
  }
}
