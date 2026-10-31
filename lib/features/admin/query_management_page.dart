// lib/features/admin/query_management_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/query_ticket.dart';
import '../../core/models/user.dart';
import '../../core/models/subject.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/async_error_widget.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Queries'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => ref.invalidate(queryManagementProvider),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(queryManagementProvider),
        ),
        data: (data) {
          final allQueries = data['queries'] as List<QueryTicket>;
          final usersList = data['users'] as List<UserAccount>;
          final subjectsList = data['subjects'] as List<Subject>;

          final usersMap = {for (final u in usersList) u.id: u};
          final subjectsMap = {for (final s in subjectsList) s.id: s};

          // 1. Apply Search and Subject Filters First
          final filteredQueries = allQueries.where((q) {
            if (_selectedSubjectId != null && _selectedSubjectId != 'GENERAL') {
              if (q.subjectId != _selectedSubjectId) return false;
            } else if (_selectedSubjectId == 'GENERAL') {
              if (q.subjectId != null) return false;
            }

            if (_searchQuery.isNotEmpty) {
              final queryText = _searchQuery.toLowerCase();
              final student = usersMap[q.raisedByStudentId];

              final matchTitle = q.title.toLowerCase().contains(queryText);
              final matchMsg = q.message.toLowerCase().contains(queryText);
              final matchName = student?.name.toLowerCase().contains(queryText) ?? false;
              final matchRoll = student?.collegeRollNo?.toLowerCase().contains(queryText) ?? false;

              if (!matchTitle && !matchMsg && !matchName && !matchRoll) return false;
            }
            return true;
          }).toList();

          // 2. Split filtered results into Tabs
          final open = filteredQueries.where((q) => q.status == QueryStatus.open).toList();
          final inProgress = filteredQueries.where((q) => q.status == QueryStatus.inProgress).toList();
          final resolved = filteredQueries.where((q) => q.status == QueryStatus.resolved).toList();
          final rejected = filteredQueries.where((q) => q.status == QueryStatus.rejected).toList();

          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                // --- PREMIUM HEADER & FILTER BAR ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                prefixIcon: Icon(Icons.search_rounded),
                                filled: true,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: _selectedSubjectId,
                                  isExpanded: true,
                                  dropdownColor: colorScheme.surface,
                                  icon: const Icon(Icons.filter_list_rounded),
                                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('All Subjects')),
                                    const DropdownMenuItem(value: 'GENERAL', child: Text('General Queries')),
                                    ...subjectsList.map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    )),
                                  ],
                                  onChanged: (v) => setState(() => _selectedSubjectId = v),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // --- CUSTOM TAB BAR ---
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          Tab(text: 'Open (${open.length})'),
                          Tab(text: 'In Progress (${inProgress.length})'),
                          Tab(text: 'Resolved (${resolved.length})'),
                          Tab(text: 'Rejected (${rejected.length})'),
                        ],
                      ),
                    ],
                  ),
                ),

                // --- TAB VIEWS ---
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: TabBarView(
                      children: [
                        _QueryList(queries: open, users: usersMap, subjects: subjectsMap),
                        _QueryList(queries: inProgress, users: usersMap, subjects: subjectsMap),
                        _QueryList(queries: resolved, users: usersMap, subjects: subjectsMap),
                        _QueryList(queries: rejected, users: usersMap, subjects: subjectsMap),
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
}

// -----------------------------------------------------------------------------
// QUERY LIST
// -----------------------------------------------------------------------------

class _QueryList extends ConsumerWidget {
  final List<QueryTicket> queries;
  final Map<String, UserAccount> users;
  final Map<String, Subject> subjects;

  const _QueryList({
    required this.queries,
    required this.users,
    required this.subjects,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (queries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inbox_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No tickets in this queue.', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
    }

    final fmt = DateFormat('MMM d, h:mm a');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queries.length,
      itemBuilder: (_, i) {
        final query = queries[i];
        final student = users[query.raisedByStudentId];
        final subjectName = query.subjectId != null ? subjects[query.subjectId]?.name : 'General';

        final statusColor = _statusColor(query.status);
        final statusName = query.status.name.toUpperCase();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showQueryDialog(context, ref, query, student, subjectName),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Status & Date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_statusIcon(query.status), size: 12, color: statusColor),
                              const SizedBox(width: 6),
                              Text(statusName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                        Text(
                          fmt.format(query.createdAt.toLocal()),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Title & Message
                    Text(
                      query.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      query.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                    const SizedBox(height: 12),

                    // Bottom Row: Student & Subject
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                          child: Icon(Icons.person_rounded, size: 14, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${student?.name ?? 'Unknown'} ${student?.collegeRollNo != null ? '(${student!.collegeRollNo})' : ''}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subjectName ?? 'General',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MODERN QUERY DETAILS DIALOG
  // ---------------------------------------------------------------------------

  Future<void> _showQueryDialog(
      BuildContext context,
      WidgetRef ref,
      QueryTicket query,
      UserAccount? student,
      String? subjectName,
      ) async {
    QueryStatus newStatus = query.status;
    final fmt = DateFormat('EEEE, MMM d, yyyy • h:mm a');
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (statefulContext, setState) {
          final colorScheme = Theme.of(statefulContext).colorScheme;
          final isDark = Theme.of(statefulContext).brightness == Brightness.dark;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusColor(newStatus).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _statusColor(newStatus).withValues(alpha: 0.3)),
                          ),
                          child: Icon(_statusIcon(newStatus), color: _statusColor(newStatus), size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(query.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                              const SizedBox(height: 6),
                              Text(fmt.format(query.createdAt.toLocal()), style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Message Body
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        query.message,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Metadata Grid
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _DetailTile(icon: Icons.person_rounded, label: 'Student', value: student?.name ?? 'Unknown')),
                              Expanded(child: _DetailTile(icon: Icons.badge_rounded, label: 'Roll No', value: student?.collegeRollNo ?? 'N/A')),
                            ],
                          ),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                          Row(
                            children: [
                              Expanded(child: _DetailTile(icon: Icons.phone_rounded, label: 'Phone', value: student?.phone ?? 'N/A')),
                              Expanded(child: _DetailTile(icon: Icons.category_rounded, label: 'Context', value: subjectName ?? 'General')),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Action Area
                    Text('RESOLUTION STATUS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: colorScheme.primary, letterSpacing: 1.0)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<QueryStatus>(
                      initialValue: newStatus,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: QueryStatus.values.map((s) => DropdownMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            Icon(_statusIcon(s), color: _statusColor(s), size: 20),
                            const SizedBox(width: 12),
                            Text(s.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      )).toList(),
                      onChanged: (v) => setState(() => newStatus = v ?? query.status),
                    ),
                    const SizedBox(height: 32),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isSaving ? null : () async {
                            if (newStatus == query.status) {
                              Navigator.pop(dialogContext);
                              return;
                            }

                            setState(() => isSaving = true);

                            try {
                              await ref.read(queryRepoProvider).updateStatus(query.id, newStatus);
                              ref.invalidate(queryManagementProvider);

                              if (dialogContext.mounted) Navigator.pop(dialogContext);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ticket updated successfully!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              setState(() => isSaving = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          icon: isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(isSaving ? 'Saving...' : 'Apply Update', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
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

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  static Color _statusColor(QueryStatus s) {
    switch (s) {
      case QueryStatus.open: return Colors.orange;
      case QueryStatus.inProgress: return Colors.blue;
      case QueryStatus.resolved: return Colors.green;
      case QueryStatus.rejected: return Colors.red;
    }
  }

  static IconData _statusIcon(QueryStatus s) {
    switch (s) {
      case QueryStatus.open: return Icons.mark_email_unread_rounded;
      case QueryStatus.inProgress: return Icons.pending_actions_rounded;
      case QueryStatus.resolved: return Icons.check_circle_rounded;
      case QueryStatus.rejected: return Icons.cancel_rounded;
    }
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}