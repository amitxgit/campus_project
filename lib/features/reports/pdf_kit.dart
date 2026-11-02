// lib/features/reports/pdf_kit.dart
//
// Shared look for generated PDFs: black and white with the app's blue accent,
// Noto Sans (the built-in PDF fonts have no ₹ sign).

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const pdfAccent = PdfColor.fromInt(0xFF2A5BFF);
const pdfMuted = PdfColor.fromInt(0xFF6B6B73);
const pdfLine = PdfColor.fromInt(0xFFE4E4E8);
const pdfSoft = PdfColor.fromInt(0xFFF4F4F6);

pw.ThemeData? _theme;

/// Loads the fonts once per app run.
Future<pw.ThemeData> pdfTheme() async {
  if (_theme != null) return _theme!;
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  return _theme = pw.ThemeData.withFont(base: regular, bold: bold);
}

/// Institute name over a small accent title, e.g. "Fee receipt".
pw.Widget pdfHeader(String institute, String title, {String? right}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(
            child: pw.Text(institute, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          if (right != null) pw.Text(right, style: const pw.TextStyle(color: pdfMuted, fontSize: 10)),
        ]),
        pw.SizedBox(height: 2),
        pw.Text(title.toUpperCase(),
            style: pw.TextStyle(color: pdfAccent, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
        pw.SizedBox(height: 10),
        pw.Container(height: 1, color: PdfColors.black),
      ],
    );

/// Label on the left, value on the right.
pw.Widget pdfRow(String label, String value, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(color: pdfMuted, fontSize: 10))),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
      ]),
    );

pw.Widget pdfFootnote(String text) =>
    pw.Text(text, style: const pw.TextStyle(color: pdfMuted, fontSize: 8));
