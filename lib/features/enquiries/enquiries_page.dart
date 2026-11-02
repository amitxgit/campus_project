// lib/features/enquiries/enquiries_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/enquiry.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../theme.dart';
import '../admin/user_form_dialog.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../common/widgets/ui_kit.dart';
import '../parent_alerts/parent_messenger.dart';
import 'enquiry_form.dart';

final enquiriesProvider = StreamProvider.autoDispose<List<Enquiry>>((ref) {
  return ref.watch(enquiryRepoProvider).watchAll();
});

/// This month's enquiries → joined, for the admin home.
final enquiryConversionProvider = FutureProvider.autoDispose<EnquiryConversion>((ref) {
  return ref.watch(enquiryRepoProvider).conversionThisMonth();
});

/// Adds an enquiry as the signed-in staff member (admins and teachers).
Future<void> addEnquiry(BuildContext context, WidgetRef ref, {bool showStatus = false}) async {
  final me = await ref.read(authRepoProvider).currentUser();
  if (me == null || !context.mounted) return;
  final e = await showEnquiryForm(context, settings: ref.read(settingsProvider), createdBy: me.id);
  if (e == null || !context.mounted) return;
  try {
    await ref.read(enquiryRepoProvider).add(e);
    if (context.mounted) showMessage(context, 'Enquiry added', success: true);
  } catch (err) {
    if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(err), error: true);
  }
}

class EnquiriesPage extends ConsumerWidget {
  const EnquiriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(enquiriesProvider);
    final now = DateTime.now();
    final due = async.valueOrNull?.where((e) => e.isDue(now)).length ?? 0;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Enquiries'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: due > 0 ? 'Today · $due' : 'Today'),
              const Tab(text: 'All'),
              const Tab(text: 'Joined'),
              const Tab(text: 'Lost'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => addEnquiry(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New enquiry'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorWidget(
            message: FirebaseErrorParser.getMessage(e),
            onRetry: () => ref.invalidate(enquiriesProvider),
          ),
          data: (all) {
            final today = all.where((e) => e.isDue(now)).toList()
              ..sort((a, b) => a.nextFollowUp!.compareTo(b.nextFollowUp!));
            return TabBarView(children: [
              _EnquiryList(items: today, empty: 'No follow-ups due today.'),
              _EnquiryList(items: all, empty: 'No enquiries yet. Add walk-ins and calls as they come.', header: true),
              _EnquiryList(items: all.where((e) => e.status == EnquiryStatus.joined).toList(), empty: 'Nobody joined yet.'),
              _EnquiryList(items: all.where((e) => e.status == EnquiryStatus.lost).toList(), empty: 'No lost enquiries.'),
            ]);
          },
        ),
      ),
    );
  }
}

class _EnquiryList extends ConsumerWidget {
  final List<Enquiry> items;
  final String empty;
  final bool header;
  const _EnquiryList({required this.items, required this.empty, this.header = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final month = EnquiryConversion.forMonth(items, DateTime.now());
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 104),
      children: [
        if (header && month.total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              '${DateFormat('MMMM').format(DateTime.now())}: ${month.total} '
              'enquir${month.total == 1 ? 'y' : 'ies'} · ${month.joined} joined (${month.percent}%)',
              style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500),
            ),
          ),
        if (items.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 80), child: EmptyNote(icon: Icons.person_search_outlined, text: empty)),
        for (final (i, e) in items.indexed) FadeSlideIn(index: i, child: _EnquiryRow(e)),
      ],
    );
  }
}

class _EnquiryRow extends ConsumerWidget {
  final Enquiry e;
  const _EnquiryRow(this.e);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final now = DateTime.now();
    final follow = e.nextFollowUp;
    final String? when;
    Color tone = p.inkMuted;
    if (!e.status.isOpen || follow == null) {
      when = null;
    } else if (e.isOverdue(now)) {
      when = 'Overdue · ${DateFormat('d MMM').format(follow)}';
      tone = p.danger;
    } else if (e.isDue(now)) {
      when = 'Follow up today';
      tone = p.warning;
    } else {
      when = 'Follow up ${DateFormat('d MMM').format(follow)}';
    }
    final detail = [
      if (e.course.isNotEmpty) e.course,
      e.source.label,
      if (e.batch.isNotEmpty) e.batch,
    ].join(' · ');

    return InkWell(
      onTap: () => _showActions(context, ref, e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.inkMuted, fontSize: 13)),
              if (when != null) ...[
                const SizedBox(height: 2),
                Text(when, style: TextStyle(color: tone, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          _StatusMenu(e),
          IconButton(
            tooltip: 'WhatsApp',
            icon: Icon(Icons.chat_outlined, color: p.inkMuted),
            onPressed: () => _whatsApp(context, ref, e),
          ),
        ]),
      ),
    );
  }
}

