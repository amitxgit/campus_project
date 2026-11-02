// lib/features/legal/legal_html.dart
//
// Renders a LegalDoc as a standalone web page (same look as web/pay.html).
// Pure Dart, used by tool/make_legal_pages.dart and its up-to-date test.

import 'legal_texts.dart';

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String legalHtml(LegalDoc doc) {
  final b = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('  <meta charset="UTF-8">')
    ..writeln('  <meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('  <title>${_esc(doc.title)} · Batchwise</title>')
    ..writeln('  <!-- Generated from lib/features/legal/legal_texts.dart by tool/make_legal_pages.dart. Do not edit. -->')
    ..writeln('  <style>')
    ..writeln('    :root { --bg:#fff; --ink:#0b0b0d; --muted:#62626c; --line:#e4e4e8; --accent:#2a5bff; }')
    ..writeln('    @media (prefers-color-scheme: dark) { :root { --bg:#09090b; --ink:#f5f5f6; --muted:#a0a0ab; --line:#26262b; --accent:#6d8bff; } }')
    ..writeln('    body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }')
    ..writeln('    main { max-width:680px; margin:0 auto; padding:40px 24px 64px; }')
    ..writeln('    .brand { font-size:12px; font-weight:700; letter-spacing:1.2px; text-transform:uppercase; color:var(--accent); }')
    ..writeln('    h1 { font-size:32px; letter-spacing:-0.8px; line-height:1.2; margin:6px 0 4px; }')
    ..writeln('    .updated { color:var(--muted); font-size:14px; margin:0 0 24px; }')
    ..writeln('    h2 { font-size:18px; margin:32px 0 8px; padding-top:20px; border-top:1px solid var(--line); }')
    ..writeln('    ul { padding-left:20px; } li { margin:6px 0; }')
    ..writeln('    nav { margin-top:40px; font-size:14px; color:var(--muted); } nav a { color:var(--muted); margin-right:16px; }')
    ..writeln('  </style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<main>')
    ..writeln('  <div class="brand">Batchwise</div>')
    ..writeln('  <h1>${_esc(doc.title)}</h1>')
    ..writeln('  <p class="updated">Last updated ${_esc(kLegalUpdated)}</p>')
    ..writeln('  <p>${_esc(doc.intro)}</p>');
  for (final s in doc.sections) {
    b.writeln('  <h2>${_esc(s.heading)}</h2>');
    var inList = false;
    for (final block in s.blocks) {
      final bullet = block.startsWith('- ');
      if (bullet && !inList) b.writeln('  <ul>');
      if (!bullet && inList) b.writeln('  </ul>');
      inList = bullet;
      b.writeln(bullet ? '    <li>${_esc(block.substring(2))}</li>' : '  <p>${_esc(block)}</p>');
    }
    if (inList) b.writeln('  </ul>');
  }
  b
    ..writeln('  <nav>')
    ..writeln('    ${legalDocs.map((d) => '<a href="${d.slug}.html">${_esc(d.title)}</a>').join('\n    ')}')
    ..writeln('  </nav>')
    ..writeln('</main>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}
