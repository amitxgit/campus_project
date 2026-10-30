// lib/features/assignments/assignment_detail_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/assignment.dart';
import '../../core/models/role.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/assignment_repository.dart';
import '../../main.dart';
import 'assignments_page.dart';

final _mySubmissionProvider =
FutureProvider.autoDispose.family<AssignmentSubmission?, String>((ref, assignmentId) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) return null;
  return ref.watch(assignmentRepoProvider).submissionOf(assignmentId, user.id);
});

final _allSubmissionsProvider =
FutureProvider.autoDispose.family<List<AssignmentSubmission>, String>((ref, assignmentId) {
  return ref.watch(assignmentRepoProvider).submissions(assignmentId);
});

class AssignmentDetailPage extends ConsumerStatefulWidget {
  final Assignment assignment;

  const AssignmentDetailPage({super.key, required this.assignment});

  @override
  ConsumerState<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends ConsumerState<AssignmentDetailPage> {
  final _submissionCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _prefilled = false;
  Uint8List? _fileBytes;
  String? _fileName;

  @override
  void dispose() {
    _submissionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final isStudent = user?.role == UserRole.student;
    final canManage = user != null &&
        (user.role == UserRole.admin || user.isAdmin || user.id == widget.assignment.teacherId);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = widget.assignment;

    final dueDate = DateFormat('EEEE, MMM d, yyyy • h:mm a').format(a.dueDate);
    final displayDesc = a.description.isEmpty ? 'No instructions provided by the instructor.' : a.description;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Delete assignment',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteAssignment,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- PREMIUM HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 100, 24, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${a.subjectName} • ${a.section}'.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    a.title,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.2),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, color: Colors.white.withValues(alpha: 0.8), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Due: $dueDate', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- INSTRUCTIONS ---
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Instructions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: colorScheme.primary, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Text(
                      displayDesc,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ),

                  const SizedBox(height: 40),

                  if (isStudent) _buildStudentSection(colorScheme),
                  if (!isStudent && user != null) _buildSubmissionsSection(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STUDENT: TURN IN WORK
  // ---------------------------------------------------------------------------
  Widget _buildStudentSection(ColorScheme colorScheme) {
    final mine = ref.watch(_mySubmissionProvider(widget.assignment.id));
    final existing = mine.valueOrNull;

    if (existing != null && !_prefilled) {
      _prefilled = true;
      _submissionCtrl.text = existing.text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Submit Your Work', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: colorScheme.primary, letterSpacing: 1.0)),
        const SizedBox(height: 12),
        if (existing != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Turned in ${DateFormat('MMM d, h:mm a').format(existing.submittedAt)}'
                        '${existing.submittedAt.isAfter(widget.assignment.dueDate) ? ' (late)' : ''}'
                        '. You can resubmit to replace it.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              TextField(
                controller: _submissionCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Write your answer or paste a link...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(20),
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _pickFile,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text('Attach File'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fileName ?? existing?.fileName ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    if (_fileName != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _fileBytes = null;
                          _fileName = null;
                        }),
                      ),
                  ],
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: _isSubmitting ? null : () => _turnInAssignment(existing),
            icon: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(
              _isSubmitting ? 'Turning In...' : (existing == null ? 'Turn In Assignment' : 'Resubmit'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final file = files.first;
      final size = await file.length() ?? 0;
      if (size > AssignmentRepository.maxFileBytes) {
        throw Exception('File is too large. The limit is 20 MB.');
      }
      final bytes = await file.xFile.readAsBytes();
      setState(() {
        _fileBytes = bytes;
        _fileName = file.name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _turnInAssignment(AssignmentSubmission? existing) async {
    final hasFile = _fileBytes != null || existing?.filePath != null;
    if (_submissionCtrl.text.trim().isEmpty && !hasFile) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please attach a file or write your answer before turning in.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = await ref.read(authRepoProvider).currentUser();
      if (user == null) throw Exception('Not logged in');

      await ref.read(assignmentRepoProvider).submit(
        assignmentId: widget.assignment.id,
        studentId: user.id,
        studentName: user.name,
        text: _submissionCtrl.text.trim(),
        fileBytes: _fileBytes,
        fileName: _fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignment Turned In Successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context); // Go back to list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // STAFF: REVIEW SUBMISSIONS
  // ---------------------------------------------------------------------------
  Widget _buildSubmissionsSection(ColorScheme colorScheme) {
    final submissions = ref.watch(_allSubmissionsProvider(widget.assignment.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Submissions${submissions.hasValue ? ' (${submissions.value!.length})' : ''}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: colorScheme.primary, letterSpacing: 1.0),
        ),
        const SizedBox(height: 12),
        submissions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(FirebaseErrorParser.getMessage(e)),
          data: (list) {
            if (list.isEmpty) {
              return Text('No one has turned this in yet.', style: TextStyle(color: colorScheme.onSurfaceVariant));
            }
            return Column(
              children: list.map((s) {
                final late = s.submittedAt.isAfter(widget.assignment.dueDate);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(s.studentName.isEmpty ? s.studentId : s.studentName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('MMM d, h:mm a').format(s.submittedAt)}${late ? ' • LATE' : ''}',
                          style: TextStyle(color: late ? colorScheme.error : null, fontSize: 12),
                        ),
                        if (s.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SelectableText(s.text),
                        ],
                      ],
                    ),
                    trailing: s.filePath == null
                        ? null
                        : IconButton(
                            tooltip: s.fileName ?? 'Open file',
                            icon: const Icon(Icons.download_rounded),
                            onPressed: () => _openFile(s.filePath!),
                          ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _openFile(String path) async {
    try {
      final url = await ref.read(assignmentRepoProvider).fileUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteAssignment() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete assignment?'),
        content: const Text('Students will no longer see it. Existing submissions are kept for your records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(assignmentRepoProvider).delete(widget.assignment.id);
      ref.invalidate(assignmentsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red));
      }
    }
  }
}
