// lib/features/admin/timetable_builder_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/institution_settings.dart';
import '../../core/models/timetable_entry.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../core/utils/time_formatter.dart';
import '../../theme.dart';
import '../common/widgets/class_card.dart';
import '../common/widgets/ui_kit.dart';

typedef _BuilderData = ({
  List<TimetableEntry> entries,
  List<Subject> subjects,
  List<UserAccount> teachers,
});

final timetableBuilderProvider = FutureProvider.autoDispose<_BuilderData>((ref) async {
  final ttRepo = ref.watch(timetableRepoProvider);
  final authRepo = ref.watch(authRepoProvider);

  final results = await Future.wait([
    ttRepo.allEntries(),
    ttRepo.allSubjects(),
    authRepo.allTeachers(),
  ]);

  return (
    entries: results[0] as List<TimetableEntry>,
    subjects: results[1] as List<Subject>,
    teachers: results[2] as List<UserAccount>,
  );
});

class TimetableBuilderPage extends ConsumerStatefulWidget {
  const TimetableBuilderPage({super.key});

  @override
  ConsumerState<TimetableBuilderPage> createState() => _TimetableBuilderPageState();
}

class _TimetableBuilderPageState extends ConsumerState<TimetableBuilderPage> {
  String? _selectedGroup;
  String? _selectedDay;

