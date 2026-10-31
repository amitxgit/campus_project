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
import '../common/widgets/ui_kit.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------
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
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timetable', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: const [ProfileAvatarAction()],
          elevation: 0,
          scrolledUnderElevation: 0,
          bottom: const TabBar(tabs: [Tab(text: 'Schedule'), Tab(text: 'Subjects')]),
        ),
        drawer: const AppDrawer(),
        body: asyncData.when(
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
            final groupSubjects = data.subjects.where((s) => s.section == group).toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            final dayEntries = data.entries
                .where((e) => e.section == group && e.dayOfWeek == day)
                .toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));

            return Column(
              children: [
                // --- GROUP + DAY SELECTOR ---
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: group,
                        decoration: InputDecoration(
                          labelText: settings.groupLabel,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.groups_rounded),
                          isDense: true,
                        ),
                        items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                        onChanged: (g) => setState(() => _selectedGroup = g),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: days.map((d) {
                            final isSel = d == day;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8, bottom: 12),
                              child: FilterChip(
                                label: Text(d),
                                selected: isSel,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _selectedDay = d),
                                backgroundColor: colorScheme.surface,
                                selectedColor: colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: isSel ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
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
    );
  }

  Widget _buildNoGroups(InstitutionSettings s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, size: 64),
            const SizedBox(height: 16),
            Text('No ${s.groupLabelPlural.toLowerCase()} yet', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Add your ${s.groupLabelPlural.toLowerCase()} in Institute Settings first.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/admin/settings'),
              child: const Text('Open Institute Settings'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SCHEDULE TAB
  // ---------------------------------------------------------------------------
  Widget _buildSchedule(List<TimetableEntry> entries, _BuilderData data, List<Subject> groupSubjects,
      String group, String day, InstitutionSettings settings) {
    return Scaffold(
      body: entries.isEmpty
          ? _buildEmptyState('No classes for $group on $day.', Icons.event_busy_rounded)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final subj = data.subjects.firstWhere(
                  (s) => s.id == entry.subjectId,
                  orElse: () => const Subject(id: '', code: '?', name: 'Unknown subject', department: '', semester: '', section: '', teacherId: ''),
                );
                return _buildTimelineCard(entry, subj, groupSubjects, data.teachers, group, day, settings);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addClass',
        onPressed: () => _showClassDialog(null, groupSubjects, data.teachers, group, day, settings),
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
    );
  }

  Widget _buildTimelineCard(TimetableEntry entry, Subject subj, List<Subject> groupSubjects,
      List<UserAccount> teachers, String group, String day, InstitutionSettings settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final names = teachers.where((t) => entry.teacherIds.contains(t.id)).map((t) => t.name).join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 12),
                Text(entry.startTime, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: colorScheme.primary)),
                Text(entry.endTime, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(subj.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: Icon(Icons.edit_outlined, size: 20, color: colorScheme.secondary),
                        onPressed: () => _showClassDialog(entry, groupSubjects, teachers, group, day, settings),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                        onPressed: () => _confirmDelete(
                          title: 'Delete class?',
                          body: 'Remove ${subj.name} on ${entry.dayOfWeek} at ${entry.startTime}?',
                          action: () => ref.read(timetableRepoProvider).delete(entry.id),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (entry.room.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.room, size: 14, color: colorScheme.tertiary),
                          const SizedBox(width: 4),
                          Text(entry.room, style: TextStyle(fontSize: 12, color: colorScheme.tertiary, fontWeight: FontWeight.bold)),
                        ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(names.isEmpty ? Icons.person_off_rounded : Icons.person_rounded,
                            size: 14, color: names.isEmpty ? colorScheme.error : colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(names.isEmpty ? 'No teacher assigned' : names,
                            style: TextStyle(fontSize: 12, color: names.isEmpty ? colorScheme.error : colorScheme.onSurfaceVariant)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _showClassDialog(TimetableEntry? entry, List<Subject> groupSubjects,
      List<UserAccount> teachers, String group, String day, InstitutionSettings settings) async {
    if (groupSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add a subject for $group first (Subjects tab).')),
      );
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
                    decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
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
                    decoration: const InputDecoration(labelText: 'Day', border: OutlineInputBorder()),
                    items: settings.workingDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => classDay = v!,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: settings.periodStarts
                        .map((t) => ChoiceChip(
                              label: Text(t),
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
                        decoration: const InputDecoration(labelText: 'Start (HH:MM)', border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: endCtrl,
                        decoration: const InputDecoration(labelText: 'End (HH:MM)', border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roomCtrl,
                    decoration: const InputDecoration(labelText: 'Room (optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Teachers', style: TextStyle(fontWeight: FontWeight.bold)),
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
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
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
    return Scaffold(
      body: subjects.isEmpty
          ? _buildEmptyState('No subjects for $group yet.', Icons.menu_book_rounded)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: subjects.map((s) {
                final lead = teachers.where((t) => t.id == s.teacherId).map((t) => t.name).firstOrNull;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(s.code.isEmpty ? '?' : s.code.substring(0, 1))),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${s.code} • ${lead ?? 'No lead teacher'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showSubjectDialog(s, teachers, group)),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                          onPressed: () => _confirmDelete(
                            title: 'Delete ${s.name}?',
                            body: 'Classes already scheduled for this subject will show as "Unknown subject" until removed.',
                            action: () => ref.read(timetableRepoProvider).deleteSubject(s.id),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addSubject',
        onPressed: () => _showSubjectDialog(null, teachers, group),
        icon: const Icon(Icons.add),
        label: const Text('Add Subject'),
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
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Physics', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Short code', hintText: 'e.g. PHY', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: leadId,
                  decoration: const InputDecoration(labelText: 'Lead teacher', border: OutlineInputBorder()),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and lead teacher are required.')));
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
