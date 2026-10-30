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
import '../../core/utils/time_formatter.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';

// ✅ FIX: Corrected the import path to point to your common/widgets folder!
import '../common/widgets/override_class_dialog.dart';

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
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(teacherDashboardProvider),
        ),
        data: (vm) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(teacherDashboardProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(vm: vm),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _ActionButtons(),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Today\'s Classes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (vm.todaysClasses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.event_available_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
                              ),
                              const SizedBox(height: 16),
                              const Text('No classes scheduled today!', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Enjoy your free time.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: vm.todaysClasses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (ctx, i) {
                          final entry = vm.todaysClasses[i];
                          final subj = vm.subjectsMap[entry.subjectId];
                          final isCancelled = vm.cancelledEntryIds.contains(entry.id);
                          final rescheduleData = vm.rescheduledEntries[entry.id];

                          return _ModernClassCard(
                            entry: entry,
                            subject: subj,
                            isCancelled: isCancelled,
                            rescheduleData: rescheduleData,
                            currentTeacherId: vm.currentTeacherId,
                            ref: ref,
                          );
                        },
                      ),
                    const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Weekly Timetable',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TimetablePreview(vm: vm),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HEADER & ACTION BUTTONS
// -----------------------------------------------------------------------------
class _Header extends StatelessWidget {
  final TeacherDashboardVM vm;
  const _Header({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome, Professor 👋', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text('${vm.todaysClasses.length} Classes Today', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Text('Ready for the day?', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    final actions = [
      (title: 'Marks', icon: Icons.assessment_rounded, path: '/teacher/internal-marks', color: Colors.indigo),
      (title: 'Remarks', icon: Icons.rate_review_rounded, path: '/teacher/remarks-board', color: Colors.teal),
      (title: 'Students', icon: Icons.people_alt_rounded, path: '/students/directory', color: Colors.purple),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisExtent: 140,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (ctx, i) => _ModernActionCard(
        title: actions[i].title,
        icon: actions[i].icon,
        path: actions[i].path,
        themeColor: actions[i].color,
      ),
    );
  }
}

class _ModernActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String path;
  final MaterialColor themeColor;

  const _ModernActionCard({required this.title, required this.icon, required this.path, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white30 : Colors.black26;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(path),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: isDark ? themeColor.shade900.withValues(alpha: 0.5) : themeColor.shade50, shape: BoxShape.circle),
                child: Icon(icon, color: isDark ? themeColor.shade200 : themeColor.shade700, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TODAY's CLASS CARD W/ OVERRIDES
// -----------------------------------------------------------------------------
class _ModernClassCard extends StatelessWidget {
  final TimetableEntry entry;
  final Subject? subject;
  final bool isCancelled;
  final Map<String, dynamic>? rescheduleData;
  final String currentTeacherId;
  final WidgetRef ref;

  const _ModernClassCard({
    required this.entry,
    required this.subject,
    required this.isCancelled,
    required this.rescheduleData,
    required this.currentTeacherId,
    required this.ref,
  });

  String _getSemester(String section) {
    if (section.startsWith('IV-')) return '8';
    if (section.startsWith('III-')) return '6';
    if (section.startsWith('II-')) return '4';
    if (section.startsWith('I-')) return '2';
    return section;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayTime = rescheduleData != null ? rescheduleData!['newStartTime'] as String : entry.startTime;
    final displayRoom = rescheduleData != null ? rescheduleData!['newRoom'] as String : entry.room;
    final timeStr = TimeFormatter.formatTime(displayTime).split(' ');

    final displaySemester = _getSemester(entry.section);

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
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 24),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subject?.name ?? 'Unknown Subject',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isCancelled ? Colors.grey : null),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => OverrideClassDialog(
                              entry: entry,
                              subjectName: subject?.name ?? 'Unknown Subject',
                              currentTeacherId: currentTeacherId,
                              onOverrideComplete: () => ref.invalidate(teacherDashboardProvider),
                            ),
                          );
                        },
                      )
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.class_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('Sem: $displaySemester', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Icon(Icons.room_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('Room $displayRoom', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (isCancelled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('CLASS CANCELLED', style: TextStyle(color: colorScheme.onErrorContainer, fontWeight: FontWeight.bold, letterSpacing: 1))),
                    )
                  else if (rescheduleData != null)
                    Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Center(child: Text('RESCHEDULED', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1))),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              await context.push('/teacher/generate-qr/${entry.id}');
                              ref.invalidate(teacherDashboardProvider);
                            },
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Take Attendance'),
                            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await context.push('/teacher/generate-qr/${entry.id}');
                          ref.invalidate(teacherDashboardProvider);
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('Take Attendance'),
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white30 : Colors.black26;

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
            ? Container(
          height: 150,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Center(
            child: Text(
              _selectedGroup == null ? 'No classes scheduled.' : 'No classes for $_selectedGroup.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
        )
            : TimetableGrid(
          days: [dayKey],
          periodStarts: settings.periodStarts,
          periodLabels: settings.periodLabels,
          entries: filteredEntries,
          subjectCodes: {for (var k in widget.vm.subjectsMap.keys) k: widget.vm.subjectsMap[k]?.code ?? ''},
          subjectLeadTeacherId: {for (var k in widget.vm.subjectsMap.keys) k: widget.vm.subjectsMap[k]?.teacherId ?? ''},
          teacherNames: widget.vm.teacherNamesMap,
          todayKey: dayKey,
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