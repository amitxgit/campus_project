// lib/features/tests/my_results_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/test_result.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';
import '../reports/report_card_share.dart';

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
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          if (async.valueOrNull?.isNotEmpty == true)
            IconButton(
              tooltip: 'Report card (PDF)',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                final me = await ref.read(authRepoProvider).currentUser();
                if (me == null) return;
                try {
                  await shareReportCard(ref, me);
                } catch (e) {
                  if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
                }
              },
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(myResultsProvider)),
        data: (results) {
          if (results.isEmpty) {
            return const Center(child: EmptyNote(icon: Icons.emoji_events_outlined, text: 'Your test results will appear here once they are published.'));
          }
          final taken = results.where((r) => !r.absent).toList();
          final avgPct = taken.isEmpty ? 0.0 : taken.fold(0.0, (s, r) => s + r.percent) / taken.length;
          final ranked = taken.where((r) => r.rank != null).toList();
          final bestRank = ranked.isEmpty ? null : ranked.map((r) => r.rank!).reduce((a, b) => a < b ? a : b);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myResultsProvider),
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
                FadeSlideIn(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Average score', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
                        Text(
                          '${avgPct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.4, height: 1.15),
                        ),
                        const SizedBox(height: 14),
                        ProgressLine(value: avgPct / 100),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: FadeSlideIn(index: 1, child: StatBlock(value: '${taken.length}/${results.length}', label: 'Tests taken'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FadeSlideIn(
                        index: 2,
                        child: StatBlock(value: bestRank == null ? '—' : '#$bestRank', label: 'Best rank', tone: bestRank == null ? null : p.accent),
                      ),
                    ),
                  ]),
                ),
                const SectionLabel('Tests'),
                for (var i = 0; i < results.length; i++) FadeSlideIn(index: i, child: _ResultRow(r: results[i])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final StudentResult r;
  const _ResultRow({required this.r});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const fmt = MyResultsPage._fmt;
    final aboveAvg = !r.absent && r.marks! >= r.average;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  r.subjectName.isEmpty ? r.testName : '${r.testName} · ${r.subjectName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),
              if (r.absent)
                StatusPill(text: 'Absent', color: p.danger, background: p.dangerSoft)
              else
                Text.rich(TextSpan(children: [
                  TextSpan(text: fmt(r.marks!), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  TextSpan(text: ' / ${fmt(r.maxMarks)}', style: TextStyle(color: p.inkMuted, fontSize: 13)),
                ])),
            ],
          ),
          const SizedBox(height: 8),
          ProgressLine(value: r.absent ? 0 : r.percent / 100, height: 4, color: aboveAvg ? p.accent : p.warning),
          const SizedBox(height: 6),
          Text(
            [
              DateFormat('d MMM').format(r.date),
              if (r.rank != null) 'Rank ${r.rank} of ${r.outOf}',
              'Avg ${fmt(r.average)}',
              'Top ${fmt(r.highest)}',
            ].join(' · '),
            style: TextStyle(color: p.inkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
