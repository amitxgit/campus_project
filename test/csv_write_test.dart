import 'dart:convert';

import 'package:campus_track/core/utils/csv.dart';
import 'package:campus_track/core/utils/share_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quotes commas, quotes and line breaks; CRLF between rows', () {
    expect(
      toCsv([
        ['Name', 'Note'],
        ['Sharma, Riya', 'said "ok"\nlater'],
      ]),
      'Name,Note\r\n"Sharma, Riya","said ""ok""\nlater"',
    );
  });

  test('numbers: whole amounts without decimals, paise with two', () {
    expect(toCsv([[12500.0, 99.5, 3, null]]), '12500,99.50,3,');
  });

  test('neutralises formula-like text but keeps negative numbers', () {
    expect(toCsv([['=HYPERLINK("x")', '-250', '+91 98']]), '"\'=HYPERLINK(""x"")",-250,\'+91 98');
  });

  test('bytes start with a UTF-8 BOM and keep ₹ and Hindi names', () {
    final bytes = csvBytes([['₹', 'अमित']]);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.skip(3).toList()), '₹,अमित');
  });

  test('round-trips through the import parser', () {
    final rows = [
      ['Name', 'Batch', 'Note'],
      ['Sharma, Riya', 'JEE-A', 'two\nlines "quoted"'],
    ];
    expect(parseCsv(utf8.decode(csvBytes(rows))), rows);
  });

  test('file slugs are safe', () {
    expect(fileSlug('Fee ledger 1 Nov – 30 Nov'), 'fee-ledger-1-nov-30-nov');
  });
}
