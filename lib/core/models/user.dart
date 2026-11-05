// lib/core/models/user.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'role.dart';
import '../utils/date_parser.dart';

class UserAccount {
  final String id;
  final UserRole role;
  final String name;
  final String? email;
  final String phone;
  final DateTime createdAt;
  final bool isActive;
  final String? collegeRollNo;
  final String? examRollNo;
  final String? section;
  final int? year;
  final List<String> qualifications;
  final String? idCardPhotoPath;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? course;
  final int? semester;

  // ✅ NEW: Admin Override Flag
  final bool isAdmin;

  // Students only: who receives absence, fee and result alerts.
  final String? parentName;
  final String? parentPhone;

  const UserAccount({
    required this.id,
    required this.role,
    required this.name,
    this.email,
    required this.phone,
    required this.createdAt,
    this.isActive = true,
    this.collegeRollNo,
    this.examRollNo,
    this.section,
    this.year,
    this.qualifications = const [],
    this.idCardPhotoPath,
    this.gender,
    this.dateOfBirth,
    this.course,
    this.semester,
    this.isAdmin = false, // Default to false
    this.parentName,
    this.parentPhone,
  });

  UserAccount copyWith({
    String? id,
    UserRole? role,
    String? name,
    String? email,
    String? phone,
    DateTime? createdAt,
    bool? isActive,
    String? collegeRollNo,
    String? examRollNo,
    String? section,
    int? year,
    List<String>? qualifications,
    String? idCardPhotoPath,
    String? gender,
    DateTime? dateOfBirth,
    String? course,
    int? semester,
    bool? isAdmin,
    String? parentName,
    String? parentPhone,
  }) {
    return UserAccount(
      id: id ?? this.id,
      role: role ?? this.role,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      collegeRollNo: collegeRollNo ?? this.collegeRollNo,
      examRollNo: examRollNo ?? this.examRollNo,
      section: section ?? this.section,
      year: year ?? this.year,
      qualifications: qualifications ?? this.qualifications,
      idCardPhotoPath: idCardPhotoPath ?? this.idCardPhotoPath,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      course: course ?? this.course,
      semester: semester ?? this.semester,
      isAdmin: isAdmin ?? this.isAdmin,
      parentName: parentName ?? this.parentName,
      parentPhone: parentPhone ?? this.parentPhone,
    );
  }

  Map<String, dynamic> toMap() {
    String? dobStr;
    if (dateOfBirth != null) {
      final d = dateOfBirth!.day.toString().padLeft(2, '0');
      final m = dateOfBirth!.month.toString().padLeft(2, '0');
      final y = dateOfBirth!.year.toString();
      dobStr = '$d-$m-$y';
    }

    return {
      'role': role.key,
      'name': name,
      'email': email,
      'phone': phone,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'collegeRollNo': collegeRollNo,
      'examRollNo': examRollNo,
      'section': section,
      'year': year,
      'qualifications': qualifications,
      'idCardPhotoPath': idCardPhotoPath,
      'gender': gender,
      'date_of_birth': dobStr,
      'course': course,
      'semester': semester,
      'isAdmin': isAdmin,
      'parentName': parentName,
      'parentPhone': parentPhone,
    };
  }

  factory UserAccount.fromMap(String id, Map<String, dynamic> map) {
    int? parsedSemester;
    if (map['semester'] != null) {
      if (map['semester'] is int) {
        parsedSemester = map['semester'];
      } else {
        parsedSemester = int.tryParse(map['semester'].toString());
      }
    }

    int? parsedYear;
    if (map['year'] != null) {
      if (map['year'] is int) {
        parsedYear = map['year'];
      } else {
        parsedYear = int.tryParse(map['year'].toString());
      }
    }

    if (parsedYear == null && parsedSemester != null) {
      parsedYear = (parsedSemester / 2.0).ceil();
    }

    DateTime? dob;
    if (map['date_of_birth'] != null) {
      try {
        final parts = map['date_of_birth'].toString().split('-');
        if (parts.length == 3) {
          final day = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          dob = DateTime(year, month, day);
        }
      } catch (e) {
        debugPrint('Failed to parse date_of_birth: ${map['date_of_birth']}');
      }
    }

    bool active = true;
    if (map['isActive'] != null) {
      if (map['isActive'] is bool) {
        active = map['isActive'];
      } else {
        active = map['isActive'].toString().toLowerCase() != 'false';
      }
    }

    // Safely parse isAdmin
    bool adminFlag = false;
    if (map['isAdmin'] != null) {
      if (map['isAdmin'] is bool) {
        adminFlag = map['isAdmin'];
      } else {
        adminFlag = map['isAdmin'].toString().toLowerCase() == 'true';
      }
    }

    return UserAccount(
      id: id,
      role: UserRoleX.fromString(map['role']?.toString() ?? ''),
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString(),
      phone: map['phone']?.toString() ?? '',
      createdAt: DateParser.parse(map['createdAt'], fieldName: 'UserAccount.createdAt'),
      isActive: active,
      collegeRollNo: map['collegeRollNo']?.toString(),
      examRollNo: map['examRollNo']?.toString(),
      section: map['section']?.toString(),
      year: parsedYear,
      qualifications: (map['qualifications'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      idCardPhotoPath: map['idCardPhotoPath']?.toString(),
      gender: map['gender']?.toString(),
      dateOfBirth: dob,
      course: map['course']?.toString(),
      semester: parsedSemester,
      isAdmin: adminFlag, // ✅ Assigning the parsed flag
      parentName: map['parentName']?.toString(),
      parentPhone: map['parentPhone']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserAccount &&
        other.id == id &&
        other.role == role &&
        other.name == name &&
        other.email == email &&
        other.phone == phone &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.collegeRollNo == collegeRollNo &&
        other.examRollNo == examRollNo &&
        other.section == section &&
        other.year == year &&
        other.idCardPhotoPath == idCardPhotoPath &&
        other.gender == gender &&
        other.dateOfBirth == dateOfBirth &&
        other.course == course &&
        other.semester == semester &&
        other.isAdmin == isAdmin &&
        other.parentName == parentName &&
        other.parentPhone == parentPhone &&
        listEquals(other.qualifications, qualifications);
  }

  @override
  int get hashCode => Object.hash(
    id, role, name, email, phone, isActive, createdAt, collegeRollNo,
    examRollNo, section, year, idCardPhotoPath, gender, dateOfBirth, course, semester, isAdmin,
    parentName, parentPhone, Object.hashAll(qualifications),
  );
}