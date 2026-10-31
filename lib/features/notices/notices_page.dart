// lib/features/notices/notices_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/notice.dart';
import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../main.dart';

// --- PROVIDER ---
final noticesProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) return [];

  // Students only receive notices meant for them or everyone.
  return ref.watch(noticeRepoProvider).visibleTo(user.role);
});

// --- MAIN PAGE ---
class NoticesPage extends ConsumerWidget {
  const NoticesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotices = ref.watch(noticesProvider);
    final userAsync = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notices'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[100],
      body: asyncNotices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (notices) {
          if (notices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('No notices available.', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(noticesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notices.length,
              itemBuilder: (ctx, i) {
                final notice = notices[i];
                final user = userAsync.valueOrNull;
                final canDelete = user != null &&
                    (user.role == UserRole.admin || user.isAdmin || notice.authorId == user.id);
                return _NoticeCard(
                  notice: notice,
                  onDelete: canDelete ? () => _confirmDelete(context, ref, notice) : null,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: userAsync.maybeWhen(
        data: (user) {
          if (user != null && user.role != UserRole.student) {
            return FloatingActionButton.extended(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              onPressed: () => _showAddNoticeDialog(context, user),
              icon: const Icon(Icons.add),
              label: const Text('Post Notice'),
            );
          }
          return null;
        },
        orElse: () => null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Notice notice) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notice?'),
        content: Text('"${notice.title}" will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(noticeRepoProvider).delete(notice.id);
      ref.invalidate(noticesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showAddNoticeDialog(BuildContext context, UserAccount currentUser) {
    showDialog(
      context: context,
      builder: (ctx) => _AddNoticeDialog(currentUser: currentUser),
    );
  }
}

// --- PROFESSIONAL NOTICE CARD UI ---
class _NoticeCard extends StatelessWidget {
  final Notice notice;
  final VoidCallback? onDelete;
  const _NoticeCard({required this.notice, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final title = notice.title;
    final content = notice.content;
    final authorName = notice.authorName;
    final authorRole = notice.authorRole;
    final dateStr = DateFormat('MMM d, yyyy').format(notice.createdAt);

    Color badgeColor = Colors.grey;
    String badgeText = 'All Users';
    if (notice.audience == NoticeAudience.students) {
      badgeColor = Colors.blue;
      badgeText = 'Students Only';
    } else if (notice.audience == NoticeAudience.teachers) {
      badgeColor = Colors.orange;
      badgeText = 'Teachers Only';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.indigo.shade100,
                      child: Text(
                        authorName.isNotEmpty ? authorName[0].toUpperCase() : 'A',
                        style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(authorRole.toString().toUpperCase(), style: TextStyle(color: Colors.grey.shade600, fontSize: 10, letterSpacing: 0.5)),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),

            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onDelete != null) ...[
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade500),
                    tooltip: 'Delete notice',
                    visualDensity: VisualDensity.compact,
                  ),
                  const Spacer(),
                ],
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// --- STATEFUL CREATE DIALOG ---
class _AddNoticeDialog extends ConsumerStatefulWidget {
  final UserAccount currentUser;
  const _AddNoticeDialog({required this.currentUser});

  @override
  ConsumerState<_AddNoticeDialog> createState() => _AddNoticeDialogState();
}

class _AddNoticeDialogState extends ConsumerState<_AddNoticeDialog> {
  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();
  NoticeAudience _selectedTarget = NoticeAudience.all;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New notice'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send to:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            DropdownButtonFormField<NoticeAudience>(
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              initialValue: _selectedTarget,
              items: const [
                DropdownMenuItem(value: NoticeAudience.all, child: Text('Everyone (All Users)')),
                DropdownMenuItem(value: NoticeAudience.students, child: Text('Students Only')),
                DropdownMenuItem(value: NoticeAudience.teachers, child: Text('Teachers Only')),
              ],
              onChanged: (val) => setState(() => _selectedTarget = val!),
            ),
            const SizedBox(height: 16),

            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: 'Message Content', border: OutlineInputBorder()), maxLines: 4),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
          onPressed: _isLoading ? null : _submitNotice,
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send, size: 18),
          label: const Text('Publish'),
        ),
      ],
    );
  }

  Future<void> _submitNotice() async {
    if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(noticeRepoProvider).create(Notice(
        id: '',
        title: titleCtrl.text.trim(),
        content: contentCtrl.text.trim(),
        audience: _selectedTarget,
        authorId: widget.currentUser.id,
        authorName: widget.currentUser.name,
        authorRole: widget.currentUser.role.key,
        createdAt: DateTime.now(),
      ));

      ref.invalidate(noticesProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice published successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}