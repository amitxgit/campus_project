// lib/features/student/timetable_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/timetable_grid.dart';
import '../../core/models/role.dart';
import '../../core/models/timetable_entry.dart';
import '../../core/models/timetable_override.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/utils/time_formatter.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';

// -----------------------------------------------------------------------------
// VIEW MODEL
// -----------------------------------------------------------------------------

class TimetablePageVM {
  final String section;
  final List<TimetableEntry> entries;
  final Set<String> cancelledEntryIds;
  final Map<String, Subject> subjectsMap;
  final Map<String, String> teacherNamesMap;
  final Upcoming? nextClass;

  TimetablePageVM({
    required this.section,
    required this.entries,
    required this.cancelledEntryIds,
    required this.subjectsMap,
    required this.teacherNamesMap,
    required this.nextClass,
  });
}

class Upcoming {
  final TimetableEntry entry;
  final int minutesToStart;
  final bool isOngoing;

  Upcoming(
      this.entry,
      this.minutesToStart, {
        required this.isOngoing,
      });
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

final studentTimetablePageProvider =
FutureProvider.autoDispose<TimetablePageVM>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), () => link.close());
  ref.onDispose(timer.cancel);

  final authRepo = ref.watch(authRepoProvider);
  final user = await authRepo.currentUser();
  if (user == null) throw Exception('Not logged in');

  final section = user.section ?? '';
  if (section.isEmpty) {
    throw Exception("You haven't been added to a batch yet. Please ask your admin.");
  }

  final ttRepo = ref.watch(timetableRepoProvider);

  final today = DateTime.now();
  final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  final results = await Future.wait([
    ttRepo.forSection(section),
    ttRepo.allSubjects(),
    authRepo.allTeachers(),
    ttRepo.getOverridesForDate(section, dateString),
  ]);

  final rawEntries = results[0] as List<TimetableEntry>;
  final subjects = results[1] as List<Subject>;
  final users = results[2] as List<UserAccount>;
  final overrides = results[3] as List<TimetableOverride>;

  final subjectsMap = {for (final s in subjects) s.id: s};
  final teacherNamesMap = {
    for (final u in users.where((u) => u.role == UserRole.teacher))
      u.id: u.name
  };

  final overrideMap = {for (final o in overrides) o.originalEntryId: o};
  final todayKey = _TimetableUtil.dayStr(today.weekday);
  final cancelledEntryIds = <String>{};

  final normalizedEntries = rawEntries.map((e) {
    const dayMap = {'1': 'Mon', '2': 'Tue', '3': 'Wed', '4': 'Thu', '5': 'Fri', '6': 'Sat'};
    final safeDay = dayMap[e.dayOfWeek] ?? e.dayOfWeek;
    final dataMap = e.toMap();
    dataMap['dayOfWeek'] = safeDay;

    if (safeDay == todayKey && overrideMap.containsKey(e.id)) {
      final over = overrideMap[e.id]!;

      if (over.isCancelled) {
        cancelledEntryIds.add(e.id);
        dataMap['room'] = 'Cancelled';
      } else {
        if (over.newStartTime != null) dataMap['startTime'] = over.newStartTime;
        if (over.newEndTime != null) dataMap['endTime'] = over.newEndTime;
        if (over.newRoom != null) dataMap['room'] = '${over.newRoom} (Updated)';
      }
    }

    return TimetableEntry.fromMap(e.id, dataMap);
  }).toList();

  final todays = normalizedEntries
      .where((e) => e.dayOfWeek == todayKey && !cancelledEntryIds.contains(e.id))
      .toList()
    ..sort((a, b) => _TimetableUtil.toMinutes(a.startTime).compareTo(_TimetableUtil.toMinutes(b.startTime)));

  final nextClass = _TimetableUtil.findNextOrOngoing(todays);

  return TimetablePageVM(
    section: section,
    entries: normalizedEntries,
    cancelledEntryIds: cancelledEntryIds,
    subjectsMap: subjectsMap,
    teacherNamesMap: teacherNamesMap,
    nextClass: nextClass,
  );
});

// -----------------------------------------------------------------------------
// UI
// -----------------------------------------------------------------------------

