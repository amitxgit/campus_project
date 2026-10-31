// lib/features/admin/attendance_overrides_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/attendance.dart';
import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../core/models/role.dart';
import '../../main.dart';
import '../common/widgets/ui_kit.dart';

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
        title: const Text('Attendance'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(adminAttendanceProvider),
        ),
        data: (data) {
          final allRecords = data['records'] as List<AttendanceRecord>;
          final subjects = data['subjects'] as List<Subject>;
          final students = data['students'] as List<UserAccount>;

          // Apply Search Filter
          final filtered = allRecords.where((r) {
            if (_searchQuery.isEmpty) return true;

            final st = students.firstWhere((s) => s.id == r.studentId, orElse: () => _unknownUser);
            final matchName = st.name.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchRoll = (st.collegeRollNo ?? '').toLowerCase().contains(_searchQuery.toLowerCase());

            final sub = subjects.firstWhere((s) => s.id == r.subjectId,
                orElse: () => const Subject(id: '', code: '?', name: 'Unknown', department: '', semester: '', section: '', teacherId: ''));
            final matchSubject = sub.name.toLowerCase().contains(_searchQuery.toLowerCase());

            return matchName || matchRoll || matchSubject;
          }).toList();

          return Stack(
            children: [
              Column(
                children: [
                  // -----------------------------------------------------------
                  // 1. PREMIUM SEARCH HEADER
                  // -----------------------------------------------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search student, roll no or subject',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),

                  // -----------------------------------------------------------
                  // 2. LIST VIEW
                  // -----------------------------------------------------------
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.builder(
                      padding: EdgeInsets.only(top: 16, bottom: _edited.isNotEmpty ? 100 : 16), // Padding for sticky bottom bar
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        final st = students.firstWhere((s) => s.id == r.studentId, orElse: () => _unknownUser);
                        final sub = subjects.firstWhere((s) => s.id == r.subjectId,
                            orElse: () => const Subject(id: '', code: '?', name: 'Unknown', department: '', semester: '', section: '', teacherId: ''));

                        final isEdited = _edited.containsKey(r.id);
                        final currentStatus = _edited[r.id] ?? r.status;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isEdited ? colorScheme.primaryContainer.withValues(alpha: 0.2) : Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: isEdited ? colorScheme.primary : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                                width: isEdited ? 2.0 : 1.5
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Student Info
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: colorScheme.secondaryContainer,
                                      child: Text(
                                        st.name.isNotEmpty ? st.name[0].toUpperCase() : '?',
                                        style: TextStyle(color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(st.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          Text(st.collegeRollNo ?? 'No Roll No', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    if (isEdited)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                                        child: const Text('Modified', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                      )
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Middle: Subject & Context
                                Row(
                                  children: [
                                    Icon(Icons.menu_book_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(sub.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(DateFormat('MMM d, yyyy').format(r.date), style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 16),
                                    Icon(Icons.access_time_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(r.slot, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),

                                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

                                // Bottom: Status Selector
                                SizedBox(
                                  width: double.infinity,
                                  child: SegmentedButton<AttendanceStatus>(
                                    showSelectedIcon: false,
                                    style: SegmentedButton.styleFrom(
                                      selectedBackgroundColor: _getStatusColor(currentStatus, isDark).withValues(alpha: 0.2),
                                      selectedForegroundColor: _getStatusColor(currentStatus, isDark),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    segments: [
                                      ButtonSegment(value: AttendanceStatus.present, label: _buildSegmentLabel('Present', currentStatus == AttendanceStatus.present)),
                                      ButtonSegment(value: AttendanceStatus.absent, label: _buildSegmentLabel('Absent', currentStatus == AttendanceStatus.absent)),
                                      ButtonSegment(value: AttendanceStatus.late, label: _buildSegmentLabel('Late', currentStatus == AttendanceStatus.late)),
                                      ButtonSegment(value: AttendanceStatus.excused, label: _buildSegmentLabel('Excused', currentStatus == AttendanceStatus.excused)),
                                    ],
                                    selected: {currentStatus},
                                    onSelectionChanged: (val) {
                                      setState(() {
                                        if (val.first == r.status) {
                                          _edited.remove(r.id); // Reverted to original
                                        } else {
                                          _edited[r.id] = val.first; // Overridden
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // 3. STICKY ACTION BAR (ANIMATED)
              // ---------------------------------------------------------------
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                bottom: _edited.isNotEmpty ? 24 : -100, // Slides up when items are edited
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unsaved Changes',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          Row(
                            children: [
                              Text(
                                '${_edited.length}',
                                style: TextStyle(color: colorScheme.primary, fontSize: 24, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 8),
                              const Text('Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _isSaving ? null : () => setState(() => _edited.clear()),
                            child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isSaving ? null : () => _saveChanges(ref),
                            icon: _isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Apply All', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('No records found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Try adjusting your search criteria.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSegmentLabel(String text, bool isSelected) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  Color _getStatusColor(AttendanceStatus status, bool isDark) {
    switch (status) {
      case AttendanceStatus.present: return isDark ? Colors.greenAccent : Colors.green;
      case AttendanceStatus.absent: return isDark ? Colors.redAccent : Colors.red;
      case AttendanceStatus.late: return isDark ? Colors.orangeAccent : Colors.orange;
      case AttendanceStatus.excused: return isDark ? Colors.blueAccent : Colors.blue;
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> _saveChanges(WidgetRef ref) async {
    if (_edited.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final user = await ref.read(authRepoProvider).currentUser();

      // ✅ FIX: Admins can bypass base role check if the flag is active
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
        showMessage(context, 'All overrides applied successfully.', success: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showMessage(context, 'Error: $e', error: true);
      }
    }
  }
}