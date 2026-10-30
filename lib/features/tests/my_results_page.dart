// lib/features/tests/my_results_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/test_result.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';

final myResultsProvider = FutureProvider.autoDispose<List<StudentResult>>((ref) async {
  final me = await ref.watch(authRepoProvider).currentUser();
  if (me == null) throw Exception('Not logged in');
  return ref.watch(testRepoProvider).resultsFor(me.id);
});

class MyResultsPage extends ConsumerWidget {
  const MyResultsPage({super.key});

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myResultsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Results')),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(myResultsProvider)),
        data: (results) {
          if (results.isEmpty) return const Center(child: Text('No results published yet.'));
          final taken = results.where((r) => !r.absent).toList();
          final avgPct = taken.isEmpty ? 0.0 : taken.fold(0.0, (s, r) => s + r.percent) / taken.length;
          final best = taken.isEmpty ? null : taken.reduce((a, b) => (a.rank ?? 1 << 30) <= (b.rank ?? 1 << 30) ? a : b);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myResultsProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _headline(context, '${avgPct.toStringAsFixed(1)}%', 'Average score'),
                        _headline(context, '${taken.length}/${results.length}', 'Tests taken'),
                        _headline(context, best?.rank == null ? '—' : '#${best!.rank}', 'Best rank'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...results.map((r) {
                  final aboveAvg = !r.absent && r.marks! >= r.average;
                  return Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.subjectName.isEmpty ? r.testName : '${r.testName} • ${r.subjectName}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              Text(
                                r.absent ? 'Absent' : '${_fmt(r.marks!)}/${_fmt(r.maxMarks)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: r.absent ? cs.error : cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (r.percent / 100).clamp(0, 1),
                              minHeight: 8,
                              color: aboveAvg ? Colors.green : Colors.orange,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              DateFormat('d MMM yyyy').format(r.date),
                              if (r.rank != null) 'Rank ${r.rank} of ${r.outOf}',
                              'Batch avg ${_fmt(r.average)}',
                              'Top ${_fmt(r.highest)}',
                            ].join(' • '),
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _headline(BuildContext context, String value, String label) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
        ],
      ),
    );
  }
}
