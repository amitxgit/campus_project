// lib/core/models/enquiry.dart
//
// A prospective student who asked about joining: walk-in, call, referral...
// Admins follow up until they join or are lost.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/date_parser.dart';
import 'role.dart';
import 'user.dart';

enum EnquirySource { walkIn, call, referral, instagram, justdial, other }

extension EnquirySourceX on EnquirySource {
  String get label => switch (this) {
        EnquirySource.walkIn => 'Walk-in',
        EnquirySource.call => 'Call',
        EnquirySource.referral => 'Referral',
        EnquirySource.instagram => 'Instagram',
        EnquirySource.justdial => 'Justdial',
        EnquirySource.other => 'Other',
      };

  static EnquirySource parse(String? name) =>
      EnquirySource.values.firstWhere((s) => s.name == name, orElse: () => EnquirySource.other);
}

enum EnquiryStatus { newEnquiry, contacted, demoBooked, joined, lost }

extension EnquiryStatusX on EnquiryStatus {
  /// Stored value. `new` is a Dart keyword, hence the enum name.
  String get key => this == EnquiryStatus.newEnquiry ? 'new' : name;

  String get label => switch (this) {
        EnquiryStatus.newEnquiry => 'New',
        EnquiryStatus.contacted => 'Contacted',
        EnquiryStatus.demoBooked => 'Demo booked',
        EnquiryStatus.joined => 'Joined',
        EnquiryStatus.lost => 'Lost',
      };

  /// Still being followed up.
  bool get isOpen => this != EnquiryStatus.joined && this != EnquiryStatus.lost;

  static EnquiryStatus parse(String? key) =>
      EnquiryStatus.values.firstWhere((s) => s.key == key, orElse: () => EnquiryStatus.newEnquiry);
}

class Enquiry {
  final String id;
  final String name;
  final String phone;
  final String parentName;
  final String parentPhone;

  /// Class or course of interest, e.g. "Class 11 JEE".
  final String course;

  /// Batch they'd join (one of the institute's groups), if known.
  final String batch;
  final EnquirySource source;
  final EnquiryStatus status;
  final DateTime? nextFollowUp;
  final String notes;
  final String createdBy;

  /// Set once converted: the new student's uid.
  final String? studentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Enquiry({
    required this.id,
    required this.name,
    this.phone = '',
    this.parentName = '',
    this.parentPhone = '',
    this.course = '',
    this.batch = '',
    this.source = EnquirySource.walkIn,
    this.status = EnquiryStatus.newEnquiry,
    this.nextFollowUp,
    this.notes = '',
    required this.createdBy,
    this.studentId,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Open and the follow-up date is today or already past.
  bool isDue(DateTime now) =>
      status.isOpen && nextFollowUp != null && !_day(nextFollowUp!).isAfter(_day(now));

  bool isOverdue(DateTime now) =>
      status.isOpen && nextFollowUp != null && _day(nextFollowUp!).isBefore(_day(now));

  /// Number to message: the parent's if given, else the student's own.
  String get contactPhone => parentPhone.trim().isNotEmpty ? parentPhone.trim() : phone.trim();

  /// Plain WhatsApp follow-up (wa.me, no template needed).
  String followUpMessage(String institute) {
    final who = parentName.trim().isNotEmpty ? parentName.trim().split(' ').first : name.trim().split(' ').first;
    final about = course.trim().isNotEmpty ? ' about ${course.trim()}' : '';
    return 'Hello $who, this is $institute. Thank you for your enquiry$about for ${name.trim()}. '
        'Would you like to visit for a free demo class? Reply here and we will book a time.';
  }

  /// A new student profile pre-filled from this enquiry, for Add User.
  UserAccount toStudentDraft(String newId) => UserAccount(
        id: newId,
        role: UserRole.student,
        name: name.trim(),
        email: '',
        phone: phone.trim(),
        parentName: parentName.trim(),
        parentPhone: parentPhone.trim(),
        section: batch.trim().isEmpty ? null : batch.trim(),
        createdAt: DateTime.now(),
        isActive: true,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'parentName': parentName,
        'parentPhone': parentPhone,
        'course': course,
        'batch': batch,
        'source': source.name,
        'status': status.key,
        'nextFollowUp': nextFollowUp == null ? null : Timestamp.fromDate(nextFollowUp!),
        'notes': notes,
        'createdBy': createdBy,
        if (studentId != null) 'studentId': studentId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory Enquiry.fromMap(String id, Map<String, dynamic> map) => Enquiry(
        id: id,
        name: map['name'] ?? '',
        phone: map['phone'] ?? '',
        parentName: map['parentName'] ?? '',
        parentPhone: map['parentPhone'] ?? '',
        course: map['course'] ?? '',
        batch: map['batch'] ?? '',
        source: EnquirySourceX.parse(map['source'] as String?),
        status: EnquiryStatusX.parse(map['status'] as String?),
        nextFollowUp: map['nextFollowUp'] == null
            ? null
            : DateParser.parse(map['nextFollowUp'], fieldName: 'Enquiry.nextFollowUp'),
        notes: map['notes'] ?? '',
        createdBy: map['createdBy'] ?? '',
        studentId: map['studentId'] as String?,
        createdAt: DateParser.parse(map['createdAt'], fieldName: 'Enquiry.createdAt'),
        updatedAt: DateParser.parse(map['updatedAt'], fieldName: 'Enquiry.updatedAt'),
      );

  Enquiry copyWith({
    String? name,
    String? phone,
    String? parentName,
    String? parentPhone,
    String? course,
    String? batch,
    EnquirySource? source,
    EnquiryStatus? status,
    DateTime? nextFollowUp,
    bool clearFollowUp = false,
    String? notes,
    String? studentId,
  }) =>
      Enquiry(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        parentName: parentName ?? this.parentName,
        parentPhone: parentPhone ?? this.parentPhone,
        course: course ?? this.course,
        batch: batch ?? this.batch,
        source: source ?? this.source,
        status: status ?? this.status,
        nextFollowUp: clearFollowUp ? null : (nextFollowUp ?? this.nextFollowUp),
        notes: notes ?? this.notes,
        createdBy: createdBy,
        studentId: studentId ?? this.studentId,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// This month's enquiries and how many of them joined.
class EnquiryConversion {
  final int total;
  final int joined;
  const EnquiryConversion(this.total, this.joined);

  /// Whole-number percentage; 0 when there were no enquiries.
  int get percent => total == 0 ? 0 : (joined * 100 / total).round();

  static DateTime monthStart(DateTime now) => DateTime(now.year, now.month);

  /// Counts enquiries created this calendar month (by [now]).
  factory EnquiryConversion.forMonth(Iterable<Enquiry> all, DateTime now) {
    final start = monthStart(now);
    final end = DateTime(now.year, now.month + 1);
    final month = all.where((e) => !e.createdAt.isBefore(start) && e.createdAt.isBefore(end)).toList();
    return EnquiryConversion(month.length, month.where((e) => e.status == EnquiryStatus.joined).length);
  }
}
