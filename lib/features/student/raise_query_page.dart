// lib/features/student/raise_query_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../../core/models/subject.dart';
import '../../main.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// SUBJECTS PROVIDER (FOR DROPDOWN)
// -----------------------------------------------------------------------------

final subjectsProvider = FutureProvider.autoDispose<List<Subject>>((ref) async {
  final ttRepo = ref.watch(timetableRepoProvider);
  final subjects = await ttRepo.allSubjects();
  subjects.sort((a, b) => a.name.compareTo(b.name));
  return subjects;
});

// -----------------------------------------------------------------------------
// PAGE
// -----------------------------------------------------------------------------

class RaiseQueryPage extends ConsumerStatefulWidget {
  const RaiseQueryPage({super.key});

  @override
  ConsumerState<RaiseQueryPage> createState() => _RaiseQueryPageState();
}

class _RaiseQueryPageState extends ConsumerState<RaiseQueryPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  String? _subjectId; // null = General
  bool _isLoading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SUBMIT
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authRepo = ref.read(authRepoProvider);
      final queryRepo = ref.read(queryRepoProvider);

      final user = await authRepo.currentUser();
      if (user == null) {
        throw Exception('You must be logged in.');
      }

      await queryRepo.raise(
        raisedByStudentId: user.id,
        subjectId: _subjectId,
        title: _titleCtrl.text.trim(),
        message: _msgCtrl.text.trim(),
      );

      if (!mounted) return;

      showMessage(context, 'Sent. You will be notified when the office replies.', success: true);

      context.pop(); // Back to previous page
    } catch (e) {
      if (!mounted) return;
      showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(subjectsProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask a question'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your question goes to the office. You will get a notification when they reply.',
                style: TextStyle(color: p.inkMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              Text('About', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              subjectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Text('Could not load subjects.', style: TextStyle(color: p.danger)),
                data: (subjects) => Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (id, name) in [(null, 'General'), ...subjects.map((s) => (s.id, s.name))])
                      ChoiceChip(
                        label: Text(name),
                        selected: _subjectId == id,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _subjectId = id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Subject line', hintText: 'e.g. Attendance not marked on Monday'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a short subject line' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _msgCtrl,
                minLines: 5,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Your question', alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Write your question' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
