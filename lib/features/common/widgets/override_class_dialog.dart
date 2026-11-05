// lib/features/common/widgets/override_class_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../core/models/timetable_entry.dart';
import '../../../core/models/notification.dart';
import '../../../core/utils/firebase_error_parser.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../main.dart';
import '../../../theme.dart';
import 'ui_kit.dart';

class OverrideClassDialog extends ConsumerStatefulWidget {
  final TimetableEntry entry;
  final String subjectName;
  final String currentTeacherId;
  final VoidCallback onOverrideComplete; // Triggers the dashboard to refresh

  const OverrideClassDialog({
    super.key,
    required this.entry,
    required this.subjectName,
    required this.currentTeacherId,
    required this.onOverrideComplete,
  });

  @override
  ConsumerState<OverrideClassDialog> createState() => _OverrideClassDialogState();
}

class _OverrideClassDialogState extends ConsumerState<OverrideClassDialog> {
  String _action = 'Cancel';
  final _timeCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _timeCtrl.text = widget.entry.startTime;
    _roomCtrl.text = widget.entry.room;
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text(widget.subjectName),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today, ${TimeFormatter.formatTime(widget.entry.startTime)} – ${TimeFormatter.formatTime(widget.entry.endTime)}',
              style: TextStyle(color: p.inkMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (value, label) in const [('Cancel', 'Cancel'), ('Reschedule', 'Reschedule'), ('Restore', 'Restore')])
                  ChoiceChip(
                    label: Text(label),
                    selected: _action == value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _action = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              switch (_action) {
                'Cancel' => 'Students in ${widget.entry.section} are notified that today\'s class is off.',
                'Reschedule' => 'Students are notified of the new time and room.',
                _ => 'Undo today\'s change and go back to the normal schedule.',
              },
              style: TextStyle(color: p.inkMuted, fontSize: 13),
            ),
            if (_action == 'Reschedule') ...[
              const SizedBox(height: 16),
              TextField(controller: _timeCtrl, decoration: const InputDecoration(labelText: 'New time (HH:MM)')),
              const SizedBox(height: 12),
              TextField(controller: _roomCtrl, decoration: const InputDecoration(labelText: 'Room')),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _isLoading ? null : _submitOverride,
          style: _action == 'Cancel'
              ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white)
              : null,
          child: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(switch (_action) { 'Cancel' => 'Cancel class', 'Reschedule' => 'Reschedule', _ => 'Restore' }),
        ),
      ],
    );
  }

  Future<void> _submitOverride() async {
    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instance;
      final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docId = '${widget.entry.id}_$todayDateStr'; // Unique ID for today's override

      if (_action == 'Restore') {
        // Delete the override to restore the original schedule
        await db.collection('timetable_overrides').doc(docId).delete();
      } else {
        // Create or Update the override
        await db.collection('timetable_overrides').doc(docId).set({
          'entryId': widget.entry.id,
          'section': widget.entry.section,
          'date': todayDateStr,
          'teacherId': widget.currentTeacherId,
          'isCancelled': _action == 'Cancel',
          'newStartTime': _timeCtrl.text.trim(),
          'newRoom': _roomCtrl.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // Send Push Notification to Students in that Section
      if (_action != 'Restore') {
        final students = await ref.read(authRepoProvider).studentsInSection(widget.entry.section);
        final studentIds = students.map((s) => s.id).toList();

        if (studentIds.isNotEmpty) {
          await ref.read(firestoreNotifierProvider).sendToUsers(
            userIds: studentIds,
            title: 'Timetable Update: ${widget.subjectName}',
            body: _action == 'Cancel'
                ? 'Your class today has been cancelled.'
                : 'Class rescheduled to ${_timeCtrl.text.trim()} in Room ${_roomCtrl.text.trim()}.',
            type: NotificationType.classChange,
          );
        }
      }

      // Tell the Dashboard to refresh its data
      widget.onOverrideComplete();

      if (mounted) {
        Navigator.pop(context);
        showMessage(context, _action == 'Restore' ? 'Schedule restored.' : (_action == 'Cancel' ? 'Class cancelled.' : 'Class rescheduled.'), success: true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    }
  }
}