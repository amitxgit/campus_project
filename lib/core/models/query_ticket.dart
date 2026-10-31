// lib/core/models/query_ticket.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

enum QueryStatus { open, inProgress, resolved, rejected }

extension QueryStatusX on QueryStatus {
  String get label {
    switch (this) {
      case QueryStatus.open: return "Open";
      case QueryStatus.inProgress: return "In progress";
      case QueryStatus.resolved: return "Resolved";
      case QueryStatus.rejected: return "Rejected";
    }
  }

  static QueryStatus fromName(String? val) {
    return QueryStatus.values.firstWhere(
          (e) => e.name == val,
      orElse: () => QueryStatus.open,
    );
  }
}

class QueryTicket {
  final String id;
  final String raisedByStudentId;
  final String? subjectId;
  final String title;
  final String message;
  final List<String> attachments;
  final QueryStatus status;
  final String? assignedToTeacherId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QueryTicket({
    required this.id,
    required this.raisedByStudentId,
    this.subjectId,
    required this.title,
    required this.message,
    this.attachments = const [],
    this.status = QueryStatus.open,
    this.assignedToTeacherId,
    required this.createdAt,
    required this.updatedAt,
  });

  QueryTicket copyWith({
    String? id,
    String? raisedByStudentId,
    String? subjectId,
    String? title,
    String? message,
    List<String>? attachments,
    QueryStatus? status,
    String? assignedToTeacherId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QueryTicket(
      id: id ?? this.id,
      raisedByStudentId: raisedByStudentId ?? this.raisedByStudentId,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      message: message ?? this.message,
      attachments: attachments ?? this.attachments,
      status: status ?? this.status,
      assignedToTeacherId: assignedToTeacherId ?? this.assignedToTeacherId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'raisedByStudentId': raisedByStudentId,
    'subjectId': subjectId,
    'title': title,
    'message': message,
    'attachments': attachments,
    'status': status.name,
    'assignedToTeacherId': assignedToTeacherId,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory QueryTicket.fromMap(String id, Map<String, dynamic> map) {
    return QueryTicket(
      id: id,
      raisedByStudentId: map['raisedByStudentId'] ?? '',
      subjectId: map['subjectId'],
      title: map['title'] ?? 'No Title',
      message: map['message'] ?? '',
      attachments: (map['attachments'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      status: QueryStatusX.fromName(map['status']),
      assignedToTeacherId: map['assignedToTeacherId'],
      createdAt: DateParser.parse(map['createdAt'], fieldName: 'QueryTicket.createdAt'),
      updatedAt: DateParser.parse(map['updatedAt'], fieldName: 'QueryTicket.updatedAt'),
    );
  }
}