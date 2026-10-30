// lib/features/common/widgets/override_class_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../core/models/timetable_entry.dart';
import '../../../core/models/notification.dart';
import '../../../main.dart';

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
    return AlertDialog(
      title: Text('Manage: ${widget.subjectName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scheduled: ${widget.entry.startTime} – ${widget.entry.endTime}',
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Action', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Cancel', child: Text('Cancel Class', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              DropdownMenuItem(value: 'Reschedule', child: Text('Reschedule (Time/Room)')),
              DropdownMenuItem(value: 'Restore', child: Text('Restore Original Schedule')),
            ],
            onChanged: (v) => setState(() => _action = v!),
          ),
          if (_action == 'Reschedule') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _timeCtrl,
              decoration: const InputDecoration(labelText: 'New Time (e.g. 10:30)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roomCtrl,
              decoration: const InputDecoration(labelText: 'New Room', border: OutlineInputBorder()),
            ),
          ]
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submitOverride,
          style: FilledButton.styleFrom(
            backgroundColor: _action == 'Cancel' ? Colors.red : Theme.of(context).colorScheme.primary,
          ),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Apply Update'),
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
            type: NotificationType.general,
          );
        }
      }

      // Tell the Dashboard to refresh its data
      widget.onOverrideComplete();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_action == 'Restore' ? 'Schedule Restored' : 'Class updated successfully!'),
              backgroundColor: Colors.green,
            )
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }
}