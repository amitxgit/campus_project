// lib/features/teacher/teacher_home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/timetable_grid.dart';
import '../../core/models/timetable_entry.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../common/widgets/class_card.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';

// ✅ FIX: Corrected the import path to point to your common/widgets folder!
import '../common/widgets/override_class_dialog.dart';
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// VIEW MODEL
// -----------------------------------------------------------------------------
class TeacherDashboardVM {
  final List<TimetableEntry> allEntries;
  final List<TimetableEntry> todaysClasses;
  final Set<String> cancelledEntryIds;
  final Map<String, Map<String, dynamic>> rescheduledEntries;
  final Map<String, Subject> subjectsMap;
  final Map<String, String> teacherNamesMap;
  final String currentTeacherId;

  TeacherDashboardVM({
    required this.allEntries,
    required this.todaysClasses,
    required this.cancelledEntryIds,
    required this.rescheduledEntries,
    required this.subjectsMap,
    required this.teacherNamesMap,
    required this.currentTeacherId,
  });
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final teacherDashboardProvider = FutureProvider.autoDispose<TeacherDashboardVM>((ref) async {
  final authRepo = ref.watch(authRepoProvider);
  final ttRepo = ref.watch(timetableRepoProvider);
  final db = FirebaseFirestore.instance;

  final user = await authRepo.currentUser();
  if (user == null) throw Exception('Not logged in');

  final results = await Future.wait([
    ttRepo.forTeacher(user.id),
    ttRepo.allSubjects(),
    authRepo.allTeachers(),
  ]);

  final rawEntries = results[0] as List<TimetableEntry>;
  final subjects = results[1] as List<Subject>;
  final users = results[2] as List<UserAccount>;

  final subjectsMap = {for (var s in subjects) s.id: s};
  final teacherNamesMap = {for (var u in users) u.id: u.name};

  final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final overridesSnap = await db.collection('timetable_overrides')
      .where('date', isEqualTo: todayDateStr)
      .where('teacherId', isEqualTo: user.id)
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

  final normalizedEntries = rawEntries.map((e) {
    String day = e.dayOfWeek;
    const seederMap = {'1': 'Mon', '2': 'Tue', '3': 'Wed', '4': 'Thu', '5': 'Fri', '6': 'Sat'};
    final safeDay = seederMap[day] ?? day;
    final dataMap = e.toMap();
    dataMap['dayOfWeek'] = safeDay;
    return TimetableEntry.fromMap(e.id, dataMap);
  }).toList();

  final todayNum = DateTime.now().weekday;
  final dayMap = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
  final todayStr = dayMap[todayNum] ?? 'Mon';

  final todaysClasses = normalizedEntries.where((e) => e.dayOfWeek == todayStr).toList();
  todaysClasses.sort((a, b) => a.startTime.compareTo(b.startTime));

  return TeacherDashboardVM(
    allEntries: normalizedEntries,
    todaysClasses: todaysClasses,
    cancelledEntryIds: cancelledEntryIds,
    rescheduledEntries: rescheduledEntries,
    subjectsMap: subjectsMap,
    teacherNamesMap: teacherNamesMap,
    currentTeacherId: user.id,
  );
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------
class TeacherHomePage extends ConsumerWidget {
  const TeacherHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(teacherDashboardProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: Text(ref.watch(settingsProvider).name),
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
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(teacherDashboardProvider),
        ),
        data: (vm) {
          final running = vm.todaysClasses.where((e) => !vm.cancelledEntryIds.contains(e.id)).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(teacherDashboardProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                              style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Text(
                            running == 0 ? 'No classes today' : '$running ${running == 1 ? 'class' : 'classes'} today',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _ActionButtons(),
                        // The headline already says when there's nothing today.
                        if (vm.todaysClasses.isNotEmpty) const SectionLabel('Schedule'),
                        if (vm.todaysClasses.isNotEmpty)
                          for (var i = 0; i < vm.todaysClasses.length; i++)
                            FadeSlideIn(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: _TeacherClassCard(
                                  entry: vm.todaysClasses[i],
                                  subject: vm.subjectsMap[vm.todaysClasses[i].subjectId],
                                  isCancelled: vm.cancelledEntryIds.contains(vm.todaysClasses[i].id),
                                  rescheduleData: vm.rescheduledEntries[vm.todaysClasses[i].id],
                                  currentTeacherId: vm.currentTeacherId,
                                ),
                              ),
                            ),
                        if (vm.allEntries.isNotEmpty) ...[
                          const SectionLabel('This week'),
                          _TimetablePreview(vm: vm),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SHORTCUTS
// -----------------------------------------------------------------------------
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return ActionGrid(
      aspectRatio: 1.25,
      children: [
        if (settings.internalMarksEnabled)
          ActionTile(label: 'Marks', icon: Icons.assessment_outlined, onTap: () => context.push('/teacher/internal-marks')),
        if (settings.testsEnabled)
          ActionTile(label: 'Tests', icon: Icons.quiz_outlined, onTap: () => context.push('/tests')),
        if (settings.remarksEnabled)
          ActionTile(label: 'Remarks', icon: Icons.rate_review_outlined, onTap: () => context.push('/teacher/remarks-board')),
        ActionTile(label: 'Students', icon: Icons.people_outline_rounded, onTap: () => context.push('/students/directory')),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TODAY's CLASS CARD W/ OVERRIDES
// -----------------------------------------------------------------------------
class _TeacherClassCard extends ConsumerWidget {
  final TimetableEntry entry;
  final Subject? subject;
  final bool isCancelled;
  final Map<String, dynamic>? rescheduleData;
  final String currentTeacherId;

  const _TeacherClassCard({
    required this.entry,
    required this.subject,
    required this.isCancelled,
    required this.rescheduleData,
    required this.currentTeacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(settingsProvider).periodMinutes;
    final displayTime = rescheduleData != null ? rescheduleData!['newStartTime'] as String : entry.startTime;
    final displayRoom = rescheduleData != null ? rescheduleData!['newRoom'] as String : entry.room;
    final live = ClassCard.isNow(displayTime, minutes);

    Future<void> takeAttendance() async {
      await context.push('/teacher/generate-qr/${entry.id}');
      ref.invalidate(teacherDashboardProvider);
    }

    return ClassCard(
      startTime: displayTime,
      durationMinutes: minutes,
      subject: subject?.name ?? 'Unknown subject',
      meta: [if (entry.section.isNotEmpty) entry.section, if (displayRoom.isNotEmpty) ClassCard.roomLabel(displayRoom)].join('  ·  '),
      cancelled: isCancelled,
      rescheduled: rescheduleData != null,
      trailing: IconButton(
        tooltip: 'Cancel or reschedule',
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () => showDialog(
          context: context,
          builder: (ctx) => OverrideClassDialog(
            entry: entry,
            subjectName: subject?.name ?? 'Unknown subject',
            currentTeacherId: currentTeacherId,
            onOverrideComplete: () => ref.invalidate(teacherDashboardProvider),
          ),
        ),
      ),
      // The running class gets the bold button; the rest stay quiet.
      footer: isCancelled
          ? null
          : SizedBox(
              width: double.infinity,
              child: live
                  ? FilledButton.icon(
                      onPressed: takeAttendance,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                      label: const Text('Take attendance'),
                    )
                  : OutlinedButton.icon(
                      onPressed: takeAttendance,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                      label: const Text('Take attendance'),
                    ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// TIMETABLE PREVIEW
// -----------------------------------------------------------------------------
class _TimetablePreview extends ConsumerStatefulWidget {
  final TeacherDashboardVM vm;
  const _TimetablePreview({required this.vm});

  @override
  ConsumerState<_TimetablePreview> createState() => _TimetablePreviewState();
}

class _TimetablePreviewState extends ConsumerState<_TimetablePreview> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String _selectedDay = _dayNames[DateTime.now().weekday - 1];
  String? _selectedGroup;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final days = settings.workingDays;
    final dayKey = days.contains(_selectedDay) ? _selectedDay : days.first;

    final borderColor = context.palette.line;

    final groups = widget.vm.allEntries.map((e) => e.section).where((s) => s.isNotEmpty).toSet().toList()..sort();
    final filteredEntries = widget.vm.allEntries
        .where((e) => _selectedGroup == null || e.section == _selectedGroup)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildGroupChip('All', null, borderColor),
              for (final g in groups) ...[
                const SizedBox(width: 8),
                _buildGroupChip(g, g, borderColor),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: days.map((d) {
              final isSel = d == _selectedDay;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(d),
                  selected: isSel,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _selectedDay = d),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isSel ? Theme.of(context).colorScheme.primary : borderColor, width: 1.5),
                  ),
                  labelStyle: TextStyle(color: isSel ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: isSel ? FontWeight.bold : FontWeight.normal),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        filteredEntries.isEmpty
            ? EmptyNote(
          icon: Icons.event_busy_outlined,
          text: _selectedGroup == null ? 'No classes' : 'No classes for $_selectedGroup',
        )
            : TimetableGrid(
          days: [dayKey],
          periodStarts: settings.periodStarts,
          periodLabels: settings.periodLabels,
          entries: filteredEntries,
          subjectCodes: {for (var k in widget.vm.subjectsMap.keys) k: widget.vm.subjectsMap[k]?.code ?? ''},
          subjectLeadTeacherId: {for (var k in widget.vm.subjectsMap.keys) k: widget.vm.subjectsMap[k]?.teacherId ?? ''},
          teacherNames: widget.vm.teacherNamesMap,
          // The real today, not the selected tab: overrides apply to today's date.
          todayKey: _dayNames[DateTime.now().weekday - 1],
          currentTeacherId: widget.vm.currentTeacherId,
          cancelledEntryIds: widget.vm.cancelledEntryIds,
        ),
      ],
    );
  }

  Widget _buildGroupChip(String label, String? group, Color borderColor) {
    final isSelected = _selectedGroup == group;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (bool selected) => setState(() => _selectedGroup = selected ? group : null),
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? Theme.of(context).colorScheme.secondary : borderColor, width: 1.5),
      ),
      labelStyle: TextStyle(color: isSelected ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
    );
  }
}