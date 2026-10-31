// lib/features/admin/internal_marks_overrides_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/internal_marks.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/models/role.dart';
import '../../main.dart';
import '../../data/settings_repository.dart';
import '../common/widgets/ui_kit.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

final adminMarksProvider = FutureProvider.autoDispose((ref) async {
  final marksRepo = ref.read(internalMarksRepoProvider);
  final ttRepo = ref.read(timetableRepoProvider);
  final authRepo = ref.read(authRepoProvider);

  final results = await Future.wait([
    marksRepo.getAllMarks(),
    ttRepo.allSubjects(),
    authRepo.allStudents(),
  ]);

  return {
    'marks': results[0] as List<InternalMarks>,
    'subjects': results[1] as List<Subject>,
    'students': results[2] as List<UserAccount>,
  };
});

class InternalMarksOverridesPage extends ConsumerStatefulWidget {
  const InternalMarksOverridesPage({super.key});

  @override
  ConsumerState<InternalMarksOverridesPage> createState() =>
      _InternalMarksOverridesPageState();
}

class _InternalMarksOverridesPageState
    extends ConsumerState<InternalMarksOverridesPage> {
  String _query = '';
  final Map<String, InternalMarks> _edited = {};
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(adminMarksProvider);
    final scheme = ref.watch(settingsProvider);
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
        title: const Text(
          'Academic Overrides',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => ref.invalidate(adminMarksProvider),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.refresh(adminMarksProvider),
        ),
        data: (data) {
          final marks = data['marks'] as List<InternalMarks>;
          final subjects = data['subjects'] as List<Subject>;
          final students = data['students'] as List<UserAccount>;

          final filtered = marks.where((m) {
            final s = students.firstWhere((u) => u.id == m.studentId,
                orElse: () => _unknownUser);
            if (_query.isEmpty) return true;
            return s.name.toLowerCase().contains(_query.toLowerCase()) ||
                (s.collegeRollNo ?? '').contains(_query);
          }).toList();

          return Stack(
            children: [
              Column(
                children: [
                  // --- PREMIUM HEADER ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search student or roll no',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ],
                    ),
                  ),

                  // --- LIST OF MARKS ---
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, _edited.isNotEmpty ? 100 : 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final original = filtered[index];
                        final current = _edited[original.id] ?? original;
                        final student = students.firstWhere(
                                (s) => s.id == current.studentId,
                            orElse: () => _unknownUser);
                        final subject = subjects.firstWhere(
                                (s) => s.id == current.subjectId,
                            orElse: () => _unknownSubject);

                        final hasChanges = _edited.containsKey(original.id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hasChanges
                                  ? colorScheme.primary
                                  : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                              width: hasChanges ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ExpansionTile(
                            shape: const RoundedRectangleBorder(side: BorderSide.none),
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                student.name.isNotEmpty ? student.name[0] : '?',
                                style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              student.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Text(
                              '${subject.name} • Sem ${subject.semester}',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${current.totalMarks.toStringAsFixed(1)} / ${ref.watch(settingsProvider).totalMarksMax.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: hasChanges ? colorScheme.primary : colorScheme.onSurface,
                                  ),
                                ),
                                if (hasChanges)
                                  Text(
                                    'MODIFIED',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                              ],
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                child: Row(
                                  children: [
                                    _buildScoreEditor(
                                      label: 'Attendance',
                                      current: current.attendanceMarks,
                                      max: scheme.attendanceMax,
                                      onChanged: (v) => _updateLocalEntry(current, attendance: v),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildScoreEditor(
                                      label: 'Assignment',
                                      current: current.assignmentMarks,
                                      max: scheme.assignmentMax,
                                      onChanged: (v) => _updateLocalEntry(current, assignment: v),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildScoreEditor(
                                      label: 'Mid-Term',
                                      current: current.testMarks,
                                      max: scheme.testMax,
                                      onChanged: (v) => _updateLocalEntry(current, test: v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // --- FLOATING SAVE BAR ---
              if (_edited.isNotEmpty)
                _buildFloatingSaveBar(context, colorScheme),
            ],
          );
        },
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          const Text('No records match your search', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildScoreEditor({
    required String label,
    required double current,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (Max $max)',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: current.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'(^\d*\.?\d*)'))],
            onChanged: (v) {
              final d = double.tryParse(v) ?? 0.0;
              if (d <= max) onChanged(d);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSaveBar(BuildContext context, ColorScheme colorScheme) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_edited.length} OVERRIDES PENDING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onPrimaryContainer,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Unsaved Changes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const Spacer(),
            TextButton(
              onPressed: _isSaving ? null : () => setState(() => _edited.clear()),
              child: Text('Discard', style: TextStyle(color: colorScheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSaving ? null : () => _saveAll(context),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Apply Changes'),
            ),
          ],
        ),
      ),
    );
  }

  // --- LOGIC ---

  void _updateLocalEntry(InternalMarks current, {double? attendance, double? assignment, double? test}) {
    setState(() {
      _edited[current.id] = current.copyWith(
        attendanceMarks: attendance ?? current.attendanceMarks,
        assignmentMarks: assignment ?? current.assignmentMarks,
        testMarks: test ?? current.testMarks,
      );
    });
  }

  Future<void> _saveAll(BuildContext context) async {
    setState(() => _isSaving = true);
    final batch = FirebaseFirestore.instance.batch();

    final scheme = ref.read(settingsProvider);
    for (final mark in _edited.values) {
      final assign = mark.assignmentMarks.clamp(0.0, scheme.assignmentMax);
      final test = mark.testMarks.clamp(0.0, scheme.testMax);
      final att = mark.attendanceMarks.clamp(0.0, scheme.attendanceMax);
      final toSave = mark.copyWith(
        assignmentMarks: assign,
        testMarks: test,
        attendanceMarks: att,
        totalMarks: assign + test + att,
      );

      final ref = FirebaseFirestore.instance.collection('internal_marks').doc(toSave.id);
      batch.set(ref, toSave.toMap(), SetOptions(merge: true));
    }

    try {
      await batch.commit();
      setState(() {
        _edited.clear();
        _isSaving = false;
      });
      ref.invalidate(adminMarksProvider);

      if (context.mounted) {
        showMessage(context, 'Academic records updated successfully!', success: true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (context.mounted) {
        showMessage(context, 'Error: $e', error: true);
      }
    }
  }

  final _unknownUser = UserAccount(
    id: '?',
    role: UserRole.student,
    name: 'Unknown Student',
    email: '',
    phone: '',
    isActive: true,
    createdAt: DateTime.now(),
  );

  final _unknownSubject = const Subject(
    id: '?',
    code: '?',
    name: 'Unknown Subject',
    department: '',
    semester: '',
    section: '',
    teacherId: '',
  );
}