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
import '../../core/utils/time_formatter.dart';
import '../../main.dart';
import '../../data/settings_repository.dart';

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
      .get(); // We fetch all for today, since we filter entries locally

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

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
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
          message: err.toString(),
          onRetry: () => ref.invalidate(studentDashboardProvider),
        ),
        data: (vm) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(studentDashboardProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(vm: vm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ModernAttendanceCard(pct: vm.attendancePct),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _QuickActions(vm: vm),
                ),

                // 🔴 NEW: TODAY'S SCHEDULE SHOWING CANCELLATIONS
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Today\'s Schedule', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                if (vm.todaysClasses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No classes today! Enjoy your free time.', style: TextStyle(fontWeight: FontWeight.w500))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: vm.todaysClasses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final entry = vm.todaysClasses[i];
                      final subj = vm.subjectsMap[entry.subjectId];
                      final isCancelled = vm.cancelledEntryIds.contains(entry.id);
                      final rescheduleData = vm.rescheduledEntries[entry.id];

                      return _StudentClassCard(
                        entry: entry,
                        subject: subj,
                        isCancelled: isCancelled,
                        rescheduleData: rescheduleData,
                      );
                    },
                  ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HEADER (SEMESTER ONLY)
// -----------------------------------------------------------------------------
class _Header extends StatelessWidget {
  final StudentDashboardVM vm;
  const _Header({required this.vm});

  @override
  Widget build(BuildContext context) {
    final semesterText = vm.student.semester != null ? 'Semester ${vm.student.semester}' : 'Year ${vm.student.year ?? 1}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, ${vm.student.name.split(' ').first} 👋',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(semesterText, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Text('Roll No: ${vm.student.collegeRollNo ?? "N/A"}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// STUDENT CLASS CARD (WITH CANCELLATION ALERTS)
// -----------------------------------------------------------------------------
class _StudentClassCard extends StatelessWidget {
  final TimetableEntry entry;
  final Subject? subject;
  final bool isCancelled;
  final Map<String, dynamic>? rescheduleData;

  const _StudentClassCard({
    required this.entry,
    required this.subject,
    required this.isCancelled,
    required this.rescheduleData,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayTime = rescheduleData != null ? rescheduleData!['newStartTime'] as String : entry.startTime;
    final displayRoom = rescheduleData != null ? rescheduleData!['newRoom'] as String : entry.room;
    final timeStr = TimeFormatter.formatTime(displayTime).split(' ');

    Color borderColor = isDark ? Colors.white30 : Colors.black26;
    Color timeBlockColor = colorScheme.primaryContainer.withValues(alpha: 0.4);

    if (isCancelled) {
      borderColor = colorScheme.error;
      timeBlockColor = colorScheme.errorContainer.withValues(alpha: 0.3);
    } else if (rescheduleData != null) {
      borderColor = Colors.blue;
      timeBlockColor = Colors.blue.withValues(alpha: 0.1);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isCancelled || rescheduleData != null ? 2.0 : 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: timeBlockColor,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  timeStr[0],
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900,
                    color: isCancelled ? colorScheme.error : colorScheme.primary,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  timeStr.length > 1 ? timeStr[1] : '',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isCancelled ? colorScheme.error : colorScheme.primary.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject?.name ?? 'Unknown Subject',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isCancelled ? Colors.grey : null),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.room_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('Room $displayRoom', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (isCancelled) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text('CANCELLED BY TEACHER', style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ] else if (rescheduleData != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: const Text('RESCHEDULED', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODERN ATTENDANCE CARD
// -----------------------------------------------------------------------------
class _ModernAttendanceCard extends ConsumerWidget {
  final int pct;
  const _ModernAttendanceCard({required this.pct});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(settingsProvider).attendanceThreshold;
    List<Color> gradientColors;
    String statusText;
    IconData statusIcon;

    if (pct >= threshold + 10) {
      gradientColors = const [Color(0xFF0D9488), Color(0xFF059669)];
      statusText = 'Excellent standing';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (pct >= threshold) {
      gradientColors = const [Color(0xFFD97706), Color(0xFFF59E0B)];
      statusText = 'Requires attention';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      gradientColors = const [Color(0xFFE11D48), Color(0xFFDC2626)];
      statusText = 'Critical shortage';
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: gradientColors.last.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: -20, bottom: -20, child: Icon(Icons.analytics_rounded, size: 120, color: Colors.white.withValues(alpha: 0.15))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(statusText.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1)),
              const SizedBox(height: 4),
              const Text('Overall Attendance', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// QUICK ACTIONS
// -----------------------------------------------------------------------------
class _QuickActions extends ConsumerWidget {
  final StudentDashboardVM vm;
  const _QuickActions({required this.vm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _ActionData(title: 'Scan QR', icon: Icons.qr_code_scanner_rounded, path: '/student/scan-qr', themeColor: Colors.blue),
      _ActionData(title: 'Attendance', icon: Icons.fact_check_rounded, path: '/student/attendance', themeColor: Colors.teal, badgeText: '${vm.attendancePct}%'),
      _ActionData(title: 'Timetable', icon: Icons.calendar_month_rounded, path: '/student/timetable', themeColor: Colors.purple),
      _ActionData(title: 'Raise Query', icon: Icons.support_agent_rounded, path: '/student/raise-query', themeColor: Colors.orange),
    ];

    return LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 3 : 2);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: constraints.maxWidth > 600 ? 1.5 : 1.1,
            ),
            itemBuilder: (_, i) => _ModernActionCard(
              data: actions[i],
              onTap: () async {
                if (actions[i].path == '/student/scan-qr') {
                  await context.push(actions[i].path);
                  ref.invalidate(studentDashboardProvider);
                } else {
                  context.push(actions[i].path);
                }
              },
            ),
          );
        }
    );
  }
}

class _ActionData {
  final String title;
  final IconData icon;
  final String path;
  final MaterialColor themeColor;
  final String? badgeText;
  _ActionData({required this.title, required this.icon, required this.path, required this.themeColor, this.badgeText});
}

class _ModernActionCard extends StatelessWidget {
  final _ActionData data;
  final VoidCallback onTap;
  const _ModernActionCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isDark ? data.themeColor.shade900.withValues(alpha: 0.5) : data.themeColor.shade50, borderRadius: BorderRadius.circular(16)),
                      child: Icon(data.icon, color: isDark ? data.themeColor.shade200 : data.themeColor.shade700, size: 28),
                    ),
                    const Spacer(),
                    Text(data.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
              if (data.badgeText != null)
                Positioned(
                  top: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: data.themeColor, borderRadius: BorderRadius.circular(12)),
                    child: Text(data.badgeText!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}