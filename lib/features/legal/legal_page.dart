// lib/features/legal/legal_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'legal_texts.dart';

/// /legal/privacy, /legal/terms, /legal/delete-account. Open to signed-out
/// users too (linked from the login screen).
class LegalPage extends StatelessWidget {
  final String slug;
  const LegalPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final doc = legalDocs.firstWhere((d) => d.slug == slug, orElse: () => privacyPolicy);
    final body = TextStyle(height: 1.55, color: p.ink, fontSize: 15);

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
        children: [
          Text('Last updated $kLegalUpdated', style: TextStyle(color: p.inkMuted, fontSize: 13)),
          const SizedBox(height: 16),
          Text(doc.intro, style: body),
          for (final s in doc.sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 8),
              child: Text(s.heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
            ),
            for (final block in s.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: block.startsWith('- ')
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 9, right: 10),
                          child: Container(width: 4, height: 4, decoration: BoxDecoration(color: p.inkMuted, shape: BoxShape.circle)),
                        ),
                        Expanded(child: Text(block.substring(2), style: body)),
                      ])
                    : Text(block, style: body),
              ),
          ],
          const SizedBox(height: 24),
          Wrap(spacing: 4, children: [
            for (final d in legalDocs)
              if (d.slug != doc.slug)
                TextButton(onPressed: () => context.pushReplacement('/legal/${d.slug}'), child: Text(d.title)),
          ]),
        ],
      ),
    );
  }
}

/// "Privacy · Terms" links for the login screen and About.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.palette.inkMuted, fontSize: 13);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TextButton(onPressed: () => context.push('/legal/privacy'), child: Text('Privacy', style: style)),
      Text('·', style: style),
      TextButton(onPressed: () => context.push('/legal/terms'), child: Text('Terms', style: style)),
    ]);
  }
}
