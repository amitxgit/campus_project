// lib/core/models/notification.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_parser.dart';

enum NotificationType {
  general, classChange, lowAttendance, queryUpdate, remarkSaved, dailySummary,
}

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final NotificationType type;
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.read = false,
    required this.createdAt,
    this.data,
  });

  AppNotification copyWith({
    String? id,
    String? userId,
    String? title,
    String? body,
    NotificationType? type,
    bool? read,
    DateTime? createdAt,
    Map<String, dynamic>? data,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'title': title,
    'body': body,
    'type': type.name,
    'read': read,
    'createdAt': Timestamp.fromDate(createdAt),
    'data': data,
  };

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? 'Notification',
      body: map['body'] ?? '',
      type: NotificationType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => NotificationType.general,
      ),
      read: map['read'] ?? false,
      createdAt: DateParser.parse(map['createdAt'], fieldName: 'AppNotification.createdAt'),
      data: map['data'] as Map<String, dynamic>?,
    );
  }
}