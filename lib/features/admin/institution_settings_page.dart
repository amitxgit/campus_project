// lib/features/admin/institution_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/institution_settings.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../data/settings_repository.dart';
import '../../theme.dart';
import '../common/widgets/app_drawer.dart';
import '../common/widgets/async_error_widget.dart';
import '../common/widgets/ui_kit.dart';

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
  bool _dirty = false;

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
    setState(() {
      _draft = fn(_draft!);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsFutureProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSlide(
        offset: _dirty ? Offset.zero : const Offset(0, 2),
        duration: Motion.medium,
        curve: Motion.curve,
        child: AnimatedOpacity(
          opacity: _dirty ? 1 : 0,
          duration: Motion.fast,
          child: Container(
            width: MediaQuery.sizeOf(context).width - 32,
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Text('Unsaved changes', style: TextStyle(color: p.background, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: p.background.withValues(alpha: 0.7)),
                onPressed: _saving ? null : _discard,
                child: const Text('Discard'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size(88, 44),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
                    : const Text('Save'),
              ),
            ]),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorWidget(
          message: FirebaseErrorParser.getMessage(e),
          onRetry: () => ref.invalidate(settingsFutureProvider),
        ),
        data: (saved) {
          if (_draft == null) _load(saved);
          final s = _draft!;
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _card('Institute', [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Institute name'),
                  onChanged: (v) => _update((d) => d.copyWith(name: v)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InstitutionType>(
                  initialValue: s.type,
                  decoration: const InputDecoration(labelText: 'Type'),
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
                  ),
                  onChanged: (v) => _update((d) => d.copyWith(groupLabel: v.trim())),
                ),
              ]),

              _card(s.groupLabelPlural, [
                if (s.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('No ${s.groupLabelPlural.toLowerCase()} yet. Add one below.',
                        style: TextStyle(color: p.inkMuted)),
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
                        ),
                        onSubmitted: (_) => _addGroup(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(minimumSize: const Size(52, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: _addGroup,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ]),

              _card('Schedule', [
                Text('Working days', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: InstitutionSettings.allDays
                      .map((day) => FilterChip(
                            showCheckmark: false,
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
                  decoration: const InputDecoration(labelText: 'Class length'),
                  items: const [30, 40, 45, 50, 60, 75, 90, 120]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m minutes')))
                      .toList(),
                  onChanged: (m) => m == null ? null : _update((d) => d.copyWith(periodMinutes: m)),
                ),
                const SizedBox(height: 16),
                Text('Class start times', style: TextStyle(fontSize: 13, color: p.inkMuted, fontWeight: FontWeight.w500)),
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
                      avatar: Icon(Icons.add_rounded, size: 18, color: p.accent),
                      label: const Text('Add slot'),
                      onPressed: _addSlot,
                    ),
                  ],
                ),
              ]),

              _card('Attendance', [
                Row(children: [
                  const Expanded(child: Text('Minimum attendance', style: TextStyle(fontWeight: FontWeight.w600))),
                  Text('${s.attendanceThreshold}%', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: p.accent)),
                ]),
                Slider(
                  value: s.attendanceThreshold.toDouble(),
                  min: 50,
                  max: 95,
                  divisions: 9,
                  label: '${s.attendanceThreshold}%',
                  onChanged: (v) => _update((d) => d.copyWith(attendanceThreshold: v.round())),
                ),
                Text('Students below this are flagged${s.parentAlertsEnabled ? ' and parents can be alerted' : ''}.',
                    style: TextStyle(color: p.inkMuted, fontSize: 13)),
              ]),

              _card('Features', [
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
                _card('Internal marks scheme', [
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

  /// A titled group: quiet uppercase label over a soft panel.
  Widget _card(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title, padding: const EdgeInsets.fromLTRB(20, 24, 20, 10)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(20)),
          // Fields sit on the panel, so give them the page colour to stand out.
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(fillColor: context.palette.background),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );
  }

  Widget _switch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: context.palette.inkMuted, fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _numField(String label, double value, ValueChanged<double> onChanged) {
    return Expanded(
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
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
      _dirty = true;
      if (applyPreset) {
        _draft = InstitutionSettings.preset(type, name: _draft!.name).copyWith(groups: _draft!.groups);
        _labelCtrl.text = _draft!.groupLabel;
      } else {
        _draft = _draft!.copyWith(type: type);
      }
    });
  }

  /// Throws away edits and reloads what's saved.
  void _discard() {
    setState(() {
      _draft = null;
      _dirty = false;
      _groupCtrl.clear();
    });
    ref.invalidate(settingsFutureProvider);
  }

  Future<void> _save() async {
    final s = _draft!;
    if (s.name.trim().isEmpty || s.groupLabel.trim().isEmpty) {
      showMessage(context, 'Name and group label are required.', error: true);
      return;
    }
    if (s.periodStarts.isEmpty || s.workingDays.isEmpty) {
      showMessage(context, 'Add at least one working day and class time.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepoProvider).save(s);
      if (mounted) setState(() => _dirty = false);
      if (mounted) {
        showMessage(context, 'Settings saved', success: true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
