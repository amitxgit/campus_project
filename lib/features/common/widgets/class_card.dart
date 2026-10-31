// lib/features/common/widgets/class_card.dart
import 'package:flutter/material.dart';

import '../../../core/utils/time_formatter.dart';
import '../../../theme.dart';
import 'ui_kit.dart';

/// One class in a day's schedule: time on the left, subject and place on the
/// right. Shared by the student and teacher home screens.
class ClassCard extends StatelessWidget {
  final String startTime; // "HH:mm"
  final int durationMinutes;
  final String subject;
  final String meta; // e.g. "JEE-2027-A · Room 4"
  final bool cancelled;
  final bool rescheduled;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  /// Highlight the class while it is running. Off when the card isn't for today.
  final bool showLive;

  const ClassCard({
    super.key,
    required this.startTime,
    required this.durationMinutes,
    required this.subject,
    required this.meta,
    this.cancelled = false,
    this.rescheduled = false,
    this.trailing,
    this.footer,
    this.onTap,
    this.showLive = true,
  });

  /// "4" -> "Room 4", but "Hall A" stays "Hall A".
  static String roomLabel(String room) =>
      room.isEmpty ? '' : (RegExp(r'^\d').hasMatch(room) ? 'Room $room' : room);

  /// True while the class is running.
  static bool isNow(String startTime, int durationMinutes) {
    final parts = startTime.split(':');
    if (parts.length < 2) return false;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    return !now.isBefore(start) && now.isBefore(start.add(Duration(minutes: durationMinutes)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = showLive && !cancelled && isNow(startTime, durationMinutes);
    final time = TimeFormatter.formatTime(startTime).split(' ');

    final card = AnimatedContainer(
      duration: Motion.medium,
      decoration: BoxDecoration(
        color: live ? p.accentSoft : p.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time.first,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: cancelled ? p.inkFaint : (live ? p.accent : p.ink),
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (time.length > 1)
                      Text(time[1], style: TextStyle(fontSize: 12, color: p.inkMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: cancelled ? p.inkFaint : p.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.inkMuted)),
                    if (cancelled || rescheduled || live) ...[
                      const SizedBox(height: 8),
                      if (cancelled)
                        StatusPill(text: 'Cancelled', color: p.danger, background: p.dangerSoft)
                      else if (rescheduled)
                        StatusPill(text: 'Rescheduled', color: p.warning, background: p.warningSoft)
                      else
                        StatusPill(text: 'Now', color: p.onAccent, background: p.accent),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.only(right: 8), child: footer!),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, color: Colors.transparent, child: card);
  }
}

/// Friendly empty state used for "no classes today" and similar.
class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const EmptyNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        // min: otherwise it stretches to full height when wrapped in Center.
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: p.inkFaint, size: 28),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.inkMuted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
