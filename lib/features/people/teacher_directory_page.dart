// lib/features/people/teacher_directory_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';

import '../../core/models/subject.dart';
import '../../core/models/user.dart';
import '../../main.dart';
import '../../core/utils/login_id.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/class_card.dart' show EmptyNote;
import '../../core/utils/firebase_error_parser.dart';

// Provider to fetch teachers and subjects
final teacherDirectoryProvider = FutureProvider.autoDispose((ref) async {
  final results = await Future.wait([
    ref.watch(authRepoProvider).allTeachers(),
    ref.watch(timetableRepoProvider).allSubjects(),
  ]);

  final teachers = results[0] as List<UserAccount>;
  final allSubjects = results[1] as List<Subject>;


  return (teachers: teachers, allSubjects: allSubjects);
});

class TeacherDirectoryPage extends ConsumerStatefulWidget {
  const TeacherDirectoryPage({super.key});

  @override
  ConsumerState<TeacherDirectoryPage> createState() => _TeacherDirectoryPageState();
}

class _TeacherDirectoryPageState extends ConsumerState<TeacherDirectoryPage> {
  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(teacherDirectoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teachers'),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(err),
          onRetry: () => ref.refresh(teacherDirectoryProvider),
        ),
        data: (data) {
          final teachers = data.teachers;
          final subjects = data.allSubjects;

          if (teachers.isEmpty) {
            return const Center(child: EmptyNote(icon: Icons.person_search_outlined, text: 'No teachers yet.'));
          }
          final p = context.palette;

          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            itemCount: teachers.length,
            itemBuilder: (context, index) {
              final teacher = teachers[index];
              final teaching = subjects.where((s) => s.teacherId == teacher.id).map((s) => s.name).toSet().toList()..sort();
              return FadeSlideIn(
                index: index,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(teacher.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: Text(
                      teaching.isEmpty ? 'No subjects yet' : teaching.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.inkMuted, fontSize: 13),
                    ),
                    children: [
                      if (teacher.qualifications.isNotEmpty) ...[
                        Text(teacher.qualifications.join(' · '), style: TextStyle(color: p.inkMuted, height: 1.45)),
                        const SizedBox(height: 10),
                      ],
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (teacher.phone.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _launchUrl('tel:${teacher.phone}'),
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: Text(teacher.phone),
                          ),
                        if ((teacher.email ?? '').isNotEmpty && !LoginId.isPhoneLogin(teacher.email))
                          OutlinedButton.icon(
                            onPressed: () => _launchUrl('mailto:${teacher.email}'),
                            icon: const Icon(Icons.mail_outline_rounded, size: 18),
                            label: const Text('Email'),
                          ),
                      ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}