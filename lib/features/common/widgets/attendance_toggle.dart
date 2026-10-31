// lib/features/common/widgets/attendance_toggle.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/attendance.dart';
import '../../../theme.dart';

/// Present / Absent / Late (and optionally Excused) as one compact
/// segmented control. Used when reviewing a session and by admins fixing
/// records.
class AttendanceToggle extends StatelessWidget {
  final AttendanceStatus value;
  final ValueChanged<AttendanceStatus> onChanged;
  final bool showExcused;

  const AttendanceToggle({super.key, required this.value, required this.onChanged, this.showExcused = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget seg(AttendanceStatus s, String label, String tooltip, Color fg) {
      final on = value == s;
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(s);
          },
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? fg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: on ? Colors.white : p.inkMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(13)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(AttendanceStatus.present, 'P', 'Present', p.success),
        seg(AttendanceStatus.absent, 'A', 'Absent', p.danger),
        seg(AttendanceStatus.late, 'L', 'Late', p.warning),
        if (showExcused) seg(AttendanceStatus.excused, 'E', 'Excused', p.accent),
      ]),
    );
  }
}
