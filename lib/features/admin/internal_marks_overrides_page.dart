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
import '../../theme.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Internal marks'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(adminMarksProvider),
          ),
          const ProfileAvatarAction(),
        ],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
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
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: hasChanges ? context.palette.accentSoft : context.palette.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              student.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: Text(
                              [subject.name, if (subject.semester.isNotEmpty) 'Sem ${subject.semester}'].join(' · '),
                              style: TextStyle(fontSize: 13, color: context.palette.inkMuted),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${current.totalMarks.toStringAsFixed(1)} / ${ref.watch(settingsProvider).totalMarksMax.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: hasChanges ? context.palette.accent : context.palette.ink,
                                  ),
                                ),
                                if (hasChanges)
                                  Text('Edited', style: TextStyle(color: context.palette.accent, fontSize: 12, fontWeight: FontWeight.w600)),
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
    return const Center(child: EmptyNote(icon: Icons.person_search_outlined, text: 'No records match.'));
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
            '$label / ${max.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.palette.inkMuted),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: current.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              fillColor: context.palette.background,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
      bottom: 16,
      left: 16,
      right: 16,
      child: UnsavedChangesBar(
        visible: true,
        label: _edited.length == 1 ? '1 change' : '${_edited.length} changes',
        saving: _isSaving,
        onDiscard: () => setState(() => _edited.clear()),
        onSave: () => _saveAll(context),
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
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
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