/// Tap the pill to change status in one step.
class _StatusMenu extends ConsumerWidget {
  final Enquiry e;
  const _StatusMenu(this.e);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final (Color fg, Color bg) = switch (e.status) {
      EnquiryStatus.newEnquiry => (p.accent, p.accentSoft),
      EnquiryStatus.contacted || EnquiryStatus.demoBooked => (p.ink, p.surfaceRaised),
      EnquiryStatus.joined => (p.success, p.successSoft),
      EnquiryStatus.lost => (p.inkMuted, p.surface),
    };
    return PopupMenuButton<EnquiryStatus>(
      tooltip: 'Change status',
      position: PopupMenuPosition.under,
      onSelected: (s) async {
        if (s == EnquiryStatus.joined && e.studentId == null) {
          await _convert(context, ref, e);
          return;
        }
        try {
          await ref.read(enquiryRepoProvider).setStatus(e.id, s);
        } catch (err) {
          if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(err), error: true);
        }
      },
      itemBuilder: (_) => [
        for (final s in EnquiryStatus.values)
          if (s != e.status)
            PopupMenuItem(value: s, child: Text(s == EnquiryStatus.joined && e.studentId == null ? 'Joined (add student)' : s.label)),
      ],
      child: StatusPill(text: e.status.label, color: fg, background: bg),
    );
  }
}

Future<void> _whatsApp(BuildContext context, WidgetRef ref, Enquiry e) =>
    ParentMessenger.openWhatsApp(context, e.contactPhone, e.followUpMessage(ref.read(settingsProvider).name));

Future<void> _showActions(BuildContext context, WidgetRef ref, Enquiry e) async {
  final p = context.palette;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(
            [
              if (e.parentName.isNotEmpty) 'Parent ${e.parentName}',
              if (e.contactPhone.isNotEmpty) e.contactPhone,
              'Added ${DateFormat('d MMM').format(e.createdAt)}',
            ].join(' · '),
            style: TextStyle(color: p.inkMuted),
          ),
          if (e.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.notes, style: const TextStyle(height: 1.45)),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.chat_outlined),
            title: const Text('Follow up on WhatsApp'),
            onTap: () => Navigator.pop(ctx, 'whatsapp'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          if (e.studentId == null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_add_alt_1_rounded, color: p.accent),
              title: Text('Convert to student', style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'convert'),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Student fees'),
              onTap: () => Navigator.pop(ctx, 'fees'),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded, color: p.danger),
            title: Text('Delete', style: TextStyle(color: p.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'whatsapp':
      await _whatsApp(context, ref, e);
    case 'edit':
      await _edit(context, ref, e);
    case 'convert':
      await _convert(context, ref, e);
    case 'fees':
      context.push('/admin/fees/${e.studentId}');
    case 'delete':
      await _delete(context, ref, e);
  }
}

Future<void> _edit(BuildContext context, WidgetRef ref, Enquiry e) async {
  final updated = await showEnquiryForm(
    context,
    settings: ref.read(settingsProvider),
    createdBy: e.createdBy,
    initial: e,
    showStatus: true,
  );
  if (updated == null || !context.mounted) return;
  try {
    await ref.read(enquiryRepoProvider).save(updated);
  } catch (err) {
    if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(err), error: true);
  }
}

/// Opens Add User pre-filled from the enquiry, marks it joined and linked to
/// the new student, then offers to set up their fee plan.
Future<void> _convert(BuildContext context, WidgetRef ref, Enquiry e) async {
  final settings = ref.read(settingsProvider);
  final form = await showUserFormDialog(context, settings, e.toStudentDraft(const Uuid().v4()), isNew: true);
  if (form == null || !context.mounted) return;
  final String uid;
  try {
    showMessage(context, 'Creating account…');
    uid = await createUserFromForm(ref.read(authRepoProvider).createAccount, form);
    await ref.read(enquiryRepoProvider).markJoined(e.id, uid);
  } catch (err) {
    if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(err), error: true);
    return;
  }
  if (!context.mounted) return;
  if (!settings.feesEnabled) {
    showMessage(context, '${form.user.name} joined. They can sign in now.', success: true);
    return;
  }
  final setUpFees = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${form.user.name} joined'),
      content: const Text('Their account is ready. Set up their fee plan now?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set up fees')),
      ],
    ),
  );
  if (setUpFees == true && context.mounted) context.push('/admin/fees/$uid');
}

Future<void> _delete(BuildContext context, WidgetRef ref, Enquiry e) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete ${e.name}?'),
      content: const Text('The enquiry is removed. A student created from it is not affected.'),
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
    await ref.read(enquiryRepoProvider).delete(e.id);
  } catch (err) {
    if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(err), error: true);
  }
}
