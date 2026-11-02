// lib/features/admin/deletion_requests_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/firebase_error_parser.dart';
import '../../data/deletion_request_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';

final pendingDeletionsProvider = StreamProvider.autoDispose<List<DeletionRequest>>((ref) {
  return ref.watch(deletionRepoProvider).watchPending();
});

/// Users who asked for their account to be deleted. Deleting removes their
/// login, profile, notifications and uploads (deleteUserAccount).
class DeletionRequestsPage extends ConsumerWidget {
  const DeletionRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingDeletionsProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Account deletion requests')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(e),
          onRetry: () => ref.invalidate(pendingDeletionsProvider),
        ),
        data: (list) => list.isEmpty
            ? const Center(child: EmptyNote(icon: Icons.verified_user_outlined, text: 'No open requests.'))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Please act within 30 days. Fee receipts, attendance and results are kept as your records.',
                      style: TextStyle(color: p.inkMuted, fontSize: 13, height: 1.4),
                    ),
                  ),
                  for (final r in list)
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          '${r.role[0].toUpperCase()}${r.role.substring(1)} · ${r.contact}',
                          'Asked ${DateFormat('d MMM').format(r.createdAt)}',
                          if (r.reason.isNotEmpty) '"${r.reason}"',
                        ].join('\n'),
                        style: TextStyle(color: p.inkMuted, fontSize: 13, height: 1.4),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => v == 'delete' ? _delete(context, ref, r) : _reject(context, ref, r),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'delete', child: Text('Delete account', style: TextStyle(color: p.danger))),
                          const PopupMenuItem(value: 'reject', child: Text('Decline')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, DeletionRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${r.name}\'s account?'),
        content: const Text('Their sign-in, profile, notifications and uploads are removed. This can\'t be undone.'),
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
      await ref.read(authRepoProvider).deleteAccount(r.userId);
      if (context.mounted) showMessage(context, 'Account deleted.', success: true);
    } catch (e) {
      if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, DeletionRequest r) async {
    try {
      final me = await ref.read(authRepoProvider).currentUser();
      await ref.read(deletionRepoProvider).reject(r.userId, me?.id ?? '');
    } catch (e) {
      if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    }
  }
}