class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(studentTimetablePageProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('My Timetable'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => _buildErrorState(context, ref, err, stack),
        data: (vm) {
          final subjectCodes = vm.subjectsMap.map((k, v) => MapEntry(k, v.code));
          final subjectLeadMap = vm.subjectsMap.map((k, v) => MapEntry(k, v.teacherId));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(studentTimetablePageProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (vm.nextClass != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _NextClassCard(vm: vm),
                  ),

                if (vm.cancelledEntryIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _CancelledBanner(count: vm.cancelledEntryIds.length),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weekly Schedule',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${ref.watch(settingsProvider).groupLabel} ${vm.section}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                TimetableGrid(
                  days: ref.watch(settingsProvider).workingDays,
                  periodStarts: ref.watch(settingsProvider).periodStarts,
                  periodLabels: ref.watch(settingsProvider).periodLabels,
                  entries: vm.entries,
                  subjectCodes: subjectCodes,
                  subjectLeadTeacherId: subjectLeadMap,
                  teacherNames: vm.teacherNamesMap,
                  todayKey: _TimetableUtil.dayStr(DateTime.now().weekday),
                  // ✅ FIXED: Pass cancelled IDs down so the grid styles them!
                  cancelledEntryIds: vm.cancelledEntryIds,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object err, StackTrace stack) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning, color: Colors.red, size: 32),
                SizedBox(width: 8),
                Text('CRASH DETECTED', style: TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 32),
            Text('ERROR:\n$err', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Text('STACK TRACE:\n$stack', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => ref.invalidate(studentTimetablePageProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final errorText = 'CRASH REPORT\n\nERROR:\n$err\n\nSTACK TRACE:\n$stack';
                    await Clipboard.setData(ClipboardData(text: errorText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error details copied!')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODERNIZED NEXT CLASS CARD
// -----------------------------------------------------------------------------

class _NextClassCard extends StatelessWidget {
  final TimetablePageVM vm;
  const _NextClassCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final nc = vm.nextClass!;
    final e = nc.entry;
    final subject = vm.subjectsMap[e.subjectId]?.name ?? e.subjectId;
    final isPrimary = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isPrimary
              ? [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)]
              : [Theme.of(context).colorScheme.surfaceContainerHigh, Theme.of(context).colorScheme.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(nc.isOngoing ? Icons.play_circle_fill : Icons.schedule,
                        color: isPrimary ? Colors.white : Theme.of(context).colorScheme.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      nc.isOngoing ? 'ONGOING' : 'UPCOMING',
                      style: TextStyle(
                        color: isPrimary ? Colors.white : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                nc.isOngoing ? 'Ends in ${nc.minutesToStart}m' : 'Starts in ${nc.minutesToStart}m',
                style: TextStyle(
                  color: isPrimary ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            subject,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: isPrimary ? Colors.white : Theme.of(context).colorScheme.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, size: 18, color: isPrimary ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                TimeFormatter.formatSlot(e.slot),
                style: TextStyle(
                  color: isPrimary ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.room, size: 18, color: isPrimary ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Room ${e.room}',
                style: TextStyle(
                  color: isPrimary ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CANCELLED BANNER
// -----------------------------------------------------------------------------

class _CancelledBanner extends StatelessWidget {
  final int count;
  const _CancelledBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 class has been cancelled today.'
                  : '$count classes have been cancelled today.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// UTILITIES
// -----------------------------------------------------------------------------

class _TimetableUtil {

  static String dayStr(int weekday) {
    const map = {
      1: 'Mon', 2: 'Tue', 3: 'Wed',
      4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
    };
    return map[weekday] ?? 'Mon';
  }

  static int toMinutes(String hhmm) {
    try {
      return int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));
    } catch (_) {
      return 0;
    }
  }

  static Upcoming? findNextOrOngoing(List<TimetableEntry> todays) {
    if (todays.isEmpty) return null;
    final now = DateTime.now();

    DateTime at(String hhmm) {
      try {
        final p = hhmm.split(':');
        return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      } catch (_) {
        return now;
      }
    }

    for (final e in todays) {
      final start = at(e.startTime);
      final end = at(e.endTime);

      if (!now.isBefore(start) && now.isBefore(end)) {
        return Upcoming(e, end.difference(now).inMinutes, isOngoing: true);
      }
      if (start.isAfter(now)) {
        return Upcoming(e, start.difference(now).inMinutes, isOngoing: false);
      }
    }
    return null;
  }
}