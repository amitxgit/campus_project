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
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Tests')),
      drawer: const AppDrawer(),
      floatingActionButton: async.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _create(async.value!),
              icon: const Icon(Icons.add_rounded),
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
              padding: const EdgeInsets.only(top: 4, bottom: 104),
              children: [
                if (d.groups.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final g in <String?>[null, ...d.groups])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(g ?? 'All'),
                              selected: _group == g,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _group = g),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (d.groups.isEmpty)
                  EmptyNote(
                    icon: Icons.groups_outlined,
                    text: 'No ${settings.groupLabelPlural.toLowerCase()} to give tests to yet.',
                  )
                else if (tests.isEmpty)
                  const EmptyNote(icon: Icons.quiz_outlined, text: 'No tests yet. Create one to start entering marks.'),
                for (var i = 0; i < tests.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: _TestRow(
                      test: tests[i],
                      onTap: () async {
                        await context.push('/tests/${tests[i].id}');
                        ref.invalidate(testsListProvider);
                      },
                    ),
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
                      decoration: const InputDecoration(labelText: 'Test name', hintText: 'e.g. Weekly Test 12'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: group,
                      decoration: InputDecoration(labelText: settings.groupLabel),
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
                      decoration: const InputDecoration(labelText: 'Subject'),
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
                      decoration: const InputDecoration(labelText: 'Maximum marks'),
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
      if (mounted) showMessage(context, 'Name and maximum marks are required.', error: true);
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
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}

/// One test: date on the left, name and batch, then its average or "Draft".
class _TestRow extends StatelessWidget {
  final TestPaper test;
  final VoidCallback onTap;
  const _TestRow({required this.test, required this.onTap});

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = test;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('d').format(t.date),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.1),
                    ),
                    Text(DateFormat('MMM').format(t.date), style: TextStyle(fontSize: 12, color: p.inkMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${t.section} · out of ${_fmt(t.maxMarks)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (t.published)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_fmt(t.average), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('avg', style: TextStyle(fontSize: 12, color: p.inkMuted)),
                  ],
                )
              else
                StatusPill(text: 'Draft', color: p.warning, background: p.warningSoft),
            ],
          ),
        ),
      ),
    );
  }
}
