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
import '../../theme.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/ui_kit.dart';

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
    final p = context.palette;
    final connected = settings.whatsappConnected;

    return Scaffold(
      appBar: AppBar(title: const Text('Parent alerts')),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentAlertsProvider),
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            if (!settings.parentAlertsEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _Banner(
                  icon: Icons.info_outline_rounded,
                  text: 'Parent alerts are switched off in Settings.',
                  color: p.warning,
                  background: p.warningSoft,
                ),
              ),

            // Connection status.
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: connected ? p.successSoft : p.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          connected ? Icons.check_rounded : Icons.chat_outlined,
                          color: connected ? p.success : p.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? 'WhatsApp connected' : 'WhatsApp not connected',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, letterSpacing: -0.2),
                            ),
                            if (connected) Text(settings.whatsappSender, style: TextStyle(color: p.inkMuted, fontSize: 13)),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      connected
                          ? 'Messages to parents go out automatically from your WhatsApp Business number.'
                          : 'Until you connect, each message opens in WhatsApp on this phone, ready to send. '
                              'Connect a WhatsApp Business account to send automatically.',
                      style: TextStyle(color: p.inkMuted, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton(
                        onPressed: _busy ? null : _connect,
                        child: Text(connected ? 'Update credentials' : 'Connect WhatsApp'),
                      ),
                      if (connected) ...[
                        OutlinedButton(onPressed: _busy ? null : _sendTest, child: const Text('Send test')),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: p.danger),
                          onPressed: _busy ? null : _disconnect,
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),

            const SectionLabel('Automatic'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: p.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                    title: const Text('Absence alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      connected ? 'Message parents the first time their child is marked absent each day.' : 'Needs WhatsApp connected.',
                      style: TextStyle(color: p.inkMuted, fontSize: 13),
                    ),
                    value: settings.autoAbsenceAlerts && connected,
                    onChanged: connected && settings.parentAlertsEnabled
                        ? (v) => _saveSettings(settings.copyWith(autoAbsenceAlerts: v))
                        : null,
                  ),
                  Divider(indent: 16, endIndent: 16, color: p.line),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: const Text('Message templates', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('For Meta Business Manager · Utility · English', style: TextStyle(color: p.inkMuted, fontSize: 13)),
                      children: [
                        for (final k in ParentAlertKind.values)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(k.templateName, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text(k.templateBody, style: TextStyle(color: p.inkMuted, fontSize: 13, height: 1.4)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy',
                                  icon: Icon(Icons.copy_rounded, size: 18, color: p.inkMuted),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: k.templateBody));
                                    showMessage(context, 'Template copied');
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),

            const SectionLabel('Recently sent', padding: EdgeInsets.fromLTRB(20, 28, 20, 4)),
            alerts.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(FirebaseErrorParser.getMessage(e), style: TextStyle(color: p.danger)),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text('Nothing sent yet.', style: TextStyle(color: p.inkMuted)),
                    )
                  : Column(children: [for (final a in list) _AlertRow(alert: a)]),
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
                  decoration: const InputDecoration(labelText: 'Business WhatsApp number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number ID'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Permanent access token',
                    helperText: 'Stored securely; it cannot be viewed again.',
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
          decoration: const InputDecoration(labelText: 'Your mobile number'),
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
    if (mounted) showMessage(context, text);
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  const _Banner({required this.icon, required this.text, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// One automatic alert: what and to whom, when, and how it went.
class _AlertRow extends StatelessWidget {
  final ParentAlert alert;
  const _AlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = alert;
    final (String label, Color fg, Color bg) = switch (a.status) {
      ParentAlertStatus.sent => ('Sent', p.success, p.successSoft),
      ParentAlertStatus.pending => ('Sending', p.inkMuted, p.surfaceRaised),
      ParentAlertStatus.noPhone => ('No parent number', p.warning, p.warningSoft),
      ParentAlertStatus.notConfigured => ('Not connected', p.warning, p.warningSoft),
      ParentAlertStatus.failed => ('Failed', p.danger, p.dangerSoft),
      ParentAlertStatus.rejected => ('Rejected', p.danger, p.dangerSoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${a.kind.label} · ${DateFormat('d MMM, h:mm a').format(a.createdAt)}',
                  style: TextStyle(fontSize: 13, color: p.inkMuted),
                ),
                if (a.error != null) ...[
                  const SizedBox(height: 4),
                  Text(a.error!, style: TextStyle(fontSize: 12, color: p.danger)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusPill(text: label, color: fg, background: bg),
        ],
      ),
    );
  }
}
