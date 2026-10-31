// lib/features/student/raise_query_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../../core/models/subject.dart';
import '../../main.dart';

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Query submitted successfully! We will get back to you soon.'),
          backgroundColor: Colors.green,
        ),
      );

      context.pop(); // Back to previous page
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Input Decoration for all fields
    InputDecoration buildInputDecoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: colorScheme.primary),
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Ask a question'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // 2. FLOATING FORM CARD
            // -----------------------------------------------------------------
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // --- SUBJECT DROPDOWN ---
                    subjectsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Text('Failed to load subjects', style: TextStyle(color: colorScheme.onErrorContainer)),
                      ),
                      data: (subjects) => DropdownButtonFormField<String?>(
                        initialValue: _subjectId,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('General Query', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          ...subjects.map(
                            (s) => DropdownMenuItem<String>(
                              value: s.id,
                              child: Text(s.name, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _subjectId = v),
                        decoration: buildInputDecoration('Category / Subject (Optional)', Icons.category_rounded),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- TITLE FIELD ---
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: buildInputDecoration('Issue Title', Icons.title_rounded).copyWith(
                        hintText: 'e.g. Attendance not marked',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please provide a title' : null,
                    ),

                    const SizedBox(height: 20),

                    // --- MESSAGE FIELD ---
                    TextFormField(
                      controller: _msgCtrl,
                      maxLines: 5,
                      decoration: buildInputDecoration('Detailed Description', Icons.description_rounded).copyWith(
                        alignLabelWithHint: true,
                        hintText: 'Please describe your issue in detail so we can resolve it quickly...',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please provide a description' : null,
                    ),

                    const SizedBox(height: 32),

                    // --- SUBMIT BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _isLoading ? 'Submitting...' : 'Submit Ticket',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -----------------------------------------------------------------
            // 3. ENTERPRISE FOOTER NOTE
            // -----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Typical response time: 24-48 hours',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
