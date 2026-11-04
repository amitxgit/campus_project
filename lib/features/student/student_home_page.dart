// lib/features/student/student_home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/timetable_entry.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/models/attendance.dart';
import '../common/widgets/class_card.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../../main.dart';
import '../../data/settings_repository.dart';
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// VIEW MODELS
// -----------------------------------------------------------------------------
class StudentDashboardVM {
  final UserAccount student;
  final int attendancePct;
  final List<TimetableEntry> todaysClasses;
  final Set<String> cancelledEntryIds;
  final Map<String, Map<String, dynamic>> rescheduledEntries;
  final Map<String, Subject> subjectsMap;

  StudentDashboardVM({
    required this.student,
    required this.attendancePct,
    required this.todaysClasses,
    required this.cancelledEntryIds,
    required this.rescheduledEntries,
    required this.subjectsMap,
  });
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final studentDashboardProvider = FutureProvider.autoDispose<StudentDashboardVM>((ref) async {
  final authRepo = ref.watch(authRepoProvider);
  final ttRepo = ref.watch(timetableRepoProvider);
  final attRepo = ref.watch(attendanceRepoProvider);
  final db = FirebaseFirestore.instance;

  final student = await authRepo.currentUser();
  if (student == null) throw Exception('Not logged in');

  final section = student.section ?? '';

  final results = await Future.wait([
    ttRepo.allSubjects(),
    ttRepo.forSection(section),
    attRepo.forStudent(student.id),
  ]);

  final subjects = results[0] as List<Subject>;
  final rawEntries = results[1] as List<TimetableEntry>;
  final attendance = results[2] as List<AttendanceRecord>;

  final subjectMap = {for (final s in subjects) s.id: s};

  // Calculate Attendance %
  final presentCount = attendance.where((r) =>
  r.status == AttendanceStatus.present ||
      r.status == AttendanceStatus.late ||
      r.status == AttendanceStatus.excused).length;
  final total = attendance.length;
  final pct = total == 0 ? 100 : ((presentCount / total) * 100).round();

  // Fetch Overrides (Cancellations)
  final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final overridesSnap = await db.collection('timetable_overrides')
      .where('date', isEqualTo: todayDateStr)
      .where('section', isEqualTo: section)
      .get();

  final cancelledEntryIds = <String>{};
  final rescheduledEntries = <String, Map<String, dynamic>>{};

  for (var doc in overridesSnap.docs) {
    final data = doc.data();
    final entryId = data['entryId'] as String;
    if (data['isCancelled'] == true) {
      cancelledEntryIds.add(entryId);
    } else {
      rescheduledEntries[entryId] = data;
    }
  }

  // Filter for Today
  final todayNum = DateTime.now().weekday;
  final dayMap = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
  final todayStr = dayMap[todayNum] ?? 'Mon';

  // Need to normalize days if seeder used "1" instead of "Mon"
  final todaysClasses = rawEntries.where((e) {
    const seederMap = {'1': 'Mon', '2': 'Tue', '3': 'Wed', '4': 'Thu', '5': 'Fri', '6': 'Sat'};
    final safeDay = seederMap[e.dayOfWeek] ?? e.dayOfWeek;
    return safeDay == todayStr;
  }).toList();

  todaysClasses.sort((a, b) => a.startTime.compareTo(b.startTime));

  return StudentDashboardVM(
    student: student,
    attendancePct: pct,
    todaysClasses: todaysClasses,
    cancelledEntryIds: cancelledEntryIds,
    rescheduledEntries: rescheduledEntries,
    subjectsMap: subjectMap,
  );
});

// -----------------------------------------------------------------------------
// UI
// -----------------------------------------------------------------------------
class StudentHomePage extends ConsumerWidget {
  const StudentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(studentDashboardProvider);
    final settings = ref.watch(settingsProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.name),
        actions: const [ProfileAvatarAction()],
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(studentDashboardProvider),
        ),
        data: (vm) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(studentDashboardProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  [
                    DateFormat('EEEE, d MMMM').format(DateTime.now()),
                    if (vm.student.section?.isNotEmpty == true) vm.student.section!,
                  ].join('  ·  '),
                  style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Text('Hi, ${vm.student.name.split(' ').first}', style: Theme.of(context).textTheme.headlineMedium),
              ),
              FadeSlideIn(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _AttendanceCard(
                    pct: vm.attendancePct,
                    threshold: settings.attendanceThreshold,
                    onScan: () async {
                      await context.push('/student/check-in');
                      ref.invalidate(studentDashboardProvider);
                    },
                    onOpen: () => context.push('/student/attendance'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ActionGrid(
                aspectRatio: 1.25,
                children: [
                  ActionTile(label: 'Timetable', icon: Icons.calendar_month_outlined, onTap: () => context.push('/student/timetable')),
                  if (settings.testsEnabled)
                    ActionTile(label: 'Results', icon: Icons.emoji_events_outlined, onTap: () => context.push('/student/results')),
                  if (settings.feesEnabled)
                    ActionTile(label: 'Fees', icon: Icons.currency_rupee_rounded, onTap: () => context.push('/student/fees')),
                  if (settings.internalMarksEnabled)
                    ActionTile(label: 'Marks', icon: Icons.score_outlined, onTap: () => context.push('/student/internal-marks')),
                  ActionTile(label: 'Notices', icon: Icons.campaign_outlined, onTap: () => context.push('/notices')),
                  ActionTile(label: 'Ask a question', icon: Icons.help_outline_rounded, onTap: () => context.push('/student/raise-query')),
                ],
              ),
              const SectionLabel('Today'),
              if (vm.todaysClasses.isEmpty)
                const EmptyNote(icon: Icons.wb_sunny_outlined, text: 'No classes today')
              else
                for (var i = 0; i < vm.todaysClasses.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _studentClass(vm, vm.todaysClasses[i], settings.periodMinutes),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentClass(StudentDashboardVM vm, TimetableEntry entry, int minutes) {
    final reschedule = vm.rescheduledEntries[entry.id];
    final time = reschedule != null ? reschedule['newStartTime'] as String : entry.startTime;
    final room = reschedule != null ? reschedule['newRoom'] as String : entry.room;
    return ClassCard(
      startTime: time,
      durationMinutes: minutes,
      subject: vm.subjectsMap[entry.subjectId]?.name ?? 'Unknown subject',
      meta: ClassCard.roomLabel(room),
      cancelled: vm.cancelledEntryIds.contains(entry.id),
      rescheduled: reschedule != null,
    );
  }
}

// -----------------------------------------------------------------------------
// ATTENDANCE CARD
// -----------------------------------------------------------------------------
/// The one number a student cares about, with the main action – marking
/// attendance – right underneath it.
class _AttendanceCard extends StatelessWidget {
  final int pct;
  final int threshold;
  final VoidCallback onScan;
  final VoidCallback onOpen;

  const _AttendanceCard({required this.pct, required this.threshold, required this.onScan, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (tone, note) = pct >= threshold
        ? (p.success, 'Above the $threshold% requirement')
        : (p.danger, 'Below the $threshold% requirement');

    return Pressable(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct.toDouble()),
                  duration: Motion.slow * 2,
                  curve: Motion.curve,
                  builder: (_, v, __) => Text(
                    '${v.round()}%',
                    style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -2, height: 1, color: p.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('attendance', style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: p.inkFaint),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar with a tick at the required percentage.
            LayoutBuilder(
              builder: (_, c) => Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct / 100),
                      duration: Motion.slow * 2,
                      curve: Motion.curve,
                      builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, color: tone, backgroundColor: p.surfaceRaised),
                    ),
                  ),
                  Positioned(
                    left: c.maxWidth * threshold / 100 - 1,
                    top: -3,
                    child: Container(width: 2, height: 14, color: p.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(note, style: TextStyle(fontSize: 13, color: tone, fontWeight: FontWeight.w500)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onScan,
                style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
                icon: const Icon(Icons.how_to_reg_rounded),
                label: const Text('Mark attendance'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
