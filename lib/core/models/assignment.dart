// lib/core/models/assignment.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

class Assignment {
  final String id;
  final String title;
  final String description;
  final String teacherId;
  final String subjectId;
  final String subjectName;
  final String section;
  final DateTime dueDate;
  final DateTime createdAt;

  const Assignment({
    required this.id,
    required this.title,
    required this.description,
    required this.teacherId,
    required this.subjectId,
    required this.subjectName,
    required this.section,
    required this.dueDate,
    required this.createdAt,
  });

  bool get isOverdue => DateTime.now().isAfter(dueDate);

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'teacherId': teacherId,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'section': section,
    'dueDate': Timestamp.fromDate(dueDate),
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Assignment.fromMap(String id, Map<String, dynamic> map) {
    return Assignment(
      id: id,
      title: map['title'] ?? 'Untitled Assignment',
      description: map['description'] ?? '',
      teacherId: map['teacherId'] ?? '',
      subjectId: map['subjectId'] ?? '',
      subjectName: map['subjectName'] ?? 'General Subject',
      section: map['section'] ?? '',
      dueDate: DateParser.parse(map['dueDate'], fieldName: 'Assignment.dueDate'),
      createdAt: DateParser.parse(map['createdAt'], fieldName: 'Assignment.createdAt'),
    );
  }
}

/// One per student per assignment, stored at
/// assignments/{assignmentId}/submissions/{studentId}.
class AssignmentSubmission {
  final String studentId;
  final String studentName;
  final String text;
  final String? filePath; // Firebase Storage path
  final String? fileName;
  final DateTime submittedAt;

  const AssignmentSubmission({
    required this.studentId,
    required this.studentName,
    required this.text,
    this.filePath,
    this.fileName,
    required this.submittedAt,
  });

  Map<String, dynamic> toMap() => {
    'studentId': studentId,
    'studentName': studentName,
    'text': text,
    'filePath': filePath,
    'fileName': fileName,
    'submittedAt': Timestamp.fromDate(submittedAt),
  };

  factory AssignmentSubmission.fromMap(Map<String, dynamic> map) {
    return AssignmentSubmission(
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      text: map['text'] ?? '',
      filePath: map['filePath'],
      fileName: map['fileName'],
      submittedAt: DateParser.parse(map['submittedAt'], fieldName: 'AssignmentSubmission.submittedAt'),
    );
  }
}
