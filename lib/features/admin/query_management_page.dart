// lib/features/admin/query_management_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/query_ticket.dart';
import '../../core/models/user.dart';
import '../../core/models/subject.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

final queryManagementProvider = FutureProvider.autoDispose((ref) async {
  final queryRepo = ref.watch(queryRepoProvider);
  final authRepo = ref.watch(authRepoProvider);
  final ttRepo = ref.watch(timetableRepoProvider);

  final queries = await queryRepo.allQueries();
  final users = await authRepo.allUsers();
  final subjects = await ttRepo.allSubjects();

  return {
    'queries': queries..sort((a, b) => b.createdAt.compareTo(a.createdAt)), // Newest first
    'users': users,
    'subjects': subjects,
  };
});

// -----------------------------------------------------------------------------
// PAGE W/ FILTERS
// -----------------------------------------------------------------------------

class QueryManagementPage extends ConsumerStatefulWidget {
  const QueryManagementPage({super.key});

  @override
  ConsumerState<QueryManagementPage> createState() => _QueryManagementPageState();
}

class _QueryManagementPageState extends ConsumerState<QueryManagementPage> {
  String _searchQuery = '';
  String? _selectedSubjectId;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(queryManagementProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queries'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(queryManagementProvider),
        ),
        data: (data) {
          final allQueries = data['queries'] as List<QueryTicket>;
          final usersList = data['users'] as List<UserAccount>;
          final subjectsList = data['subjects'] as List<Subject>;
          final usersMap = {for (final u in usersList) u.id: u};
          final subjectsMap = {for (final s in subjectsList) s.id: s};

          final q = _searchQuery.toLowerCase();
          final filtered = allQueries.where((t) {
            if (_selectedSubjectId == 'GENERAL' && t.subjectId != null) return false;
            if (_selectedSubjectId != null && _selectedSubjectId != 'GENERAL' && t.subjectId != _selectedSubjectId) return false;
            if (q.isEmpty) return true;
            final student = usersMap[t.raisedByStudentId];
            return t.title.toLowerCase().contains(q) ||
                t.message.toLowerCase().contains(q) ||
                (student?.name.toLowerCase().contains(q) ?? false);
          }).toList();
          List<QueryTicket> by(QueryStatus st) => filtered.where((t) => t.status == st).toList();

          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SubjectFilter(
                      value: _selectedSubjectId,
                      subjects: subjectsList,
                      onChanged: (v) => setState(() => _selectedSubjectId = v),
                    ),
                  ]),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final st in QueryStatus.values) Tab(text: '${st.label} · ${by(st).length}'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final st in QueryStatus.values) _QueryList(queries: by(st), users: usersMap, subjects: subjectsMap),
                    ],
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

/// Funnel button that filters by subject (or general questions).
class _SubjectFilter extends StatelessWidget {
  final String? value;
  final List<Subject> subjects;
  final ValueChanged<String?> onChanged;
  const _SubjectFilter({required this.value, required this.subjects, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = value != null;
    return PopupMenuButton<String?>(
      tooltip: 'Filter by subject',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        const PopupMenuItem<String?>(value: null, child: Text('All subjects')),
        const PopupMenuItem<String?>(value: 'GENERAL', child: Text('General')),
        for (final s in subjects) PopupMenuItem<String?>(value: s.id, child: Text('${s.name} · ${s.section}')),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? p.accentSoft : p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? p.accent : p.line),
        ),
        child: Icon(Icons.filter_list_rounded, color: active ? p.accent : p.inkMuted),
      ),
    );
  }
}

Color _statusTone(QueryStatus s, Palette p) => switch (s) {
      QueryStatus.open => p.warning,
      QueryStatus.inProgress => p.accent,
      QueryStatus.resolved => p.success,
      QueryStatus.rejected => p.danger,
    };

class _QueryList extends ConsumerWidget {
  final List<QueryTicket> queries;
  final Map<String, UserAccount> users;
  final Map<String, Subject> subjects;

  const _QueryList({required this.queries, required this.users, required this.subjects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    if (queries.isEmpty) {
      return const Center(child: EmptyNote(icon: Icons.inbox_outlined, text: 'Nothing here.'));
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(queryManagementProvider),
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        itemCount: queries.length,
        separatorBuilder: (_, __) => const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
        itemBuilder: (_, i) {
          final t = queries[i];
          final student = users[t.raisedByStudentId];
          final subjectName = t.subjectId != null ? (subjects[t.subjectId]?.name ?? 'Subject') : 'General';
          return FadeSlideIn(
            index: i,
            child: InkWell(
              onTap: () => _showQueryDialog(context, ref, t, student, subjectName),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      Text(DateFormat('d MMM').format(t.createdAt.toLocal()), style: TextStyle(fontSize: 12, color: p.inkFaint)),
                    ]),
                    const SizedBox(height: 4),
                    Text(t.message, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.inkMuted, fontSize: 14, height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                      [student?.name ?? 'Unknown student', if ((student?.section ?? '').isNotEmpty) student!.section!, subjectName].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.inkMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQueryDialog(BuildContext context, WidgetRef ref, QueryTicket query, UserAccount? student, String subjectName) async {
    QueryStatus newStatus = query.status;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          final p = ctx.palette;
          return AlertDialog(
            title: Text(query.title),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        student?.name ?? 'Unknown student',
                        if ((student?.section ?? '').isNotEmpty) student!.section!,
                        subjectName,
                        DateFormat('d MMM, h:mm a').format(query.createdAt.toLocal()),
                      ].join(' · '),
                      style: TextStyle(color: p.inkMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
                      child: SelectableText(query.message, style: const TextStyle(fontSize: 15, height: 1.55)),
                    ),
                    if ((student?.phone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse('tel:${student.phone}')),
                        icon: const Icon(Icons.call_outlined, size: 18),
                        label: Text('Call ${student!.phone}'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('Status', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final st in QueryStatus.values)
                          ChoiceChip(
                            label: Text(st.label),
                            selected: newStatus == st,
                            showCheckmark: false,
                            selectedColor: _statusTone(st, p).withValues(alpha: 0.16),
                            labelStyle: TextStyle(
                              color: newStatus == st ? _statusTone(st, p) : p.ink,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() => newStatus = st),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('The student is notified when the status changes.', style: TextStyle(fontSize: 12, color: p.inkMuted)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.pop(dialogContext), child: const Text('Close')),
              FilledButton(
                onPressed: isSaving || newStatus == query.status
                    ? null
                    : () async {
                        setState(() => isSaving = true);
                        try {
                          await ref.read(queryRepoProvider).updateStatus(query.id, newStatus);
                          ref.invalidate(queryManagementProvider);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (context.mounted) showMessage(context, 'Marked ${newStatus.label.toLowerCase()}.', success: true);
                        } catch (e) {
                          setState(() => isSaving = false);
                          if (dialogContext.mounted) showMessage(dialogContext, FirebaseErrorParser.getMessage(e), error: true);
                        }
                      },
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }
}
