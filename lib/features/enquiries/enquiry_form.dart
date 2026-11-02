// lib/features/enquiries/enquiry_form.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/enquiry.dart';
import '../../core/models/institution_settings.dart';
import '../../core/utils/phone.dart';
import '../../theme.dart';

/// Add or edit an enquiry. Teachers add only ([showStatus] false); the status
/// of a new enquiry is always "new".
Future<Enquiry?> showEnquiryForm(
  BuildContext context, {
  required InstitutionSettings settings,
  required String createdBy,
  Enquiry? initial,
  bool showStatus = false,
}) {
  return showDialog<Enquiry>(
    context: context,
    builder: (_) => _EnquiryForm(settings: settings, createdBy: createdBy, initial: initial, showStatus: showStatus),
  );
}

class _EnquiryForm extends StatefulWidget {
  final InstitutionSettings settings;
  final String createdBy;
  final Enquiry? initial;
  final bool showStatus;
  const _EnquiryForm({required this.settings, required this.createdBy, this.initial, required this.showStatus});

  @override
  State<_EnquiryForm> createState() => _EnquiryFormState();
}

class _EnquiryFormState extends State<_EnquiryForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _parentName = TextEditingController(text: widget.initial?.parentName);
  late final _parentPhone = TextEditingController(text: widget.initial?.parentPhone);
  late final _course = TextEditingController(text: widget.initial?.course);
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late String _batch = widget.initial?.batch ?? '';
  late EnquirySource _source = widget.initial?.source ?? EnquirySource.walkIn;
  late EnquiryStatus _status = widget.initial?.status ?? EnquiryStatus.newEnquiry;
  late DateTime? _followUp = widget.initial == null
      ? DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1))
      : widget.initial!.nextFollowUp;

  @override
  void dispose() {
    for (final c in [_name, _phone, _parentName, _parentPhone, _course, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _phoneCheck(String? v) =>
      (v == null || v.trim().isEmpty || PhoneNumber.normalize(v) != null) ? null : 'Enter a valid mobile number';

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final base = widget.initial ??
        Enquiry(id: '', name: '', createdBy: widget.createdBy, createdAt: now, updatedAt: now);
    Navigator.pop(
      context,
      base.copyWith(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        parentName: _parentName.text.trim(),
        parentPhone: _parentPhone.text.trim(),
        course: _course.text.trim(),
        batch: _batch,
        source: _source,
        status: _status,
        nextFollowUp: _status.isOpen ? _followUp : null,
        clearFollowUp: !_status.isOpen || _followUp == null,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final groups = <String>{...widget.settings.groups, if (_batch.isNotEmpty) _batch}.toList();

    Widget chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onPick) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => onPick(v)),
              ),
          ],
        );

    Widget caption(String text) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(text, style: TextStyle(color: p.inkMuted, fontSize: 13, fontWeight: FontWeight.w500)),
        );

    return AlertDialog(
      title: Text(widget.initial == null ? 'New enquiry' : 'Edit enquiry'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: widget.initial == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Student name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Student mobile'),
                  validator: (v) {
                    final own = _phoneCheck(v);
                    if (own != null) return own;
                    if ((v ?? '').trim().isEmpty && _parentPhone.text.trim().isEmpty) {
                      return 'Add a student or parent number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _parentName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Parent name'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _parentPhone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Parent WhatsApp'),
                      validator: _phoneCheck,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _course,
                  decoration: const InputDecoration(labelText: 'Class / course', hintText: 'e.g. Class 11 JEE'),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _batch,
                    decoration: InputDecoration(labelText: widget.settings.groupLabel),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Not decided')),
                      for (final g in groups) DropdownMenuItem(value: g, child: Text(g)),
                    ],
                    onChanged: (v) => _batch = v ?? '',
                  ),
                ],
                caption('Source'),
                chips(EnquirySource.values, _source, (s) => s.label, (v) => _source = v),
                if (widget.showStatus) ...[
                  caption('Status'),
                  chips(EnquiryStatus.values, _status, (s) => s.label, (v) => _status = v),
                ],
                if (_status.isOpen)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_followUp == null
                        ? 'No follow-up set'
                        : 'Follow up on ${DateFormat('EEE, d MMM').format(_followUp!)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_followUp != null)
                        IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => setState(() => _followUp = null),
                        ),
                      TextButton(
                        child: Text(_followUp == null ? 'Set' : 'Change'),
                        onPressed: () async {
                          final today = DateUtils.dateOnly(DateTime.now());
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _followUp != null && !_followUp!.isBefore(today) ? _followUp! : today,
                            firstDate: today,
                            lastDate: today.add(const Duration(days: 365)),
                          );
                          if (picked != null) setState(() => _followUp = picked);
                        },
                      ),
                    ]),
                  ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _notes,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.initial == null ? 'Add' : 'Save')),
      ],
    );
  }
}
