// lib/features/tests/test_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/parent_alert.dart';
import '../../core/models/test_result.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../parent_alerts/parent_messenger.dart';

typedef _Detail = ({TestPaper test, List<UserAccount> students, Map<String, double?> marks});

final testDetailProvider = FutureProvider.autoDispose.family<_Detail, String>((ref, id) async {
  final repo = ref.watch(testRepoProvider);
  final test = await repo.byId(id);
  if (test == null) throw Exception('Test not found');
  final results = await Future.wait([
    ref.watch(authRepoProvider).studentsInSection(test.section, limit: 500),
    repo.marks(id),
  ]);
  return (test: test, students: results[0] as List<UserAccount>, marks: results[1] as Map<String, double?>);
});

/// Mark entry for one test: type marks (or tick absent), save as draft, then
/// publish to rank everyone and show students their results.
class TestDetailPage extends ConsumerStatefulWidget {
  final String testId;
  const TestDetailPage({super.key, required this.testId});

  @override
  ConsumerState<TestDetailPage> createState() => _TestDetailPageState();
}

class _TestDetailPageState extends ConsumerState<TestDetailPage> {
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _absent = {};
  bool _loaded = false;
  bool _busy = false;
  bool _dirty = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(_Detail d) {
    if (_loaded) return;
    _loaded = true;
    for (final s in d.students) {
      final has = d.marks.containsKey(s.id);
      final m = d.marks[s.id];
      if (has && m == null) _absent.add(s.id);
      _ctrls[s.id] = TextEditingController(text: m == null ? '' : _fmt(m));
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Current marks from the form. Returns null and shows an error if any
  /// value is invalid.
  Map<String, double?>? _collect(_Detail d, {required bool requireAll}) {
    final out = <String, double?>{};
    for (final s in d.students) {
      if (_absent.contains(s.id)) {
        out[s.id] = null;
        continue;
      }
      final text = _ctrls[s.id]!.text.trim();
      if (text.isEmpty) {
        if (requireAll) {
          _snack('Enter marks for ${s.name}, or mark them absent.');
          return null;
        }
        continue;
      }
      final v = double.tryParse(text);
      if (v == null || v < 0 || v > d.test.maxMarks) {
        _snack('${s.name}: marks must be between 0 and ${_fmt(d.test.maxMarks)}.');
        return null;
      }
      out[s.id] = v;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(testDetailProvider(widget.testId));
    final p = context.palette;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard unsaved marks?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(async.valueOrNull?.test.title ?? 'Test'),
          actions: [
            if (async.hasValue)
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'parents' => _sendToParents(async.value!),
                  'unpublish' => _unpublish(async.value!),
                  'delete' => _delete(async.value!),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (async.value!.test.published) const PopupMenuItem(value: 'parents', child: Text('Send results to parents')),
                  if (async.value!.test.published) const PopupMenuItem(value: 'unpublish', child: Text('Hide from students')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete test')),
                ],
              ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(testDetailProvider(widget.testId))),
          data: (d) {
            _load(d);
            final t = d.test;
            final ranks = t.published ? rankScores(d.marks).ranks : const <String, int>{};
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.published ? p.successSoft : p.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text('${t.section} · ${DateFormat('d MMM yyyy').format(t.date)} · out of ${_fmt(t.maxMarks)}', style: TextStyle(color: p.inkMuted)),
                      if (t.published)
                        Text('Published · ${t.appeared} appeared · avg ${t.average.toStringAsFixed(1)} · top ${_fmt(t.highest)}',
                            style: TextStyle(color: p.success, fontWeight: FontWeight.w600))
                      else
                        const Text('Draft · students can\'t see this yet', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: d.students.isEmpty
                      ? Center(child: Text('No students in ${t.section}.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: d.students.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final s = d.students[i];
                            final absent = _absent.contains(s.id);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 36,
                                    child: Text(ranks[s.id] == null ? '' : '#${ranks[s.id]}',
                                        style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  SizedBox(
                                    width: 120,
                                    child: TextField(
                                      controller: _ctrls[s.id],
                                      enabled: !absent,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                      textAlign: TextAlign.center,
                                      textInputAction: TextInputAction.next,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: absent ? 'AB' : '—',
                                        suffixText: '/${_fmt(t.maxMarks)}',
                                      ),
                                      onChanged: (_) => _dirty = true,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilterChip(
                                    label: const Text('Absent'),
                                    selected: absent,
                                    onSelected: (v) => setState(() {
                                      _dirty = true;
                                      v ? _absent.add(s.id) : _absent.remove(s.id);
                                    }),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: async.hasValue && async.value!.students.isNotEmpty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _save(async.value!),
                        child: const Text('Save draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _publish(async.value!),
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(async.value!.test.published ? 'Update results' : 'Publish results'),
                      ),
                    ),
                  ]),
                ),
              )
            : null,
      ),
    );
  }

  Future<void> _save(_Detail d) async {
    final marks = _collect(d, requireAll: false);
    if (marks == null) return;
    await _run(() async {
      await ref.read(testRepoProvider).saveMarks(d.test.id, marks);
      _dirty = false;
      _snack('Draft saved.');
    });
  }

  Future<void> _publish(_Detail d) async {
    final marks = _collect(d, requireAll: true);
    if (marks == null) return;
    await _run(() async {
      final stats = await ref.read(testRepoProvider).publish(d.test, marks);
      _dirty = false;
      ref.invalidate(testDetailProvider(widget.testId));
      _snack('Published. ${stats.appeared} appeared, average ${stats.average.toStringAsFixed(1)}.');
    });
  }

  Future<void> _unpublish(_Detail d) => _run(() async {
        await ref.read(testRepoProvider).unpublish(d.test.id, d.students.map((s) => s.id));
        ref.invalidate(testDetailProvider(widget.testId));
      });

  Future<void> _delete(_Detail d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${d.test.name}?'),
        content: const Text('Marks and published results for this test will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(testRepoProvider).delete(d.test.id, d.students.map((s) => s.id));
      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    });
  }

  Future<void> _sendToParents(_Detail d) async {
    final settings = ref.read(settingsProvider);
    final stats = rankScores(d.marks);
    await ParentMessenger.send(context, ref, kind: ParentAlertKind.testResult, messages: [
      for (final s in d.students)
        if (d.marks.containsKey(s.id))
          ParentMessage(s, [
            s.name,
            d.marks[s.id] == null
                ? 'Absent'
                : '${_fmt(d.marks[s.id]!)}/${_fmt(d.test.maxMarks)} (Rank ${stats.ranks[s.id]} of ${stats.appeared})',
            d.test.title,
            settings.name,
          ]),
    ]);
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
