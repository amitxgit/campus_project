// lib/features/notices/notices_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/notice.dart';
import '../../core/models/role.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';

final noticesProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) return [];

  // Students only receive notices meant for them or everyone.
  return ref.watch(noticeRepoProvider).visibleTo(user.role);
});

class NoticesPage extends ConsumerWidget {
  const NoticesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotices = ref.watch(noticesProvider);
    final userAsync = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notices')),
      body: asyncNotices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(noticesProvider),
        ),
        data: (notices) {
          if (notices.isEmpty) {
            return const Center(child: EmptyNote(icon: Icons.campaign_outlined, text: 'No notices yet.'));
          }

          final user = userAsync.valueOrNull;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(noticesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 104),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(),
              ),
              itemBuilder: (ctx, i) {
                final notice = notices[i];
                final canDelete = user != null &&
                    (user.role == UserRole.admin || user.isAdmin || notice.authorId == user.id);
                return FadeSlideIn(
                  index: i,
                  child: _NoticeItem(
                    notice: notice,
                    isNew: DateTime.now().difference(notice.createdAt).inHours < 48,
                    onDelete: canDelete ? () => _confirmDelete(context, ref, notice) : null,
                  ),
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
              onPressed: () => _showAddNoticeDialog(context, user),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New notice'),
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.palette.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(noticeRepoProvider).delete(notice.id);
      ref.invalidate(noticesProvider);
    } catch (e) {
      if (context.mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
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

/// One notice as plain, readable text: who it's for (when not everyone),
/// the title, the message, then author and date.
class _NoticeItem extends StatelessWidget {
  final Notice notice;
  final bool isNew;
  final VoidCallback? onDelete;
  const _NoticeItem({required this.notice, required this.isNew, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final audience = switch (notice.audience) {
      NoticeAudience.students => 'Students',
      NoticeAudience.teachers => 'Teachers',
      NoticeAudience.all => null,
    };
    final author = notice.authorName.isEmpty ? 'Office' : notice.authorName;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, onDelete == null ? 20 : 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNew || audience != null) ...[
                  Wrap(spacing: 6, children: [
                    if (isNew) StatusPill(text: 'New', color: p.onAccent, background: p.accent),
                    if (audience != null) StatusPill(text: audience, color: p.inkMuted, background: p.surfaceRaised),
                  ]),
                  const SizedBox(height: 8),
                ],
                Text(notice.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, letterSpacing: -0.2)),
                const SizedBox(height: 6),
                Text(notice.content, style: TextStyle(fontSize: 15, height: 1.5, color: p.ink)),
                const SizedBox(height: 10),
                Text(
                  '$author · ${DateFormat('d MMM yyyy').format(notice.createdAt)}',
                  style: TextStyle(color: p.inkMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: p.inkFaint, size: 20),
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
        ],
      ),
    );
  }
}

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
  void dispose() {
    titleCtrl.dispose();
    contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: const Text('New notice'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send to', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final (a, label) in const [
                    (NoticeAudience.all, 'Everyone'),
                    (NoticeAudience.students, 'Students'),
                    (NoticeAudience.teachers, 'Teachers'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _selectedTarget == a,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selectedTarget = a),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isLoading ? null : _submitNotice,
          child: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Post'),
        ),
      ],
    );
  }

  Future<void> _submitNotice() async {
    if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
      showMessage(context, 'Add a title and a message.', error: true);
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
        showMessage(context, 'Notice posted.', success: true);
      }
    } catch (e) {
      if (mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}