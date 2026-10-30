// lib/features/tests/tests_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/institution_settings.dart';
import '../../core/models/role.dart';
import '../../core/models/subject.dart';
import '../../core/models/timetable_entry.dart';
import '../../core/models/test_result.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';

typedef _TestsData = ({List<TestPaper> tests, List<String> groups, List<Subject> subjects, String myId});

final testsListProvider = FutureProvider.autoDispose<_TestsData>((ref) async {
  final me = await ref.watch(authRepoProvider).currentUser();
  if (me == null) throw Exception('Not logged in');
  final tt = ref.watch(timetableRepoProvider);
  final results = await Future.wait([
    ref.watch(testRepoProvider).recent(),
    tt.allSubjects(),
    ref.watch(settingsFutureProvider.future),
    if (me.role == UserRole.teacher) tt.forTeacher(me.id),
  ]);
  final tests = results[0] as List<TestPaper>;
  final subjects = results[1] as List<Subject>;
  final settings = results[2] as InstitutionSettings;

  List<String> groups;
  if (me.role == UserRole.teacher) {
    // Teachers see the batches they teach (plus any test they created).
    final taught = {
      ...(results[3] as List<TimetableEntry>).map((e) => e.section),
      ...subjects.where((s) => s.teacherId == me.id).map((s) => s.section),
    }..removeWhere((s) => s.isEmpty);
    groups = taught.toList()..sort();
    return (
      tests: tests.where((t) => taught.contains(t.section) || t.createdBy == me.id).toList(),
      groups: groups,
      subjects: subjects,
      myId: me.id,
    );
  }
  groups = {...settings.groups, ...subjects.map((s) => s.section)}.where((s) => s.isNotEmpty).toList()..sort();
  return (tests: tests, groups: groups, subjects: subjects, myId: me.id);
});

class TestsPage extends ConsumerStatefulWidget {
  const TestsPage({super.key});

  @override
  ConsumerState<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends ConsumerState<TestsPage> {
  String? _group;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(testsListProvider);
    final settings = ref.watch(settingsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tests & Results')),
      drawer: const AppDrawer(),
      floatingActionButton: async.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _create(async.value!),
              icon: const Icon(Icons.add),
              label: const Text('New test'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(testsListProvider)),
        data: (d) {
          final tests = d.tests.where((t) => _group == null || t.section == _group).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(testsListProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(label: const Text('All'), selected: _group == null, onSelected: (_) => setState(() => _group = null)),
                    for (final g in d.groups) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(label: Text(g), selected: _group == g, onSelected: (_) => setState(() => _group = g)),
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
                if (tests.isEmpty)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No tests yet.'))),
                ...tests.map((t) => Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: t.published ? Colors.green.withValues(alpha: 0.15) : cs.surfaceContainerHighest,
                          child: Icon(t.published ? Icons.check_rounded : Icons.edit_note_rounded,
                              color: t.published ? Colors.green : cs.onSurfaceVariant),
                        ),
                        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text([
                          t.section,
                          DateFormat('d MMM yyyy').format(t.date),
                          'Max ${t.maxMarks.toStringAsFixed(0)}',
                          if (t.published) 'Avg ${t.average.toStringAsFixed(1)}' else 'Draft',
                        ].join(' • ')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await context.push('/tests/${t.id}');
                          ref.invalidate(testsListProvider);
                        },
                      ),
                    )),
                if (d.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No ${settings.groupLabelPlural.toLowerCase()} to give tests to yet.'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _create(_TestsData d) async {
    if (d.groups.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final nameCtrl = TextEditingController();
    final maxCtrl = TextEditingController(text: '100');
    String group = _group ?? d.groups.first;
    String subject = '';
    DateTime date = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final subjects = d.subjects.where((s) => s.section == group).map((s) => s.name).toSet().toList()..sort();
          return AlertDialog(
            title: const Text('New test'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Test name', hintText: 'e.g. Weekly Test 12', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: group,
                      decoration: InputDecoration(labelText: settings.groupLabel, border: const OutlineInputBorder()),
                      items: d.groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (g) => setState(() {
                        group = g!;
                        subject = '';
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(group),
                      initialValue: subject,
                      decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All subjects / combined')),
                        ...subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      ],
                      onChanged: (s) => subject = s ?? '',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Maximum marks', border: OutlineInputBorder()),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Held on ${DateFormat('d MMM yyyy').format(date)}'),
                      trailing: TextButton(
                        child: const Text('Change'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 60)),
                          );
                          if (picked != null) setState(() => date = picked);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final max = double.tryParse(maxCtrl.text.trim()) ?? 0;
    if (nameCtrl.text.trim().isEmpty || max <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and maximum marks are required.')));
      return;
    }
    try {
      final id = await ref.read(testRepoProvider).create(TestPaper(
            id: '',
            name: nameCtrl.text.trim(),
            section: group,
            subjectName: subject,
            date: date,
            maxMarks: max,
            createdBy: d.myId,
          ));
      if (mounted) {
        await context.push('/tests/$id');
        ref.invalidate(testsListProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
        );
      }
    }
  }
}
