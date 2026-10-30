// lib/features/student/student_attendance_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/attendance.dart';
import '../../core/models/subject.dart';
import '../../main.dart';
import '../../data/settings_repository.dart';

// -----------------------------------------------------------------------------
// MODELS
// -----------------------------------------------------------------------------

class StudentSubjectStats {
  final String subjectId;
  final String name;
  final int total;
  final int present;
  final int pct;
  final Color color;

  StudentSubjectStats({
    required this.subjectId,
    required this.name,
    required this.total,
    required this.present,
    required this.pct,
    required this.color,
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

    Color color = Colors.green;
    if (pct < threshold) {
      color = Colors.red;
    } else if (pct < threshold + 10) {
      color = Colors.orange;
    }

    stats.add(StudentSubjectStats(
      subjectId: subId,
      name: subjectsMap[subId] ?? 'Unknown Subject',
      total: total,
      present: present,
      pct: pct,
      color: color,
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Attendance Analytics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subject Breakdown',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 16),
                        _buildSubjectGrid(context, data.subjectStats),
                        const SizedBox(height: 40),
                        Text(
                          'Activity Timeline',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 16),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.analytics_outlined, size: 64, color: colorScheme.primary),
          ),
          const SizedBox(height: 24),
          const Text('No Attendance Data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Your attendance records will appear here.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
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
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: stats.length,
      itemBuilder: (ctx, i) {
        final stat = stats[i];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stat.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.2),
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
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Attended',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        // ✅ ENTERPRISE FEATURE: Animated Progress Rings
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: stat.pct / 100),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: 4.5,
                            backgroundColor: stat.color.withValues(alpha: 0.15),
                            color: stat.color,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      ),
                      // ✅ ENTERPRISE FEATURE: Animated Inner Percentage
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: stat.pct.toDouble()),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => Text(
                          '${value.toInt()}%',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: stat.color),
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

  // ✅ ENTERPRISE FEATURE: Timeline Log UI
  Widget _buildHistoryTimeline(BuildContext context, _AttendanceData data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.sortedRecords.length,
        itemBuilder: (ctx, i) {
          final r = data.sortedRecords[i];
          final subjName = data.subjectStats.firstWhere(
                  (s) => s.subjectId == r.subjectId,
              orElse: () => StudentSubjectStats(subjectId: '', name: 'Unknown', total: 0, present: 0, pct: 0, color: Colors.black)
          ).name;

          final isPresent = r.status == AttendanceStatus.present || r.status == AttendanceStatus.excused;
          final isLate = r.status == AttendanceStatus.late;

          final color = isPresent ? Colors.green : (isLate ? Colors.orange : Colors.red);
          final icon = isPresent ? Icons.check_circle_rounded : (isLate ? Icons.watch_later_rounded : Icons.cancel_rounded);

          final isLast = i == data.sortedRecords.length - 1;

          return IntrinsicHeight(
            child: Row(
              children: [
                // Timeline Connector Column
                SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      Container(
                        width: 2,
                        height: 20,
                        color: i == 0 ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 14, color: color),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isLast ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12),
                        ),
                      ),
                    ],
                  ),
                ),

                // Timeline Content Card
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, top: 12, bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subjName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(DateFormat('MMM d, yyyy').format(r.date), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 12),
                                    Icon(Icons.access_time_rounded, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(r.slot, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: color.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              r.status.name.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
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
// HERO OVERALL SUMMARY CARD
// -----------------------------------------------------------------------------
class _HeroSummaryCard extends ConsumerWidget {
  final _AttendanceData data;
  const _HeroSummaryCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(settingsProvider).attendanceThreshold;
    final colorScheme = Theme.of(context).colorScheme;

    List<Color> gradientColors;
    String statusText;
    IconData statusIcon;

    if (data.overallPct >= threshold + 10) {
      gradientColors = const [Color(0xFF0D9488), Color(0xFF059669)]; // Teal/Green
      statusText = 'Excellent standing';
      statusIcon = Icons.verified_rounded;
    } else if (data.overallPct >= threshold) {
      gradientColors = const [Color(0xFFD97706), Color(0xFFF59E0B)]; // Orange/Amber
      statusText = 'Requires attention';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      gradientColors = const [Color(0xFFE11D48), Color(0xFFDC2626)]; // Rose/Red
      statusText = 'Critical shortage';
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.tertiary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          // Inner Glass Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: gradientColors.last.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(Icons.analytics_rounded, size: 120, color: Colors.white.withValues(alpha: 0.15)),
                ),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ ENTERPRISE FEATURE: Animated Counter
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: data.overallPct.toDouble()),
                              duration: const Duration(milliseconds: 1500),
                              curve: Curves.easeOutExpo,
                              builder: (context, value, _) => Text(
                                '${value.toInt()}%',
                                style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text('Overall Attendance', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${data.overallPresent}/${data.overallTotal}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text('Classes Attended', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}