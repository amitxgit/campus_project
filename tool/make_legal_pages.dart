// Writes web/privacy.html, web/terms.html and web/delete-account.html from
// lib/features/legal/legal_texts.dart. Run after editing the legal text:
//
//   dart run tool/make_legal_pages.dart
//
// test/legal_test.dart fails if the pages are out of date.

import 'dart:io';

import 'package:campus_track/features/legal/legal_html.dart';
import 'package:campus_track/features/legal/legal_texts.dart';

void main() {
  for (final doc in legalDocs) {
    final file = File('web/${doc.slug}.html');
    file.writeAsStringSync(legalHtml(doc));
    stdout.writeln('wrote ${file.path}');
  }
}
