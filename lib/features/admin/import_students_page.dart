// lib/features/admin/import_students_page.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/login_id.dart';
import '../../core/utils/phone.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../common/widgets/app_drawer.dart';

/// One CSV row, validated before anything is sent to the server.
class ImportRow {
  final int line;
  final Map<String, String> values;
  final List<String> errors;
  ImportRow(this.line, this.values, this.errors);

  String get name => values['name'] ?? '';
  Map<String, dynamic> toPayload() => {
        'name': values['name'],
        'email': values['email'],
        'phone': values['phone'],
        'section': values['section'],
        'rollNo': values['rollNo'],
        'parentName': values['parentName'],
        'parentPhone': values['parentPhone'],
        'password': values['password'],
      };
}

/// Header aliases (lower-case, spaces/underscores removed) -> field.
const _headerAliases = {
  'name': 'name', 'studentname': 'name', 'fullname': 'name',
  'email': 'email', 'emailid': 'email',
  'phone': 'phone', 'mobile': 'phone', 'mobileno': 'phone', 'phoneno': 'phone', 'studentmobile': 'phone',
  'batch': 'section', 'section': 'section', 'class': 'section', 'group': 'section',
  'roll': 'rollNo', 'rollno': 'rollNo', 'rollnumber': 'rollNo', 'enrolmentno': 'rollNo', 'enrollmentno': 'rollNo',
  'parentname': 'parentName', 'guardianname': 'parentName', 'fathername': 'parentName', 'mothername': 'parentName',
  'parentphone': 'parentPhone', 'parentmobile': 'parentPhone', 'guardianphone': 'parentPhone', 'parentwhatsapp': 'parentPhone',
  'password': 'password',
};

const templateCsv = 'name,mobile,email,batch,roll_no,parent_name,parent_phone,password\n'
    'Asha Verma,9876543210,,JEE-2027-A,101,Rakesh Verma,9812345678,\n'
    'Rohan Gupta,9123456780,rohan@example.com,NEET-2027-B,102,Sunita Gupta,9988776655,\n';

/// Parses and validates pasted/uploaded CSV text. Exposed for tests.
({List<ImportRow> rows, String? error}) parseStudentCsv(String text, List<String> knownGroups) {
  final table = parseCsv(text);
  if (table.isEmpty) return (rows: <ImportRow>[], error: 'The file is empty.');
  final header = table.first.map((h) => _headerAliases[h.toLowerCase().replaceAll(RegExp(r'[\s_\-.]'), '')]).toList();
  if (!header.contains('name') || !header.contains('section')) {
    return (rows: <ImportRow>[], error: 'The first row must be headings, including "name" and "batch".');
  }
  final seenLogins = <String>{};
  final rows = <ImportRow>[];
  for (var r = 1; r < table.length; r++) {
    final values = <String, String>{};
    for (var c = 0; c < header.length && c < table[r].length; c++) {
      final key = header[c];
      if (key != null && table[r][c].isNotEmpty) values[key] = table[r][c];
    }
    final errors = <String>[];
    if ((values['name'] ?? '').isEmpty) errors.add('name missing');
    final section = values['section'] ?? '';
    if (section.isEmpty) {
      errors.add('batch missing');
    } else if (knownGroups.isNotEmpty && !knownGroups.contains(section)) {
      errors.add('unknown batch "$section"');
    }
    final email = values['email'] ?? '';
    final phone = values['phone'] ?? '';
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) errors.add('invalid email');
    if (phone.isNotEmpty && PhoneNumber.normalize(phone) == null) errors.add('invalid mobile');
    if (email.isEmpty && phone.isEmpty) errors.add('needs email or mobile to sign in');
    final parentPhone = values['parentPhone'] ?? '';
    if (parentPhone.isNotEmpty && PhoneNumber.normalize(parentPhone) == null) errors.add('invalid parent phone');
    final password = values['password'] ?? '';
    if (password.isNotEmpty && password.length < 6) errors.add('password under 6 characters');
    if (email.isNotEmpty || phone.isNotEmpty) {
      final login = email.isNotEmpty ? email.toLowerCase() : LoginId.toEmail(phone);
      if (!seenLogins.add(login)) errors.add('duplicate login in file');
    }
    rows.add(ImportRow(r + 1, values, errors));
  }
  return (rows: rows, error: rows.isEmpty ? 'No student rows found below the headings.' : null);
}

class ImportStudentsPage extends ConsumerStatefulWidget {
  const ImportStudentsPage({super.key});

  @override
  ConsumerState<ImportStudentsPage> createState() => _ImportStudentsPageState();
}

