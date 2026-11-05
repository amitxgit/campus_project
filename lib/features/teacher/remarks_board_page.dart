// lib/features/teacher/remarks_board_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../../core/models/user.dart';
import '../../core/models/remark.dart';
import '../../core/models/role.dart';
import '../../main.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final remarksBoardProvider = FutureProvider.autoDispose((ref) async {
  final authRepo = ref.watch(authRepoProvider);
  final me = await authRepo.currentUser();
  if (me == null) throw Exception('Not logged in');

  final remarkRepo = ref.watch(remarkRepoProvider);
  final remarks = await remarkRepo.forTeacher(me.id);
  final students = await authRepo.allStudents();

  return {
    'me': me,
    'remarks': remarks,
    'students': students,
  };
});

// -----------------------------------------------------------------------------
// MAIN PAGE
// -----------------------------------------------------------------------------
class RemarksBoardPage extends ConsumerStatefulWidget {
  const RemarksBoardPage({super.key});

  @override
  ConsumerState<RemarksBoardPage> createState() => _RemarksBoardPageState();
}

class _RemarksBoardPageState extends ConsumerState<RemarksBoardPage> {
  String _searchQuery = '';
  String _filterTag = 'All';

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
    final asyncData = ref.watch(remarksBoardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remarks'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.invalidate(remarksBoardProvider),
        ),
        data: (data) {
          final remarks = data['remarks'] as List<StudentRemark>;
          final students = data['students'] as List<UserAccount>;
          final teacherId = (data['me'] as UserAccount).id;

          // Extract unique tags for top filter
          final uniqueTags = ['All', ...remarks.map((r) => r.tag).toSet()];

          // Filter existing remarks
          final filteredRemarks = remarks.where((r) {
            if (_filterTag != 'All' && r.tag != _filterTag) return false;
            final st = students.firstWhere((s) => s.id == r.studentId, orElse: () => _unknownUser);
            if (_searchQuery.isNotEmpty) {
              return st.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  (st.collegeRollNo ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
            }
            return true;
          }).toList();

          final p = context.palette;
          final knownTags = remarks.map((r) => r.tag).toSet().toList()..sort();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search student',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              if (uniqueTags.length > 2)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final tag in uniqueTags)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(tag),
                            selected: _filterTag == tag,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filterTag = tag),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: filteredRemarks.isEmpty
                    ? Center(
                        child: EmptyNote(
                          icon: Icons.rate_review_outlined,
                          text: remarks.isEmpty
                              ? 'Add short notes on students to keep track of them.'
                              : 'No remarks match.',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 104),
                        itemCount: filteredRemarks.length,
                        itemBuilder: (context, index) {
                          final r = filteredRemarks[index];
                          final st = students.firstWhere((s) => s.id == r.studentId, orElse: () => _unknownUser);
                          return FadeSlideIn(
                            index: index,
                            child: InkWell(
                              onTap: () => _editRemarkDialog(context, ref, teacherId, st, knownTags, existingTag: r.tag),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(st.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if ((st.section ?? '').isNotEmpty) st.section!,
                                              DateFormat('d MMM').format(r.updatedAt),
                                            ].join(' · '),
                                            style: TextStyle(fontSize: 13, color: p.inkMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          r.tag,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: p.accent, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: asyncData.maybeWhen(
        data: (data) => FloatingActionButton.extended(
          onPressed: () => _pickStudent(
            context,
            ref,
            data['students'] as List<UserAccount>,
            (data['me'] as UserAccount).id,
            (data['remarks'] as List<StudentRemark>).map((r) => r.tag).toSet().toList()..sort(),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add remark'),
        ),
        orElse: () => null,
      ),
    );
  }

  void _pickStudent(BuildContext context, WidgetRef ref, List<UserAccount> students, String teacherId, List<String> knownTags) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _StudentPicker(
        students: students,
        onSelected: (st) {
          Navigator.pop(ctx);
          _editRemarkDialog(context, ref, teacherId, st, knownTags);
        },
      ),
    );
  }

  Future<void> _editRemarkDialog(
    BuildContext context,
    WidgetRef ref,
    String teacherId,
    UserAccount student,
    List<String> knownTags, {
    String? existingTag,
  }) async {
    final controller = TextEditingController(text: existingTag);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(student.name),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: existingTag == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Remark', hintText: 'e.g. Needs help with organic chemistry'),
                  onChanged: (_) => setState(() {}),
                ),
                if (knownTags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Used before', style: TextStyle(fontSize: 13, color: ctx.palette.inkMuted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in knownTags.take(8))
                        ChoiceChip(
                          label: Text(t),
                          selected: controller.text.trim() == t,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => controller.text = t),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final tag = controller.text.trim();
                if (tag.isEmpty) return;
                try {
                  await ref.read(remarkRepoProvider).upsertRemark(teacherId: teacherId, studentId: student.id, tag: tag);
                  ref.invalidate(remarksBoardProvider);
                  if (context.mounted) showMessage(context, 'Remark saved.', success: true);
                } catch (e) {
                  if (context.mounted) showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search plus batch chips, then a plain list of students.
class _StudentPicker extends StatefulWidget {
  final List<UserAccount> students;
  final ValueChanged<UserAccount> onSelected;
  const _StudentPicker({required this.students, required this.onSelected});

  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  String _search = '';
  String? _batch;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final batches = widget.students.map((s) => s.section ?? '').where((b) => b.isNotEmpty).toSet().toList()..sort();
    final q = _search.toLowerCase();
    final filtered = widget.students
        .where((s) => (_batch == null || s.section == _batch) && (q.isEmpty || s.name.toLowerCase().contains(q) || s.phone.contains(q)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Choose a student', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Name or phone', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          if (batches.length > 1)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                children: [
                  for (final b in <String?>[null, ...batches])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(b ?? 'All'),
                        selected: _batch == b,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _batch = b),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No students found.', style: TextStyle(color: p.inkMuted)))
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final s = filtered[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(s.section ?? '', style: TextStyle(color: p.inkMuted)),
                        trailing: Icon(Icons.chevron_right_rounded, color: p.inkFaint),
                        onTap: () => widget.onSelected(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
