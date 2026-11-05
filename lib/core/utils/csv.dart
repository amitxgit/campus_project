// lib/core/utils/csv.dart
import 'dart:convert';
import 'dart:typed_data';

/// Minimal RFC 4180 CSV parser: commas, quoted fields with embedded commas,
/// quotes ("") and newlines, CRLF or LF line endings. Also accepts
/// tab-separated text (as pasted from Excel/Sheets) when there are no commas
/// in the first line.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final firstLine = text.split('\n').first;
  final sep = !firstLine.contains(',') && firstLine.contains('\t') ? '\t' : ',';

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString().trim());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == sep) {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

// ---------------------------------------------------------------- writing
/// Encodes rows as CSV (RFC 4180): fields with commas, quotes or line breaks
/// are quoted, quotes doubled. Lines end with CRLF, as Excel expects.
String toCsv(List<List<Object?>> rows) => rows.map((r) => r.map(_field).join(',')).join('\r\n');

String _field(Object? v) {
  if (v == null) return '';
  var s = v is double ? (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)) : '$v';
  // Stop spreadsheet apps treating text like "=SUM(...)" as a formula.
  if (s.isNotEmpty && '=+-@'.contains(s[0]) && double.tryParse(s) == null) s = "'$s";
  if (s.contains(RegExp('[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// UTF-8 with a byte-order mark, so Excel shows ₹ and Indian names correctly.
Uint8List csvBytes(List<List<Object?>> rows) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(rows))]);
