// lib/features/notifications/notification_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/notification.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/ui_kit.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (userId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => v == 'read' ? _markAllRead(context, ref, userId) : _confirmClear(context, ref, userId),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'read', child: Text('Mark all as read')),
                PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
            ),
          const ProfileAvatarAction(),
        ],
      ),
      drawer: const AppDrawer(),
      body: authState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(e), onRetry: () => ref.invalidate(authStateProvider)),
        data: (user) {
          if (user == null) return const SizedBox.shrink();

          return StreamBuilder<List<AppNotification>>(
            stream: ref.watch(notifRepoProvider).listenForUser(user.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AsyncErrorWidget(message: FirebaseErrorParser.getMessage(snapshot.error!), onRetry: () => ref.invalidate(notifRepoProvider));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Center(
                  child: EmptyNote(icon: Icons.notifications_none_rounded, text: "You're all caught up."),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: context.palette.dangerSoft,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(Icons.delete_outline_rounded, color: context.palette.danger),
                    ),
                    onDismissed: (_) => ref.read(notifRepoProvider).delete(item.id).catchError((Object e) {
                      if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
                    }),
                    child: _NotificationRow(
                      item: item,
                      icon: _iconFor(item.type),
                      onTap: item.read ? null : () => ref.read(notifRepoProvider).markRead(item.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref, String userId) async {
    try {
      await ref.read(notifRepoProvider).markAllRead(userId);
    } catch (e) {
      if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.palette.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(notifRepoProvider).clearForUser(userId);
      if (context.mounted) showMessage(context, 'Notifications cleared.');
    } catch (e) {
      if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    }
  }

  static IconData _iconFor(NotificationType type) => switch (type) {
        NotificationType.classChange => Icons.schedule_rounded,
        NotificationType.lowAttendance => Icons.error_outline_rounded,
        NotificationType.queryUpdate => Icons.question_answer_outlined,
        NotificationType.remarkSaved => Icons.rate_review_outlined,
        NotificationType.dailySummary => Icons.insights_rounded,
        NotificationType.general => Icons.notifications_none_rounded,
      };
}

/// Unread items get an accent dot and a bolder title; read ones go quiet.
class _NotificationRow extends StatelessWidget {
  final AppNotification item;
  final IconData icon;
  final VoidCallback? onTap;
  const _NotificationRow({required this.item, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final unread = !item.read;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: unread ? p.accentSoft : p.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: unread ? p.accent : p.inkMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      color: unread ? p.ink : p.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(item.body, style: TextStyle(fontSize: 14, color: p.inkMuted, height: 1.4)),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d MMM · h:mm a').format(item.createdAt),
                    style: TextStyle(fontSize: 12, color: p.inkFaint),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 6),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
