// lib/features/parent_alerts/parent_messenger.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/parent_alert.dart';
import '../../core/models/user.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/phone.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';

/// One message for one student's parent.
class ParentMessage {
  final UserAccount student;
  final List<String> params;
  const ParentMessage(this.student, this.params);
}

/// Sends messages to parents the best way available:
/// - WhatsApp connected: queued and sent automatically by the server.
/// - Not connected: opens WhatsApp on this device with the message typed in,
///   so staff only have to press send. Free, no setup.
class ParentMessenger {
  static Uri whatsAppLink(String phone, String text) =>
      Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');

  static Future<void> openWhatsApp(BuildContext context, String? phone, String text) async {
    final normalized = PhoneNumber.normalize(phone);
    if (normalized == null) {
      _snack(context, 'No valid parent WhatsApp number saved for this student.');
      return;
    }
    final ok = await launchUrl(whatsAppLink(normalized, text), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) _snack(context, 'Could not open WhatsApp.');
  }

  static Future<void> send(
    BuildContext context,
    WidgetRef ref, {
    required ParentAlertKind kind,
    required List<ParentMessage> messages,
  }) async {
    final settings = ref.read(settingsProvider);
    if (!settings.parentAlertsEnabled) {
      _snack(context, 'Parent alerts are turned off in Institute Settings.');
      return;
    }
    final withPhone = messages.where((m) => PhoneNumber.normalize(m.student.parentPhone) != null).toList();
    final missing = messages.length - withPhone.length;
    if (withPhone.isEmpty) {
      _snack(context, missing == 1
          ? 'No parent WhatsApp number saved for ${messages.first.student.name}.'
          : 'None of these students have a parent WhatsApp number saved.');
      return;
    }

    if (settings.whatsappConnected) {
      try {
        final me = await ref.read(authRepoProvider).currentUser();
        await ref.read(parentAlertRepoProvider).queue(
              kind: kind,
              requestedBy: me?.id ?? '',
              items: withPhone
                  .map((m) => (studentId: m.student.id, studentName: m.student.name, params: m.params))
                  .toList(),
            );
        if (context.mounted) {
          _snack(context, 'Sending ${withPhone.length} WhatsApp message${withPhone.length == 1 ? '' : 's'}'
              '${missing > 0 ? ' ($missing without a parent number skipped)' : ''}.');
        }
      } catch (e) {
        if (context.mounted) _snack(context, FirebaseErrorParser.getMessage(e));
      }
      return;
    }

    if (withPhone.length == 1) {
      await openWhatsApp(context, withPhone.first.student.parentPhone, kind.render(withPhone.first.params));
      return;
    }
    // Several messages without automation: let staff send them one by one.
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ManualSendSheet(kind: kind, messages: withPhone, skipped: missing),
    );
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ManualSendSheet extends StatefulWidget {
  final ParentAlertKind kind;
  final List<ParentMessage> messages;
  final int skipped;
  const _ManualSendSheet({required this.kind, required this.messages, required this.skipped});

  @override
  State<_ManualSendSheet> createState() => _ManualSendSheetState();
}

class _ManualSendSheetState extends State<_ManualSendSheet> {
  final _sent = <String>{};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('${widget.kind.label} — ${widget.messages.length} parents',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Tap each to open WhatsApp with the message ready.'
            '${widget.skipped > 0 ? ' ${widget.skipped} without a parent number were skipped.' : ''}'
            ' Connect WhatsApp in Parent Alerts to send these automatically.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ...widget.messages.map((m) {
            final done = _sent.contains(m.student.id);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(done ? Icons.check_circle_rounded : Icons.chat_rounded, color: done ? Colors.green : null),
              title: Text(m.student.name),
              subtitle: Text(widget.kind.render(m.params), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  await ParentMessenger.openWhatsApp(context, m.student.parentPhone, widget.kind.render(m.params));
                  setState(() => _sent.add(m.student.id));
                },
                child: Text(done ? 'Again' : 'Send'),
              ),
            );
          }),
        ],
      ),
    );
  }
}
