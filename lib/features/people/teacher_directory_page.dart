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
          message: err.toString(),
          onRetry: () => ref.refresh(teacherDirectoryProvider),
        ),
        data: (data) {
          final teachers = data.teachers;
          final subjects = data.allSubjects;

          if (teachers.isEmpty) {
            return const Center(child: Text('No teachers found.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: teachers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final teacher = teachers[index];

              // Find subjects taught by this teacher
              final teachingSubjects = subjects
                  .where((s) => s.teacherId == teacher.id)
                  .map((s) => '${s.name} (${s.code})')
                  .toList();

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(teacher.name.isNotEmpty ? teacher.name[0] : '?'),
                  ),
                  title: Text(
                    teacher.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(teacher.email ?? teacher.phone),
                  children: [
                    // CONTACT INFO
                    _buildSection(
                      context,
                      title: 'Contact',
                      icon: Icons.contact_phone_outlined,
                      children: [
                        if (teacher.email != null)
                          ListTile(
                            leading: const Icon(Icons.email_outlined, size: 20),
                            title: Text(teacher.email!),
                            dense: true,
                            onTap: () => _launchUrl('mailto:${teacher.email}'),
                          ),
                        ListTile(
                          leading: const Icon(Icons.phone_outlined, size: 20),
                          title: Text(teacher.phone),
                          dense: true,
                          onTap: () => _launchUrl('tel:${teacher.phone}'),
                        ),
                      ],
                    ),

                    // QUALIFICATIONS
                    if (teacher.qualifications.isNotEmpty)
                      _buildSection(
                        context,
                        title: 'Qualifications',
                        icon: Icons.school_outlined,
                        children: teacher.qualifications
                            .map((q) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $q'),
                        ))
                            .toList(),
                      ),

                    // SUBJECTS
                    if (teachingSubjects.isNotEmpty)
                      _buildSection(
                        context,
                        title: 'Subjects Taught',
                        icon: Icons.book_outlined,
                        children: teachingSubjects
                            .map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $s'),
                        ))
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, {
        required String title,
        required IconData icon,
        required List<Widget> children,
      }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
              )
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
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