  /// Groups from settings, plus any already used in the timetable (so older
  /// data still shows up even if it isn't in the settings list).
  List<String> _groups(InstitutionSettings s, _BuilderData data) {
    final set = <String>{...s.groups};
    for (final e in data.entries) {
      if (e.section.isNotEmpty) set.add(e.section);
    }
    for (final sub in data.subjects) {
      if (sub.section.isNotEmpty) set.add(sub.section);
    }
    final list = set.toList();
    // Settings order first, then the rest alphabetically.
    list.sort((a, b) {
      final ia = s.groups.indexOf(a), ib = s.groups.indexOf(b);
      if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
      if (ia >= 0) return -1;
      if (ib >= 0) return 1;
      return a.compareTo(b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(timetableBuilderProvider);
    final settings = ref.watch(settingsProvider);
    final p = context.palette;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timetable'),
          actions: const [ProfileAvatarAction()],
          bottom: const TabBar(tabs: [Tab(text: 'Schedule'), Tab(text: 'Subjects')]),
        ),
        drawer: const AppDrawer(),
        // Builder: the batch/day row reads the tab controller created above.
        body: Builder(
          builder: (context) => asyncData.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => AsyncErrorWidget(
              message: FirebaseErrorParser.getMessage(err),
              onRetry: () => ref.invalidate(timetableBuilderProvider),
            ),
            data: (data) {
              final groups = _groups(settings, data);
              if (groups.isEmpty) return _buildNoGroups(settings);

              final group = groups.contains(_selectedGroup) ? _selectedGroup! : groups.first;
              final days = settings.workingDays;
              final day = days.contains(_selectedDay) ? _selectedDay! : days.first;
              final groupSubjects = data.subjects.where((s) => s.section == group).toList()..sort((a, b) => a.name.compareTo(b.name));

              final dayEntries = data.entries.where((e) => e.section == group && e.dayOfWeek == day).toList()
                ..sort((a, b) => a.startTime.compareTo(b.startTime));

              return Column(
                children: [
                  // Batch, then the day. One row, scrolls if it has to.
                  AnimatedBuilder(
                    animation: DefaultTabController.of(context),
                    builder: (context, _) => SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        children: [
                          MenuChip(value: group, options: groups, onSelected: (g) => setState(() => _selectedGroup = g)),
                          if (DefaultTabController.of(context).index == 0)
                            Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: p.line),
                          // Days only matter on the Schedule tab.
                          if (DefaultTabController.of(context).index == 0)
                            for (final d in days)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(d),
                                  selected: d == day,
                                  showCheckmark: false,
                                  onSelected: (_) => setState(() => _selectedDay = d),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildSchedule(dayEntries, data, groupSubjects, group, day, settings),
                        _buildSubjects(groupSubjects, data.teachers, group),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNoGroups(InstitutionSettings s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 40, color: context.palette.inkFaint),
            const SizedBox(height: 12),
            Text('No ${s.groupLabelPlural.toLowerCase()} yet', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Add your ${s.groupLabelPlural.toLowerCase()} in Settings first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.inkMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => context.push('/admin/settings'), child: const Text('Open Settings')),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SCHEDULE TAB
  // ---------------------------------------------------------------------------
  Widget _buildSchedule(List<TimetableEntry> entries, _BuilderData data, List<Subject> groupSubjects, String group, String day,
      InstitutionSettings settings) {
    return Scaffold(
      body: entries.isEmpty
          ? _buildEmptyState('No classes for $group on $day.', Icons.event_busy_outlined)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final subj = data.subjects.firstWhere(
                  (s) => s.id == entry.subjectId,
                  orElse: () =>
                      const Subject(id: '', code: '?', name: 'Unknown subject', department: '', semester: '', section: '', teacherId: ''),
                );
                return FadeSlideIn(
                  index: index,
                  child: _buildClassCard(entry, subj, groupSubjects, data.teachers, group, day, settings),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addClass',
        onPressed: () => _showClassDialog(null, groupSubjects, data.teachers, group, day, settings),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add class'),
      ),
    );
  }

  static int _minutesBetween(String start, String end) {
    int m(String t) {
      final parts = t.split(':');
      return (int.tryParse(parts.first) ?? 0) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    }

    return (m(end) - m(start)).clamp(0, 24 * 60);
  }

  Widget _buildClassCard(TimetableEntry entry, Subject subj, List<Subject> groupSubjects, List<UserAccount> teachers, String group,
      String day, InstitutionSettings settings) {
    final p = context.palette;
    final names = teachers.where((t) => entry.teacherIds.contains(t.id)).map((t) => t.name).join(', ');
    void edit() => _showClassDialog(entry, groupSubjects, teachers, group, day, settings);

    return ClassCard(
      startTime: entry.startTime,
      durationMinutes: _minutesBetween(entry.startTime, entry.endTime),
      subject: subj.name,
      meta: [
        'till ${TimeFormatter.formatTime(entry.endTime)}',
        if (entry.room.isNotEmpty) ClassCard.roomLabel(entry.room),
        if (names.isNotEmpty) names,
      ].join(' · '),
      showLive: false,
      onTap: edit,
      footer: names.isEmpty ? StatusPill(text: 'No teacher assigned', color: p.danger, background: p.dangerSoft) : null,
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: p.inkMuted),
        onSelected: (v) => v == 'edit'
            ? edit()
            : _confirmDelete(
                title: 'Delete class?',
                body: 'Remove ${subj.name} on ${entry.dayOfWeek} at ${TimeFormatter.formatTime(entry.startTime)}?',
                action: () => ref.read(timetableRepoProvider).delete(entry.id),
              ),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(child: EmptyNote(icon: icon, text: message));
  }

  Future<void> _showClassDialog(TimetableEntry? entry, List<Subject> groupSubjects, List<UserAccount> teachers, String group, String day,
      InstitutionSettings settings) async {
    if (groupSubjects.isEmpty) {
      showMessage(context, 'Add a subject for $group first, in the Subjects tab.');
      return;
    }
    final isNew = entry == null;
    String subjectId = groupSubjects.any((s) => s.id == entry?.subjectId) ? entry!.subjectId : groupSubjects.first.id;
    String classDay = entry?.dayOfWeek ?? day;
    final firstSlot = settings.periodStarts.isNotEmpty ? settings.periodStarts.first : '09:00';
    final startCtrl = TextEditingController(text: entry?.startTime ?? firstSlot);
    final endCtrl = TextEditingController(text: entry?.endTime ?? settings.endTimeFor(firstSlot));
    final roomCtrl = TextEditingController(text: entry?.room ?? '');
    final selectedTeacherIds = <String>{
      ...(entry?.teacherIds ?? [groupSubjects.first.teacherId]).where((id) => id.isNotEmpty),
    };
    bool isSaving = false;
    final timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isNew ? 'Schedule class for $group' : 'Edit class'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: subjectId,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: groupSubjects.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.code})'))).toList(),
                    onChanged: (v) => setState(() {
                      subjectId = v!;
                      // Default to the subject's lead teacher for new classes.
                      if (isNew) {
                        final lead = groupSubjects.firstWhere((s) => s.id == v).teacherId;
                        selectedTeacherIds
                          ..clear()
                          ..addAll([lead].where((id) => id.isNotEmpty));
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: settings.workingDays.contains(classDay) ? classDay : settings.workingDays.first,
                    decoration: const InputDecoration(labelText: 'Day'),
                    items: settings.workingDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => classDay = v!,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: settings.periodStarts
                        .map((t) => ChoiceChip(
                              showCheckmark: false,
                              label: Text(TimeFormatter.formatTime(t)),
                              selected: startCtrl.text == t,
                              onSelected: (_) => setState(() {
                                startCtrl.text = t;
                                endCtrl.text = settings.endTimeFor(t);
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: startCtrl,
                        decoration: const InputDecoration(labelText: 'Start (HH:MM)'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: endCtrl,
                        decoration: const InputDecoration(labelText: 'End (HH:MM)'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roomCtrl,
                    decoration: const InputDecoration(labelText: 'Room (optional)'),
                  ),
                  const SizedBox(height: 16),
                  Text('Teachers', style: TextStyle(fontSize: 13, color: context.palette.inkMuted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  if (teachers.isEmpty) const Text('No teachers yet. Add them under Users.'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: teachers
                        .map((t) => FilterChip(
                              label: Text(t.name),
                              selected: selectedTeacherIds.contains(t.id),
                              onSelected: (sel) => setState(() => sel ? selectedTeacherIds.add(t.id) : selectedTeacherIds.remove(t.id)),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final start = startCtrl.text.trim(), end = endCtrl.text.trim();
                      String? error;
                      if (!timeRe.hasMatch(start) || !timeRe.hasMatch(end)) {
                        error = 'Times must be in 24-hour HH:MM format.';
                      } else if (end.compareTo(start) <= 0) {
                        error = 'End time must be after start time.';
                      } else if (selectedTeacherIds.isEmpty) {
                        error = 'Pick at least one teacher.';
                      }
                      if (error != null) {
                        showMessage(context, error, error: true);
                        return;
                      }
                      setState(() => isSaving = true);
                      try {
                        await ref.read(timetableRepoProvider).addOrUpdate(TimetableEntry(
                              id: entry?.id ?? const Uuid().v4(),
                              subjectId: subjectId,
                              dayOfWeek: classDay,
                              startTime: start,
                              endTime: end,
                              room: roomCtrl.text.trim(),
                              section: group,
                              teacherIds: selectedTeacherIds.toList(),
                            ));
                        ref.invalidate(timetableBuilderProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setState(() => isSaving = false);
                        if (context.mounted) {
                          showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
                        }
                      }
                    },
              child:
                  isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUBJECTS TAB
  // ---------------------------------------------------------------------------
  Widget _buildSubjects(List<Subject> subjects, List<UserAccount> teachers, String group) {
    final p = context.palette;
    return Scaffold(
      body: subjects.isEmpty
          ? _buildEmptyState('No subjects for $group yet.', Icons.menu_book_outlined)
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 104),
              children: [
                for (var i = 0; i < subjects.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: () {
                      final s = subjects[i];
                      final lead = teachers.where((t) => t.id == s.teacherId).map((t) => t.name).firstOrNull;
                      return InkWell(
                        onTap: () => _showSubjectDialog(s, teachers, group),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                s.code.isEmpty ? '?' : s.code,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  Text(
                                    lead ?? 'No lead teacher',
                                    style: TextStyle(fontSize: 13, color: lead == null ? p.danger : p.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: p.inkMuted),
                              onSelected: (v) => v == 'edit'
                                  ? _showSubjectDialog(s, teachers, group)
                                  : _confirmDelete(
                                      title: 'Delete ${s.name}?',
                                      body: 'Classes already scheduled for this subject will show as "Unknown subject" until removed.',
                                      action: () => ref.read(timetableRepoProvider).deleteSubject(s.id),
                                    ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ]),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addSubject',
        onPressed: () => _showSubjectDialog(null, teachers, group),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add subject'),
      ),
    );
  }

  Future<void> _showSubjectDialog(Subject? subject, List<UserAccount> teachers, String group) async {
    final nameCtrl = TextEditingController(text: subject?.name ?? '');
    final codeCtrl = TextEditingController(text: subject?.code ?? '');
    String? leadId = teachers.any((t) => t.id == subject?.teacherId) ? subject!.teacherId : null;

    final saved = await showDialog<Subject>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(subject == null ? 'New subject for $group' : 'Edit subject'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Physics'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Short code', hintText: 'e.g. PHY'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: leadId,
                  decoration: const InputDecoration(labelText: 'Lead teacher'),
                  items: teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (v) => setState(() => leadId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || leadId == null) {
                  showMessage(ctx, 'Name and lead teacher are required.', error: true);
                  return;
                }
                final code = codeCtrl.text.trim().isEmpty
                    ? name.substring(0, name.length.clamp(0, 3)).toUpperCase()
                    : codeCtrl.text.trim().toUpperCase();
                Navigator.pop(
                  ctx,
                  Subject(
                    id: subject?.id ?? const Uuid().v4(),
                    code: code,
                    name: name,
                    department: subject?.department ?? '',
                    semester: subject?.semester ?? '',
                    section: group,
                    teacherId: leadId!,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    codeCtrl.dispose();
    if (saved == null) return;
    try {
      await ref.read(timetableRepoProvider).addOrUpdateSubject(saved);
      ref.invalidate(timetableBuilderProvider);
    } catch (e) {
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }

  Future<void> _confirmDelete({required String title, required String body, required Future<void> Function() action}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.palette.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await action();
      ref.invalidate(timetableBuilderProvider);
    } catch (e) {
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}
