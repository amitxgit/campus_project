// lib/features/admin/import_export_page.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../../core/utils/firebase_error_parser.dart';

class ImportExportPage extends ConsumerStatefulWidget {
  const ImportExportPage({super.key});

  @override
  ConsumerState<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends ConsumerState<ImportExportPage> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isLoading = false;

  final List<Map<String, dynamic>> _collections = [
    {'id': 'users', 'label': 'Users', 'icon': Icons.people_rounded},
    {'id': 'subjects', 'label': 'Subjects', 'icon': Icons.menu_book_rounded},
    {'id': 'timetable', 'label': 'Timetable', 'icon': Icons.calendar_month_rounded},
    {'id': 'attendance', 'label': 'Attendance', 'icon': Icons.fact_check_rounded},
  ];

  String _selectedCollection = 'subjects';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Backup & raw data'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // -------------------------------------------------------------------
          // 1. PREMIUM HEADER
          // -------------------------------------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Warning Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.warningSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: context.palette.warning),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Advanced tool. Wrongly formatted data can break the app — use Import students for everyday imports.',
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          // -------------------------------------------------------------------
          // 2. MAIN CONTENT AREA
          // -------------------------------------------------------------------
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. SELECT TARGET COLLECTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: colorScheme.primary, letterSpacing: 1.0)),
                  const SizedBox(height: 12),

                  // Collection Selector Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _collections.map((c) {
                        final isSel = _selectedCollection == c['id'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c['label']),
                            avatar: Icon(c['icon'], size: 18, color: isSel ? colorScheme.onPrimary : colorScheme.onSurfaceVariant),
                            selected: isSel,
                            showCheckmark: false,
                            selectedColor: colorScheme.primary,
                            backgroundColor: colorScheme.surface,
                            labelStyle: TextStyle(
                              color: isSel ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                            ),
                            side: BorderSide(color: isSel ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (val) {
                              if (val) setState(() => _selectedCollection = c['id'] as String);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('2. PASTE JSON ARRAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: colorScheme.primary, letterSpacing: 1.0)),
                      if (_ctrl.text.isNotEmpty)
                        InkWell(
                          onTap: () => setState(() => _ctrl.clear()),
                          child: Text('Clear Editor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.error)),
                        )
                    ],
                  ),
                  const SizedBox(height: 12),

                  // JSON "Code Editor" Input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5), // Code editor feel
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: TextField(
                        controller: _ctrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                        onChanged: (_) => setState(() {}), // Trigger rebuild for "Clear" button
                        decoration: InputDecoration(
                          hintText: '[\n  {\n    "id": "doc1",\n    "name": "Example"\n  }\n]',
                          hintStyle: TextStyle(fontFamily: 'monospace', color: Colors.grey.withValues(alpha: 0.6)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // -------------------------------------------------------------------
                  // 3. EXECUTE BUTTON
                  // -------------------------------------------------------------------
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: _ctrl.text.trim().isEmpty ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                        foregroundColor: _ctrl.text.trim().isEmpty ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
                      ),
                      onPressed: (_isLoading || _ctrl.text.trim().isEmpty) ? null : _importData,
                      icon: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_rounded),
                      label: Text(
                          _isLoading ? 'Executing Batch...' : 'Execute Batch Import',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                  const SizedBox(height: 8), // SafeArea buffer
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _importData() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // 1. Validate JSON Format
      final dynamic parsed;
      try {
        parsed = jsonDecode(text);
      } catch (e) {
        throw const FormatException('Invalid JSON format. Ensure you have properly quoted keys and valid syntax.');
      }

      // 2. Validate Data Type
      if (parsed is! List) {
        throw const FormatException('JSON root must be an Array [ ] containing Objects { }.');
      }

      // 3. Cast and Write
      final List<Map<String, dynamic>> items = parsed.cast<Map<String, dynamic>>();
      await _batchWrite(_selectedCollection, items);

      if (mounted) {
        _ctrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Import executed successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            )
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Syntax Error: ${e.message}'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _batchWrite(String collection, List<Map<String, dynamic>> items) async {
    final db = FirebaseFirestore.instance;
    const int batchSize = 400;

    for (var i = 0; i < items.length; i += batchSize) {
      final batch = db.batch();
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final chunk = items.sublist(i, end);

      for (final docData in chunk) {
        final String? id = docData['id'];
        final DocumentReference ref = id != null && id.isNotEmpty
            ? db.collection(collection).doc(id)
            : db.collection(collection).doc();

        batch.set(ref, docData, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }
}