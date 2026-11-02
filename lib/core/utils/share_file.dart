// lib/core/utils/share_file.dart
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the share sheet for a PDF on phones (WhatsApp, Drive, email...) and
/// downloads it in a browser.
Future<void> sharePdf(Uint8List bytes, String filename) =>
    Printing.sharePdf(bytes: bytes, filename: filename);

/// Same for a CSV export. Browsers that can't share files download it.
Future<void> shareCsv(Uint8List bytes, String filename) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'text/csv', name: filename)],
    fileNameOverrides: [filename],
  ));
}

/// A safe file name: "Fee ledger 1 Nov-30 Nov" -> "fee-ledger-1-nov-30-nov".
String fileSlug(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
