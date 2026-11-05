// lib/features/admin/attendance_overrides_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/attendance_toggle.dart';
import '../../core/models/attendance.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/models/role.dart';
import '../../main.dart';
import '../common/widgets/ui_kit.dart';
import '../../theme.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final adminAttendanceProvider = FutureProvider.autoDispose((ref) async {
  final attRepo = ref.watch(attendanceRepoProvider);
  final ttRepo = ref.watch(timetableRepoProvider);
  final authRepo = ref.watch(authRepoProvider);

  // Fetch parallel to reduce load time
  final results = await Future.wait([
    attRepo.allRecords(limit: 500),
    ttRepo.allSubjects(),
    authRepo.allStudents(),
  ]);

  final records = results[0] as List<AttendanceRecord>;
  records.sort((a, b) => b.date.compareTo(a.date)); // Sort newest first

  return {
    'records': records,
    'subjects': results[1] as List<Subject>,
    'students': results[2] as List<UserAccount>,
  };
});

// -----------------------------------------------------------------------------
// PAGE
// -----------------------------------------------------------------------------
class AttendanceOverridesPage extends ConsumerStatefulWidget {
  const AttendanceOverridesPage({super.key});

  @override
  ConsumerState<AttendanceOverridesPage> createState() => _AttendanceOverridesPageState();
}

class _AttendanceOverridesPageState extends ConsumerState<AttendanceOverridesPage> {
  final Map<String, AttendanceStatus> _edited = {};
  String _searchQuery = '';
  bool _isSaving = false;

  final UserAccount _unknownUser = UserAccount(
    id: '?',
    role: UserRole.student,
    name: 'Unknown Student',
    phone: '',
    isActive: false,
    createdAt: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(adminAttendanceProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: UnsavedChangesBar(
        visible: _edited.isNotEmpty,
        label: _edited.length == 1 ? '1 change' : '${_edited.length} changes',
        saving: _isSaving,
        onDiscard: () => setState(() => _edited.clear()),
        onSave: () => _saveChanges(ref),
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(adminAttendanceProvider),
        ),
        data: (data) {
          final allRecords = data['records'] as List<AttendanceRecord>;
          final subjects = data['subjects'] as List<Subject>;
          final students = data['students'] as List<UserAccount>;
          final studentsById = {for (final st in students) st.id: st};
          final subjectsById = {for (final sb in subjects) sb.id: sb};

          final q = _searchQuery.toLowerCase();
          final filtered = allRecords.where((r) {
            if (q.isEmpty) return true;
            final st = studentsById[r.studentId];
            final sub = subjectsById[r.subjectId];
            return (st?.name.toLowerCase().contains(q) ?? false) ||
                (st?.section?.toLowerCase().contains(q) ?? false) ||
                (sub?.name.toLowerCase().contains(q) ?? false);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search student, batch or subject',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: EmptyNote(icon: Icons.search_off_rounded, text: 'No records match.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 104),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final r = filtered[i];
                          final st = studentsById[r.studentId] ?? _unknownUser;
                          final sub = subjectsById[r.subjectId];
                          final isEdited = _edited.containsKey(r.id);
                          final current = _edited[r.id] ?? r.status;
                          return AnimatedContainer(
                            duration: Motion.fast,
                            color: isEdited ? p.accentSoft : Colors.transparent,
                            padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                      const SizedBox(height: 2),
                                      Text(
                                        [sub?.name ?? 'Unknown subject', DateFormat('d MMM').format(r.date), if (r.slot.isNotEmpty) r.slot].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: p.inkMuted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AttendanceToggle(
                                  value: current,
                                  showExcused: true,
                                  onChanged: (v) => setState(() {
                                    if (v == r.status) {
                                      _edited.remove(r.id);
                                    } else {
                                      _edited[r.id] = v;
                                    }
                                  }),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> _saveChanges(WidgetRef ref) async {
    if (_edited.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final user = await ref.read(authRepoProvider).currentUser();

      if (user == null || (!user.role.isAdmin && !user.isAdmin)) {
        throw Exception('Unauthorized');
      }

      await ref.read(attendanceRepoProvider).batchUpdateStatus(_edited, user.id);

      if (mounted) {
        setState(() {
          _edited.clear();
          _isSaving = false;
        });
        ref.invalidate(adminAttendanceProvider);
        showMessage(context, 'Attendance updated.', success: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}