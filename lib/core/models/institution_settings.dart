// lib/core/models/institution_settings.dart
//
// Everything that differs between one institute and the next lives here, in a
// single Firestore doc (settings/institution) that admins edit from the
// Institute Settings page. Nothing institution-specific should be hardcoded.

enum InstitutionType { coaching, college, school }

extension InstitutionTypeX on InstitutionType {
  String get label => switch (this) {
        InstitutionType.coaching => 'Coaching Institute',
        InstitutionType.college => 'College',
        InstitutionType.school => 'School',
      };
}

class InstitutionSettings {
  final String name;
  final InstitutionType type;

  /// What a group of students is called: "Batch", "Section", "Class".
  final String groupLabel;
  final List<String> groups;

  /// Timetable grid: start time of each period ("HH:mm") and its length.
  final List<String> periodStarts;
  final int periodMinutes;
  final List<String> workingDays;

  /// Below this attendance %, students are flagged (and parents alerted).
  final int attendanceThreshold;

  /// Internal-marks scheme (colleges). Total = sum of the three.
  final double assignmentMax;
  final double testMax;
  final double attendanceMax;

  final bool internalMarksEnabled;
  final bool remarksEnabled;
  final bool feesEnabled;
  final bool testsEnabled;
  final bool parentAlertsEnabled;

  /// Message parents automatically when a student is marked absent
  /// (needs WhatsApp connected).
  final bool autoAbsenceAlerts;

  /// Non-secret description of the connected WhatsApp sender, e.g.
  /// "+91 98xxxx4321". Empty when not connected. The token itself is stored in
  /// a write-only doc that clients can't read.
  final String whatsappSender;

  final String currencySymbol;

  const InstitutionSettings({
    required this.name,
    required this.type,
    required this.groupLabel,
    required this.groups,
    required this.periodStarts,
    required this.periodMinutes,
    required this.workingDays,
    required this.attendanceThreshold,
    required this.assignmentMax,
    required this.testMax,
    required this.attendanceMax,
    required this.internalMarksEnabled,
    required this.remarksEnabled,
    required this.feesEnabled,
    required this.testsEnabled,
    required this.parentAlertsEnabled,
    this.autoAbsenceAlerts = false,
    this.whatsappSender = '',
    required this.currencySymbol,
  });

  bool get whatsappConnected => whatsappSender.isNotEmpty;

  static const allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Starting point for each kind of institution. Admins can change anything.
  factory InstitutionSettings.preset(InstitutionType type, {String name = 'Batchwise'}) {
    switch (type) {
      case InstitutionType.coaching:
        return InstitutionSettings(
          name: name,
          type: type,
          groupLabel: 'Batch',
          groups: const [],
          periodStarts: const ['07:00', '08:30', '10:00', '16:00', '17:30', '19:00'],
          periodMinutes: 90,
          workingDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          attendanceThreshold: 80,
          assignmentMax: 12,
          testMax: 12,
          attendanceMax: 6,
          internalMarksEnabled: false,
          remarksEnabled: true,
          feesEnabled: true,
          testsEnabled: true,
          parentAlertsEnabled: true,
          currencySymbol: '₹',
        );
      case InstitutionType.college:
        return InstitutionSettings(
          name: name,
          type: type,
          groupLabel: 'Section',
          groups: const [],
          periodStarts: const ['09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00'],
          periodMinutes: 60,
          workingDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          attendanceThreshold: 75,
          assignmentMax: 12,
          testMax: 12,
          attendanceMax: 6,
          internalMarksEnabled: true,
          remarksEnabled: true,
          feesEnabled: false,
          testsEnabled: true,
          parentAlertsEnabled: false,
          currencySymbol: '₹',
        );
      case InstitutionType.school:
        return InstitutionSettings(
          name: name,
          type: type,
          groupLabel: 'Class',
          groups: const [],
          periodStarts: const ['08:00', '08:45', '09:30', '10:30', '11:15', '12:00', '12:45'],
          periodMinutes: 45,
          workingDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          attendanceThreshold: 75,
          assignmentMax: 12,
          testMax: 12,
          attendanceMax: 6,
          internalMarksEnabled: false,
          remarksEnabled: true,
          feesEnabled: true,
          testsEnabled: true,
          parentAlertsEnabled: true,
          currencySymbol: '₹',
        );
    }
  }

  /// Used until an admin saves settings for the first time.
  static final defaults = InstitutionSettings.preset(InstitutionType.coaching);

  double get totalMarksMax => assignmentMax + testMax + attendanceMax;

  String get groupLabelPlural => groupLabel.endsWith('s')
      ? '${groupLabel}es'
      : groupLabel.endsWith('ch')
          ? '${groupLabel}es'
          : '${groupLabel}s';

  List<String> get periodLabels =>
      List.generate(periodStarts.length, (i) => 'P${i + 1}');

  /// Attendance component of internal marks. At or below the threshold earns
  /// nothing, 100% earns the full amount, and the range in between is split
  /// into equal bands worth one mark each.
  /// (With the 75% / 6-mark defaults: 76-80 → 1, 81-85 → 2, ... 96-99 → 5.)
  int attendanceMarksFor(int pct) {
    final max = attendanceMax.round();
    if (max <= 0 || pct <= attendanceThreshold) return 0;
    if (pct >= 100) return max;
    if (max == 1) return 0;
    final band = (100 - attendanceThreshold) / (max - 1);
    return ((pct - attendanceThreshold) / band).ceil().clamp(1, max - 1);
  }

