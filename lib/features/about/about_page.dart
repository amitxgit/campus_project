// lib/features/about/about_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/ui_kit.dart';
import '../legal/legal_page.dart' show LegalLinks;
import '../../theme.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const String appVersion = '1.0.0';

  static const _features = [
    (Icons.qr_code_scanner_rounded, 'QR attendance', 'A fresh code every few seconds, so no proxies.'),
    (Icons.currency_rupee_rounded, 'Fees', 'Instalments, dues and receipts in one place.'),
    (Icons.quiz_outlined, 'Tests & results', 'Marks, ranks and progress for every student.'),
    (Icons.chat_outlined, 'Parent alerts', 'Absences and results straight to WhatsApp.'),
    (Icons.calendar_month_outlined, 'Timetable', 'Cancel or move a class and everyone knows.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('About'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          FadeSlideIn(
            child: Column(
              children: [
                const BrandMark(size: 56),
                const SizedBox(height: 14),
                Text('Batchwise', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Version $appVersion', style: TextStyle(color: p.inkMuted, fontSize: 13)),
                const SizedBox(height: 16),
                Text(
                  'Attendance, fees, tests and parent updates for coaching institutes, schools and colleges.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.inkMuted, height: 1.5),
                ),
              ],
            ),
          ),
          const SectionLabel('What it does', padding: EdgeInsets.fromLTRB(0, 32, 0, 12)),
          Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                for (var i = 0; i < _features.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Icon(_features[i].$1, color: p.ink),
                      title: Text(_features[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(_features[i].$3, style: TextStyle(color: p.inkMuted)),
                    ),
                  ),
              ],
            ),
          ),
          const SectionLabel('Built by', padding: EdgeInsets.fromLTRB(0, 32, 0, 12)),
          Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
            child: const Column(
              children: [
                _Credit(name: 'Mohit Chauhan'),
                _Credit(name: 'Yash Gulati'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const LegalLinks(),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '© ${DateTime.now().year} Batchwise',
              style: TextStyle(color: p.inkFaint, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  final String name;
  const _Credit({required this.name});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: p.surfaceRaised,
        foregroundColor: p.ink,
        child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
