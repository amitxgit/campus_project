// lib/core/models/notice.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

enum NoticeAudience { all, students, teachers }

class Notice {
  final String id;
  final String title;
  final String content;
  final NoticeAudience audience;
  final String authorId;
  final String authorName;
  final String authorRole;
  final DateTime createdAt;

  const Notice({
    required this.id,
    required this.title,
    required this.content,
    required this.audience,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'content': content,
    'targetAudience': audience.name,
    'authorId': authorId,
    'authorName': authorName,
    'authorRole': authorRole,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Notice.fromMap(String id, Map<String, dynamic> map) {
    return Notice(
      id: id,
      title: map['title'] ?? 'Untitled Notice',
      content: map['content'] ?? '',
      audience: NoticeAudience.values.firstWhere(
            (e) => e.name == map['targetAudience'],
        orElse: () => NoticeAudience.all,
      ),
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? 'Admin',
      authorRole: map['authorRole'] ?? 'staff',
      createdAt: DateParser.parse(map['createdAt'], fieldName: 'Notice.createdAt'),
    );
  }
}
