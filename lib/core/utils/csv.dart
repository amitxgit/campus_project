// lib/core/utils/csv.dart

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
