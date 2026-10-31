// lib/features/common/widgets/ui_kit.dart
//
// Small building blocks shared by every screen so spacing, motion and colour
// stay consistent. Colours come from `context.palette` (see theme.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme.dart';

/// Fades and lifts its child into place. Pass [index] to stagger lists.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 16});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slow);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    // Cap the stagger so long lists don't keep the user waiting.
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
      ),
    );
  }
}

/// Gives any tappable surface a gentle press-in and a light haptic.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? color;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.color,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: Motion.fast,
      curve: Motion.curve,
      child: Material(
        color: widget.color ?? context.palette.surface,
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A quiet uppercase label that introduces a group of content.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 12)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: context.palette.inkMuted,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Square-ish shortcut tile: icon top-left, label bottom-left.
class ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final bool highlight;

  const ActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = highlight ? p.onAccent : p.ink;

    return Pressable(
      onTap: onTap,
      color: highlight ? p.accent : p.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: fg),
                const Spacer(),
                if (badge != null)
                  Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: highlight ? fg : p.accent)),
              ],
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays [children] out as an even grid of [ActionTile]s that adapts to width.
class ActionGrid extends StatelessWidget {
  final List<Widget> children;
  final double aspectRatio;

  const ActionGrid({super.key, required this.children, this.aspectRatio = 1.2});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth > 900 ? 5 : c.maxWidth > 600 ? 4 : 3;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: aspectRatio,
        children: [
          for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, child: children[i]),
        ],
      );
    });
  }
}

/// A big number with a short label. [tone] colours the number only.
class StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Color? tone;
  final VoidCallback? onTap;

  const StatBlock({super.key, required this.value, required this.label, this.tone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: double.tryParse(value) ?? 0),
              duration: Motion.slow * 2,
              curve: Motion.curve,
              builder: (_, v, __) => Text(
                double.tryParse(value) == null ? value : v.round().toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  height: 1.1,
                  color: tone ?? p.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Thin rounded bar that animates to [value] (0–1). Accent by default.
class ProgressLine extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;

  const ProgressLine({super.key, required this.value, this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: Motion.slow * 2,
        curve: Motion.curve,
        builder: (_, v, __) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: p.surfaceRaised,
          color: color ?? p.accent,
        ),
      ),
    );
  }
}

/// Floating message. [error] / [success] tint it; plain messages stay ink.
void showMessage(BuildContext context, String text, {bool error = false, bool success = false}) {
  final p = context.palette;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? p.danger : (success ? p.success : null),
    ));
}

/// Small rounded label, e.g. "Cancelled", "Paid".
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const StatusPill({super.key, required this.text, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// The Batchwise mark: three stacked bars – a batch, in order – with the
/// middle one in accent blue.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? ink;
  final Color? accent;

  const BrandMark({super.key, this.size = 40, this.ink, this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      size: Size.square(size),
      painter: _BrandMarkPainter(ink ?? p.ink, accent ?? p.accent),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final Color ink;
  final Color accent;
  _BrandMarkPainter(this.ink, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final h = s * 0.18; // bar height
    final gap = s * 0.11;
    final top = (s - (3 * h + 2 * gap)) / 2;
    final r = Radius.circular(h / 2);
    final widths = [0.86, 0.62, 0.38];
    for (var i = 0; i < 3; i++) {
      final rect = RRect.fromLTRBR(s * 0.07, top + i * (h + gap), s * (0.07 + widths[i]), top + i * (h + gap) + h, r);
      canvas.drawRRect(rect, Paint()..color = i == 1 ? accent : ink);
    }
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.ink != ink || old.accent != accent;
}
