// lib/features/admin/institution_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/institution_settings.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../common/widgets/app_drawer.dart';

class InstitutionSettingsPage extends ConsumerStatefulWidget {
  const InstitutionSettingsPage({super.key});

  @override
  ConsumerState<InstitutionSettingsPage> createState() => _InstitutionSettingsPageState();
}

class _InstitutionSettingsPageState extends ConsumerState<InstitutionSettingsPage> {
  InstitutionSettings? _draft;
  final _nameCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  void _load(InstitutionSettings s) {
    _draft = s;
    _nameCtrl.text = s.name;
    _labelCtrl.text = s.groupLabel;
  }

  void _update(InstitutionSettings Function(InstitutionSettings) fn) {
    setState(() => _draft = fn(_draft!));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _draft == null || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(FirebaseErrorParser.getMessage(e))),
        data: (saved) {
          if (_draft == null) _load(saved);
          final s = _draft!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card('Institute', Icons.apartment_rounded, [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Institute name', border: OutlineInputBorder()),
                  onChanged: (v) => _update((d) => d.copyWith(name: v)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InstitutionType>(
                  initialValue: s.type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: InstitutionType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (t) => t == null ? null : _changeType(t),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'What do you call a group of students?',
                    helperText: 'e.g. Batch, Section, Class',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _update((d) => d.copyWith(groupLabel: v.trim())),
                ),
              ]),

              _card(s.groupLabelPlural, Icons.groups_rounded, [
                if (s.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('No ${s.groupLabelPlural.toLowerCase()} yet. Add one below.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: s.groups
                      .map((g) => InputChip(
                            label: Text(g),
                            onDeleted: () => _update((d) => d.copyWith(groups: [...d.groups]..remove(g))),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _groupCtrl,
                        decoration: InputDecoration(
                          labelText: 'New ${s.groupLabel.toLowerCase()} name',
                          hintText: 'e.g. JEE-2027-A',
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addGroup(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _addGroup, icon: const Icon(Icons.add)),
                  ],
                ),
              ]),

              _card('Schedule', Icons.schedule_rounded, [
                const Text('Working days', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: InstitutionSettings.allDays
                      .map((day) => FilterChip(
                            label: Text(day),
                            selected: s.workingDays.contains(day),
                            onSelected: (on) => _update((d) => d.copyWith(
                                  workingDays: InstitutionSettings.allDays
                                      .where((x) => x == day ? on : d.workingDays.contains(x))
                                      .toList(),
                                )),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: s.periodMinutes,
                  decoration: const InputDecoration(labelText: 'Class length', border: OutlineInputBorder()),
                  items: const [30, 40, 45, 50, 60, 75, 90, 120]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m minutes')))
                      .toList(),
                  onChanged: (m) => m == null ? null : _update((d) => d.copyWith(periodMinutes: m)),
                ),
                const SizedBox(height: 16),
                const Text('Class start times', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...s.periodStarts.map((t) => InputChip(
                          label: Text('$t–${s.endTimeFor(t)}'),
                          onDeleted: () => _update((d) => d.copyWith(periodStarts: [...d.periodStarts]..remove(t))),
                        )),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add slot'),
                      onPressed: _addSlot,
                    ),
                  ],
                ),
              ]),

              _card('Attendance', Icons.fact_check_rounded, [
                Text('Minimum attendance: ${s.attendanceThreshold}%',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: s.attendanceThreshold.toDouble(),
                  min: 50,
                  max: 95,
                  divisions: 9,
                  label: '${s.attendanceThreshold}%',
                  onChanged: (v) => _update((d) => d.copyWith(attendanceThreshold: v.round())),
                ),
                Text('Students below this are flagged${s.parentAlertsEnabled ? ' and parents can be alerted' : ''}.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ]),

              _card('Features', Icons.toggle_on_rounded, [
                _switch('Fee tracking', 'Instalments, payments and dues', s.feesEnabled,
                    (v) => _update((d) => d.copyWith(feesEnabled: v))),
                _switch('Tests & results', 'Test marks, ranks and report cards', s.testsEnabled,
                    (v) => _update((d) => d.copyWith(testsEnabled: v))),
                _switch('Parent alerts', 'Absence, fee and result messages to parents', s.parentAlertsEnabled,
                    (v) => _update((d) => d.copyWith(parentAlertsEnabled: v))),
                _switch('Teacher remarks', 'Private notes on students', s.remarksEnabled,
                    (v) => _update((d) => d.copyWith(remarksEnabled: v))),
                _switch('Internal marks', 'College-style assignment/test/attendance marks', s.internalMarksEnabled,
                    (v) => _update((d) => d.copyWith(internalMarksEnabled: v))),
              ]),

              if (s.internalMarksEnabled)
                _card('Internal marks scheme', Icons.military_tech_rounded, [
                  Row(
                    children: [
                      _numField('Assignment', s.assignmentMax, (v) => _update((d) => d.copyWith(assignmentMax: v))),
                      const SizedBox(width: 8),
                      _numField('Test', s.testMax, (v) => _update((d) => d.copyWith(testMax: v))),
                      const SizedBox(width: 8),
                      _numField('Attendance', s.attendanceMax, (v) => _update((d) => d.copyWith(attendanceMax: v))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Total: ${s.totalMarksMax.toStringAsFixed(0)} marks',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _switch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _numField(String label, double value, ValueChanged<double> onChanged) {
    return Expanded(
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: (v) {
          final n = double.tryParse(v);
          if (n != null && n >= 0) onChanged(n);
        },
      ),
    );
  }

  void _addGroup() {
    final name = _groupCtrl.text.trim();
    if (name.isEmpty || _draft!.groups.contains(name)) return;
    _update((d) => d.copyWith(groups: [...d.groups, name]));
    _groupCtrl.clear();
  }

  Future<void> _addSlot() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (picked == null) return;
    final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (_draft!.periodStarts.contains(t)) return;
    _update((d) => d.copyWith(periodStarts: [...d.periodStarts, t]..sort()));
  }

  Future<void> _changeType(InstitutionType type) async {
    if (type == _draft!.type) return;
    final applyPreset = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to ${type.label}?'),
        content: const Text(
            'Apply the recommended defaults for this type (naming, class timings, features)? '
            'Your name and student groups are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Only change type')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply defaults')),
        ],
      ),
    );
    if (applyPreset == null) return;
    setState(() {
      if (applyPreset) {
        _draft = InstitutionSettings.preset(type, name: _draft!.name).copyWith(groups: _draft!.groups);
        _labelCtrl.text = _draft!.groupLabel;
      } else {
        _draft = _draft!.copyWith(type: type);
      }
    });
  }

  Future<void> _save() async {
    final s = _draft!;
    if (s.name.trim().isEmpty || s.groupLabel.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and group label are required.')));
      return;
    }
    if (s.periodStarts.isEmpty || s.workingDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one working day and class time.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepoProvider).save(s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorParser.getMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
