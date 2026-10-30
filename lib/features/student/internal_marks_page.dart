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
        title: const Text('Internal Marks'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(studentMarksProvider),
        ),
        data: (data) {
          if (data.groupedMarks.isEmpty) {
            return const Center(child: Text('No internal marks have been published yet.'));
          }

          final subjectIds = data.groupedMarks.keys.toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(studentMarksProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
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

                return Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          subjectName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...marksList.map((marks) {
                        return _MarkDetailsTile(
                          marks: marks,
                          teacherName: teacherName,
                        );
                      }),
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

class _MarkDetailsTile extends StatelessWidget {
  final InternalMarks marks;
  final String teacherName;

  const _MarkDetailsTile({required this.marks, required this.teacherName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grades by $teacherName', style: Theme.of(context).textTheme.titleSmall),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MarkItem(label: 'Assignment', value: marks.assignmentMarks, max: 12),
              _MarkItem(label: 'Test/Ppt', value: marks.testMarks, max: 12),
              _MarkItem(label: 'Attendance', value: marks.attendanceMarks, max: 6),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Total: ', style: Theme.of(context).textTheme.bodyMedium),
              Text(
                '${marks.totalMarks.toStringAsFixed(0)} / 30',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarkItem extends StatelessWidget {
  final String label;
  final double value;
  final int max;

  const _MarkItem({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(0),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          '$label (/$max)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}