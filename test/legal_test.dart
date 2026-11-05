import 'dart:io';

import 'package:campus_track/features/legal/legal_html.dart';
import 'package:campus_track/features/legal/legal_texts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final doc in legalDocs) {
    test('web/${doc.slug}.html matches the app text (run dart run tool/make_legal_pages.dart)', () {
      final onDisk = File('web/${doc.slug}.html').readAsStringSync().replaceAll('\r\n', '\n');
      expect(onDisk, legalHtml(doc));
    });
  }

  test('every page has content and links to the others', () {
    for (final doc in legalDocs) {
      expect(doc.sections, isNotEmpty);
      final html = legalHtml(doc);
      for (final other in legalDocs) {
        expect(html, contains('href="${other.slug}.html"'));
      }
    }
  });

  test('text is escaped for HTML', () {
    final html = legalHtml(const LegalDoc(
      slug: 'x',
      title: 'A & B',
      intro: '<script>',
      sections: [LegalSection('S', ['- "quoted"'])],
    ));
    expect(html, contains('A &amp; B'));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('<li>&quot;quoted&quot;</li>'));
    expect(html, isNot(contains('<script>')));
  });

  test('deletion page and policy agree on what is deleted', () {
    final deleted = accountDeletion.sections.firstWhere((s) => s.heading == 'What is deleted').blocks.join(' ');
    for (final item in ['sign-in', 'profile', 'notifications', 'uploaded files']) {
      expect(deleted.toLowerCase(), contains(item));
    }
  });
}