class _ImportStudentsPageState extends ConsumerState<ImportStudentsPage> {
  final _pasteCtrl = TextEditingController();
  List<ImportRow> _rows = [];
  String? _parseError;
  bool _importing = false;
  int _done = 0;
  List<({ImportRow row, Map<String, dynamic> result})> _results = [];

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _parse(String text) {
    final parsed = parseStudentCsv(text, ref.read(settingsProvider).groups);
    setState(() {
      _rows = parsed.rows;
      _parseError = parsed.error;
      _results = [];
    });
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
      if (files.isEmpty) return;
      final bytes = await files.first.xFile.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      _pasteCtrl.text = text;
      _parse(text);
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    }
  }

  Future<void> _import() async {
    final valid = _rows.where((r) => r.errors.isEmpty).toList();
    if (valid.isEmpty) return;
    setState(() {
      _importing = true;
      _done = 0;
      _results = [];
    });
    try {
      for (var i = 0; i < valid.length; i += 100) {
        final chunk = valid.skip(i).take(100).toList();
        final res = await ref.read(authRepoProvider).bulkCreateStudents(chunk.map((r) => r.toPayload()).toList());
        setState(() {
          for (var j = 0; j < chunk.length; j++) {
            _results.add((row: chunk[j], result: res[j]));
          }
          _done += chunk.length;
        });
      }
    } catch (e) {
      _snack(FirebaseErrorParser.getMessage(e));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _credentialsCsv() {
    final b = StringBuffer('name,batch,login,password\n');
    for (final r in _results.where((r) => r.result['ok'] == true)) {
      b.writeln('"${r.row.name}",${r.row.values['section']},${LoginId.display(r.result['login'] as String?)},'
          '${r.result['password'] ?? '(as given in file)'}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final cs = Theme.of(context).colorScheme;
    final valid = _rows.where((r) => r.errors.isEmpty).length;
    final created = _results.where((r) => r.result['ok'] == true).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Students')),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. Prepare a spreadsheet', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Columns: name, mobile, email, batch, roll_no, parent_name, parent_phone, password. '
                    'Only name and batch are required, plus a mobile or email for signing in. '
                    'Students without an email sign in with their mobile number. '
                    'Leave password blank to generate one.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if (settings.groups.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Valid ${settings.groupLabelPlural.toLowerCase()}: ${settings.groups.join(', ')}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: templateCsv));
                      _snack('Template copied — paste it into Excel or Google Sheets.');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy template'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Upload the CSV or paste the rows', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _importing ? null : _pickFile, icon: const Icon(Icons.upload_file_rounded), label: const Text('Choose CSV file')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pasteCtrl,
                    maxLines: 6,
                    enabled: !_importing,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(hintText: '...or paste here (including the heading row)', border: OutlineInputBorder()),
                    onChanged: _parse,
                  ),
                  if (_parseError != null) ...[
                    const SizedBox(height: 8),
                    Text(_parseError!, style: TextStyle(color: cs.error)),
                  ],
                ],
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3. Check and import — $valid of ${_rows.length} rows ready',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._rows.take(300).map((r) {
                      final result = _results.where((x) => identical(x.row, r)).firstOrNull?.result;
                      final ok = result?['ok'] == true;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          result != null
                              ? (ok ? Icons.check_circle_rounded : Icons.error_rounded)
                              : (r.errors.isEmpty ? Icons.radio_button_unchecked : Icons.warning_amber_rounded),
                          color: result != null ? (ok ? Colors.green : cs.error) : (r.errors.isEmpty ? null : Colors.orange),
                        ),
                        title: Text('${r.name.isEmpty ? '(no name)' : r.name} • ${r.values['section'] ?? '?'}'),
                        subtitle: Text(
                          result != null
                              ? (ok
                                  ? 'Login ${LoginId.display(result['login'] as String?)}${result['password'] != null ? ' • password ${result['password']}' : ''}'
                                  : '${result['error']}')
                              : (r.errors.isEmpty ? 'Line ${r.line}' : 'Line ${r.line}: ${r.errors.join(', ')}'),
                          style: TextStyle(color: r.errors.isNotEmpty || (result != null && !ok) ? cs.error : null),
                        ),
                      );
                    }),
                    if (_rows.length > 300) Text('…and ${_rows.length - 300} more'),
                    const SizedBox(height: 12),
                    if (_importing) ...[
                      LinearProgressIndicator(value: valid == 0 ? null : _done / valid),
                      const SizedBox(height: 8),
                      Text('Creating accounts… $_done of $valid'),
                    ] else if (_results.isEmpty)
                      FilledButton.icon(
                        onPressed: valid == 0 ? null : _import,
                        icon: const Icon(Icons.group_add_rounded),
                        label: Text('Create $valid student account${valid == 1 ? '' : 's'}'),
                      )
                    else ...[
                      Text('$created created, ${_results.length - created} failed.',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: created == 0
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: _credentialsCsv()));
                                _snack('Logins copied as CSV. Paste into a spreadsheet to share with students.');
                              },
                        icon: const Icon(Icons.key_rounded),
                        label: const Text('Copy logins & passwords'),
                      ),
                      const SizedBox(height: 4),
                      Text('Generated passwords are shown only now. Copy them before leaving this page.',
                          style: TextStyle(color: cs.error, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