  /// Period end time for a given start ("HH:mm").
  String endTimeFor(String start) {
    final parts = start.split(':');
    final mins = int.parse(parts[0]) * 60 + int.parse(parts[1]) + periodMinutes;
    return '${(mins ~/ 60 % 24).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.name,
        'groupLabel': groupLabel,
        'groups': groups,
        'periodStarts': periodStarts,
        'periodMinutes': periodMinutes,
        'workingDays': workingDays,
        'attendanceThreshold': attendanceThreshold,
        'assignmentMax': assignmentMax,
        'testMax': testMax,
        'attendanceMax': attendanceMax,
        'internalMarksEnabled': internalMarksEnabled,
        'remarksEnabled': remarksEnabled,
        'feesEnabled': feesEnabled,
        'testsEnabled': testsEnabled,
        'parentAlertsEnabled': parentAlertsEnabled,
        'autoAbsenceAlerts': autoAbsenceAlerts,
        'whatsappSender': whatsappSender,
        'currencySymbol': currencySymbol,
      };

  factory InstitutionSettings.fromMap(Map<String, dynamic> map) {
    final type = InstitutionType.values.firstWhere(
      (t) => t.name == map['type'],
      orElse: () => InstitutionType.coaching,
    );
    // Missing fields fall back to the preset for this type, so older docs
    // keep working when new settings are added.
    final base = InstitutionSettings.preset(type);
    List<String> strList(dynamic v, List<String> fallback) =>
        v is List ? v.map((e) => e.toString()).toList() : fallback;
    double dbl(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
    bool flag(dynamic v, bool fallback) => v is bool ? v : fallback;

    return InstitutionSettings(
      name: (map['name'] as String?)?.trim().isNotEmpty == true ? map['name'] : base.name,
      type: type,
      groupLabel: (map['groupLabel'] as String?)?.trim().isNotEmpty == true ? map['groupLabel'] : base.groupLabel,
      groups: strList(map['groups'], base.groups),
      periodStarts: strList(map['periodStarts'], base.periodStarts),
      periodMinutes: map['periodMinutes'] is int ? map['periodMinutes'] : base.periodMinutes,
      workingDays: strList(map['workingDays'], base.workingDays),
      attendanceThreshold: map['attendanceThreshold'] is int ? map['attendanceThreshold'] : base.attendanceThreshold,
      assignmentMax: dbl(map['assignmentMax'], base.assignmentMax),
      testMax: dbl(map['testMax'], base.testMax),
      attendanceMax: dbl(map['attendanceMax'], base.attendanceMax),
      internalMarksEnabled: flag(map['internalMarksEnabled'], base.internalMarksEnabled),
      remarksEnabled: flag(map['remarksEnabled'], base.remarksEnabled),
      feesEnabled: flag(map['feesEnabled'], base.feesEnabled),
      testsEnabled: flag(map['testsEnabled'], base.testsEnabled),
      parentAlertsEnabled: flag(map['parentAlertsEnabled'], base.parentAlertsEnabled),
      autoAbsenceAlerts: flag(map['autoAbsenceAlerts'], false),
      whatsappSender: (map['whatsappSender'] as String?) ?? '',
      currencySymbol: (map['currencySymbol'] as String?) ?? base.currencySymbol,
    );
  }

  InstitutionSettings copyWith({
    String? name,
    InstitutionType? type,
    String? groupLabel,
    List<String>? groups,
    List<String>? periodStarts,
    int? periodMinutes,
    List<String>? workingDays,
    int? attendanceThreshold,
    double? assignmentMax,
    double? testMax,
    double? attendanceMax,
    bool? internalMarksEnabled,
    bool? remarksEnabled,
    bool? feesEnabled,
    bool? testsEnabled,
    bool? parentAlertsEnabled,
    bool? autoAbsenceAlerts,
    String? whatsappSender,
    String? currencySymbol,
  }) {
    return InstitutionSettings(
      name: name ?? this.name,
      type: type ?? this.type,
      groupLabel: groupLabel ?? this.groupLabel,
      groups: groups ?? this.groups,
      periodStarts: periodStarts ?? this.periodStarts,
      periodMinutes: periodMinutes ?? this.periodMinutes,
      workingDays: workingDays ?? this.workingDays,
      attendanceThreshold: attendanceThreshold ?? this.attendanceThreshold,
      assignmentMax: assignmentMax ?? this.assignmentMax,
      testMax: testMax ?? this.testMax,
      attendanceMax: attendanceMax ?? this.attendanceMax,
      internalMarksEnabled: internalMarksEnabled ?? this.internalMarksEnabled,
      remarksEnabled: remarksEnabled ?? this.remarksEnabled,
      feesEnabled: feesEnabled ?? this.feesEnabled,
      testsEnabled: testsEnabled ?? this.testsEnabled,
      parentAlertsEnabled: parentAlertsEnabled ?? this.parentAlertsEnabled,
      autoAbsenceAlerts: autoAbsenceAlerts ?? this.autoAbsenceAlerts,
      whatsappSender: whatsappSender ?? this.whatsappSender,
      currencySymbol: currencySymbol ?? this.currencySymbol,
    );
  }
}
