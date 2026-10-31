// lib/features/common/widgets/timetable_grid.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/timetable_entry.dart';
import '../../../core/utils/time_formatter.dart';
import '../../teacher/teacher_home_page.dart'; // Needed to refresh the teacher dashboard provider
import '../../../theme.dart';
import 'override_class_dialog.dart';

class TimetableGrid extends ConsumerWidget {
  final List<String> days;
  final List<String> periodStarts;
  final List<String> periodLabels;
  final List<TimetableEntry> entries;
  final Map<String, String> subjectCodes;
  final Map<String, String> subjectLeadTeacherId;
  final Map<String, String> teacherNames;
  final String? todayKey;
  final String? currentTeacherId;
  final Set<String> cancelledEntryIds;

  const TimetableGrid({
    super.key,
    required this.days,
    required this.periodStarts,
    required this.periodLabels,
    required this.entries,
    required this.subjectCodes,
    required this.subjectLeadTeacherId,
    this.teacherNames = const {},
    this.todayKey,
    this.currentTeacherId,
    this.cancelledEntryIds = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, Map<int, TimetableEntry>> grid = {
      for (final d in days) d: {}
    };

    for (final e in entries) {
      final entryTime = _normalizeTime(e.startTime);
      int pIndex = -1;

      for (int i = 0; i < periodStarts.length; i++) {
        if (_normalizeTime(periodStarts[i]) == entryTime) {
          pIndex = i;
          break;
        }
      }

      if (pIndex != -1 && grid.containsKey(e.dayOfWeek)) {
        grid[e.dayOfWeek]![pIndex] = e;
      }
    }

    final p = context.palette;
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    return LayoutBuilder(
      builder: (context, constraints) {
        const dayColWidth = 56.0;
        final available = constraints.maxWidth - 32 - dayColWidth;
        final colWidth = periodStarts.isEmpty ? 110.0 : (available / periodStarts.length).clamp(110.0, 200.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          child: Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                0: const FixedColumnWidth(dayColWidth),
                for (int i = 0; i < periodStarts.length; i++) i + 1: FixedColumnWidth(colWidth),
              },
              children: [
                TableRow(children: [
                  const SizedBox(height: 44),
                  for (int i = 0; i < periodStarts.length; i++)
                    _headerCell(context, i < periodLabels.length ? periodLabels[i] : '', TimeFormatter.formatTime(periodStarts[i])),
                ]),
                for (final day in days)
                  TableRow(children: [
                    _dayCell(context, day, isToday: day == todayKey),
                    for (int i = 0; i < periodStarts.length; i++)
                      _classCell(context, ref, grid[day]?[i], isToday: day == todayKey, nowMins: nowMins),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }

  static int _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _normalizeTime(String time) {
    final parts = time.split(':');
    return '${int.parse(parts[0]).toString().padLeft(2, '0')}:${int.parse(parts[1]).toString().padLeft(2, '0')}';
  }

  Widget _headerCell(BuildContext context, String label, String time) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: p.inkMuted)),
          Text(time, style: TextStyle(fontSize: 12, color: p.inkFaint, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, String day, {required bool isToday}) {
    final p = context.palette;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isToday ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          day,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isToday ? p.onAccent : p.inkMuted,
          ),
        ),
      ),
    );
  }

  Widget _classCell(
    BuildContext context,
    WidgetRef ref,
    TimetableEntry? entry, {
    required bool isToday,
    required int nowMins,
  }) {
    if (entry == null) return const SizedBox(height: 76);

    final p = context.palette;
    final code = subjectCodes[entry.subjectId] ?? '—';
    final isCancelled = cancelledEntryIds.contains(entry.id);
    final start = _parseTime(entry.startTime);
    final end = _parseTime(entry.endTime);
    // Uses each class's own times, so any class length works.
    final isCurrent = isToday && !isCancelled && nowMins >= start && nowMins < end;
    final isTeacher = currentTeacherId != null;
    final canOverride = isToday && isTeacher && !isCancelled && nowMins < end;

    final (Color bg, Color fg, Color sub) = isCancelled
        ? (p.dangerSoft, p.danger, p.danger)
        : isCurrent
            ? (p.accent, p.onAccent, p.onAccent.withValues(alpha: 0.8))
            : (p.background, p.ink, p.inkMuted);

    final cell = Container(
      height: 64,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: canOverride && !isCurrent ? Border.all(color: p.accent.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: fg,
              decoration: isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          Text(
            isCancelled ? 'Cancelled' : (isCurrent ? 'Now' : entry.room),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sub),
          ),
        ],
      ),
    );

    if (!canOverride) return cell;
    return Tooltip(
      message: 'Long-press to cancel or reschedule',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => showDialog(
          context: context,
          builder: (_) => OverrideClassDialog(
            entry: entry,
            subjectName: code,
            currentTeacherId: currentTeacherId!,
            onOverrideComplete: () => ref.invalidate(teacherDashboardProvider),
          ),
        ),
        child: cell,
      ),
    );
  }
}
