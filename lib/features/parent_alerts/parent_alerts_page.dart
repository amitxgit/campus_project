// lib/features/parent_alerts/parent_alerts_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/institution_settings.dart';
import '../../core/models/parent_alert.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/phone.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';

final recentAlertsProvider = FutureProvider.autoDispose<List<ParentAlert>>((ref) {
  return ref.watch(parentAlertRepoProvider).recent();
});

class ParentAlertsPage extends ConsumerStatefulWidget {
  const ParentAlertsPage({super.key});

  @override
  ConsumerState<ParentAlertsPage> createState() => _ParentAlertsPageState();
}

class _ParentAlertsPageState extends ConsumerState<ParentAlertsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final alerts = ref.watch(recentAlertsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Parent alerts')),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentAlertsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!settings.parentAlertsEnabled)
              Card(
                color: cs.errorContainer,
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Parent alerts are switched off in Institute Settings.'),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(settings.whatsappConnected ? Icons.check_circle_rounded : Icons.chat_rounded,
                          color: settings.whatsappConnected ? Colors.green : cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          settings.whatsappConnected
                              ? 'WhatsApp connected (${settings.whatsappSender})'
                              : 'WhatsApp not connected',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      settings.whatsappConnected
                          ? 'Messages to parents are sent automatically from your WhatsApp Business number.'
                          : 'Until you connect, the app opens WhatsApp on your phone with each message ready to send. '
                              'Connect a WhatsApp Business account to send automatically.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _connect,
                        icon: const Icon(Icons.link_rounded),
                        label: Text(settings.whatsappConnected ? 'Update credentials' : 'Connect WhatsApp'),
                      ),
                      if (settings.whatsappConnected) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _sendTest,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Send test'),
                        ),
                        TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
            Card(
              child: SwitchListTile(
                title: const Text('Automatic absence alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(settings.whatsappConnected
                    ? 'Message parents the first time their child is marked absent each day.'
                    : 'Needs WhatsApp connected.'),
                value: settings.autoAbsenceAlerts && settings.whatsappConnected,
                onChanged: settings.whatsappConnected && settings.parentAlertsEnabled
                    ? (v) => _saveSettings(settings.copyWith(autoAbsenceAlerts: v))
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Message templates', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Register these in Meta Business Manager (category: Utility, language: English)'),
              children: ParentAlertKind.values
                  .map((k) => ListTile(
                        title: Text(k.templateName, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        subtitle: Text(k.templateBody),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: k.templateBody));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template copied')));
                          },
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('Recent automatic alerts', style: TextStyle(fontWeight: FontWeight.w900)),
            alerts.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text(FirebaseErrorParser.getMessage(e)),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nothing sent yet.'))
                  : Column(
                      children: list.map((a) {
                        final (IconData icon, Color color, String label) = switch (a.status) {
                          ParentAlertStatus.sent => (Icons.done_all_rounded, Colors.green, 'Sent'),
                          ParentAlertStatus.pending => (Icons.schedule_rounded, cs.onSurfaceVariant, 'Sending'),
                          ParentAlertStatus.noPhone => (Icons.phone_disabled_rounded, Colors.orange, 'No parent number'),
                          ParentAlertStatus.notConfigured => (Icons.link_off_rounded, Colors.orange, 'WhatsApp not connected'),
                          ParentAlertStatus.failed => (Icons.error_outline_rounded, cs.error, 'Failed'),
                          ParentAlertStatus.rejected => (Icons.block_rounded, cs.error, 'Rejected'),
                        };
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon, color: color),
                          title: Text('${a.kind.label} • ${a.studentName}'),
                          subtitle: Text(
                            '${DateFormat('d MMM, h:mm a').format(a.createdAt)} • $label${a.error != null ? '\n${a.error}' : ''}',
                          ),
                          isThreeLine: a.error != null,
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings(InstitutionSettings updated) async {
    setState(() => _busy = true);
    try {
      await ref.read(settingsRepoProvider).save(updated);
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final idCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect WhatsApp Business'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('From Meta for Developers → your app → WhatsApp → API Setup.'),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Business WhatsApp number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Permanent access token',
                    helperText: 'Stored securely; it cannot be viewed again.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final number = PhoneNumber.normalize(numberCtrl.text);
    if (number == null || idCtrl.text.trim().isEmpty || tokenCtrl.text.trim().isEmpty) {
      _snack('All three fields are required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(parentAlertRepoProvider).saveWhatsAppCredentials(
            phoneNumberId: idCtrl.text.trim(),
            token: tokenCtrl.text.trim(),
          );
      await ref.read(settingsRepoProvider).save(ref.read(settingsProvider).copyWith(whatsappSender: '+$number'));
      _snack('WhatsApp connected. Send a test to check it works.');
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTest() async {
    final ctrl = TextEditingController();
    final to = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send a test message'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Your mobile number', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Send')),
        ],
      ),
    );
    if (to == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(parentAlertRepoProvider).sendTest(to);
      _snack('Test sent. Check WhatsApp on that phone.');
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await ref.read(parentAlertRepoProvider).deleteWhatsAppCredentials();
      await ref.read(settingsRepoProvider).save(
            ref.read(settingsProvider).copyWith(whatsappSender: '', autoAbsenceAlerts: false),
          );
      _snack('WhatsApp disconnected.');
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
