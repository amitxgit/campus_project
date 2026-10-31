// lib/features/student/student_attendance_page.dart
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/attendance.dart';
import '../../core/models/subject.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../data/settings_repository.dart';

// -----------------------------------------------------------------------------
// MODELS
// -----------------------------------------------------------------------------

/// How a subject's attendance compares with the requirement.
enum AttendanceLevel { ok, close, low }

class StudentSubjectStats {
  final String subjectId;
  final String name;
  final int total;
  final int present;
  final int pct;
  final AttendanceLevel level;

  StudentSubjectStats({
    required this.subjectId,
    required this.name,
    required this.total,
    required this.present,
    required this.pct,
    required this.level,
  });
}

class _AttendanceData {
  final List<AttendanceRecord> sortedRecords;
  final List<StudentSubjectStats> subjectStats;
  final int overallTotal;
  final int overallPresent;
  final int overallPct;

  _AttendanceData({
    required this.sortedRecords,
    required this.subjectStats,
    required this.overallTotal,
    required this.overallPresent,
    required this.overallPct,
  });
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

final attendanceDataProvider = FutureProvider.autoDispose<_AttendanceData>((ref) async {
  final threshold = (await ref.watch(settingsFutureProvider.future)).attendanceThreshold;
  final authRepo = ref.watch(authRepoProvider);
  final user = await authRepo.currentUser();
  if (user == null) throw Exception('Not logged in');

  final attRepo = ref.watch(attendanceRepoProvider);
  final ttRepo = ref.watch(timetableRepoProvider);

  // Parallel fetch
  final results = await Future.wait([
    attRepo.forStudent(user.id),
    ttRepo.allSubjects(),
  ]);

  final records = results[0] as List<AttendanceRecord>;
  final subjects = results[1] as List<Subject>;
  final subjectsMap = {for (var s in subjects) s.id: s.name};

  // Sort records newest first
  records.sort((a, b) => b.date.compareTo(a.date));

  // Calculate stats per subject
  final Map<String, List<AttendanceRecord>> grouped = {};
  for (var r in records) {
    grouped.putIfAbsent(r.subjectId, () => []).add(r);
  }

  int grandTotal = 0;
  int grandPresent = 0;
  final List<StudentSubjectStats> stats = [];

  grouped.forEach((subId, recs) {
    final total = recs.length;
    // Present + Late + Excused count as attended
    final present = recs.where((r) =>
    r.status == AttendanceStatus.present ||
        r.status == AttendanceStatus.late ||
        r.status == AttendanceStatus.excused
    ).length;

    grandTotal += total;
    grandPresent += present;

    final pct = total == 0 ? 100 : ((present / total) * 100).round();

    final level = pct < threshold
        ? AttendanceLevel.low
        : (pct < threshold + 10 ? AttendanceLevel.close : AttendanceLevel.ok);

    stats.add(StudentSubjectStats(
      subjectId: subId,
      name: subjectsMap[subId] ?? 'Unknown Subject',
      total: total,
      present: present,
      pct: pct,
      level: level,
    ));
  });

  stats.sort((a, b) => a.name.compareTo(b.name));
  final overallPct = grandTotal == 0 ? 100 : ((grandPresent / grandTotal) * 100).round();

  return _AttendanceData(
    sortedRecords: records,
    subjectStats: stats,
    overallTotal: grandTotal,
    overallPresent: grandPresent,
    overallPct: overallPct,
  );
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------

class StudentAttendancePage extends ConsumerWidget {
  const StudentAttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(attendanceDataProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Attendance'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(attendanceDataProvider),
        ),
        data: (data) {
          if (data.sortedRecords.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(attendanceDataProvider),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _HeroSummaryCard(data: data)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('By subject', padding: EdgeInsets.only(bottom: 12)),
                        _buildSubjectGrid(context, data.subjectStats),
                        const SectionLabel('History', padding: EdgeInsets.only(top: 28, bottom: 12)),
                        _buildHistoryTimeline(context, data),
                        const SizedBox(height: 60),
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

  // ---------------------------------------------------------------------------
  // UI WIDGETS
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(BuildContext context) {
    return const Center(
      child: EmptyNote(icon: Icons.fact_check_outlined, text: 'Your attendance will appear here after your first class.'),
    );
  }

  Widget _buildSubjectGrid(BuildContext context, List<StudentSubjectStats> stats) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.25,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: stats.length,
      itemBuilder: (ctx, i) {
        final stat = stats[i];
        final p = context.palette;
        final tone = switch (stat.level) {
          AttendanceLevel.low => p.danger,
          AttendanceLevel.close => p.warning,
          AttendanceLevel.ok => p.success,
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stat.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.25),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stat.present}/${stat.total}',
                        style: TextStyle(color: context.palette.inkMuted, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: stat.pct / 100),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: 4.5,
                            backgroundColor: p.surfaceRaised,
                            color: tone,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: stat.pct.toDouble()),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => Text(
                          '${value.toInt()}%',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryTimeline(BuildContext context, _AttendanceData data) {
    final p = context.palette;

    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.sortedRecords.length,
        separatorBuilder: (_, __) => Divider(indent: 16, endIndent: 16, color: p.line),
        itemBuilder: (ctx, i) {
          final r = data.sortedRecords[i];
          final subjName = data.subjectStats.firstWhere(
                  (s) => s.subjectId == r.subjectId,
              orElse: () => StudentSubjectStats(subjectId: '', name: 'Unknown', total: 0, present: 0, pct: 0, level: AttendanceLevel.ok)
          ).name;

          final (fg, bg) = switch (r.status) {
            AttendanceStatus.present || AttendanceStatus.excused => (p.success, p.successSoft),
            AttendanceStatus.late => (p.warning, p.warningSoft),
            _ => (p.danger, p.dangerSoft),
          };
          final label = r.status.name[0].toUpperCase() + r.status.name.substring(1);

          return ListTile(
            title: Text(subjName, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${DateFormat('EEE, d MMM').format(r.date)}  ·  ${r.slot}',
              style: TextStyle(color: p.inkMuted, fontSize: 13),
            ),
            trailing: StatusPill(text: label, color: fg, background: bg),
          );
        },
      ),
    );
  }
}
// -----------------------------------------------------------------------------
// OVERALL SUMMARY
// -----------------------------------------------------------------------------
class _HeroSummaryCard extends ConsumerWidget {
  final _AttendanceData data;
  const _HeroSummaryCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(settingsProvider).attendanceThreshold;
    final p = context.palette;
    final ok = data.overallPct >= threshold;
    final tone = ok ? p.success : p.danger;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: data.overallPct.toDouble()),
                duration: Motion.slow * 2,
                curve: Motion.curve,
                builder: (context, value, _) => Text(
                  '${value.round()}%',
                  style: TextStyle(color: p.ink, fontSize: 44, fontWeight: FontWeight.w700, height: 1.0, letterSpacing: -2),
                ),
              ),
              const Spacer(),
              Text(
                '${data.overallPresent} of ${data.overallTotal} classes',
                style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: data.overallPct / 100),
              duration: Motion.slow * 2,
              curve: Motion.curve,
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, color: tone, backgroundColor: p.surfaceRaised),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ok ? 'Above the $threshold% requirement' : 'Below the $threshold% requirement',
            style: TextStyle(fontSize: 13, color: tone, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
