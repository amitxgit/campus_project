// lib/features/common/widgets/animated_theme_switcher.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for Haptic Feedback
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../theme.dart';

class AnimatedThemeSwitcher extends ConsumerWidget {
  const AnimatedThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the themeProvider so widget rebuilds on theme change
    ref.watch(themeProvider);

    // Determine actual brightness from ThemeData to respect system mode
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final notifier = ref.read(themeProvider.notifier);

    final p = context.palette;
    final bgColor = p.surface;
    final borderColor = p.line;
    final iconColor = p.ink;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          // Premium micro-interaction: Subtle vibration on tap
          HapticFeedback.lightImpact();

          if (isDark) {
            notifier.setTheme(ThemeMode.light);
          } else {
            notifier.setTheme(ThemeMode.dark);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Animated Icon
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.elasticOut, // Gives a satisfying "pop"
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return RotationTransition(
                    turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    ),
                  );
                },
                child: isDark
                    ? Icon(Icons.dark_mode_outlined, key: const ValueKey('moon'), color: iconColor, size: 18)
                    : Icon(Icons.light_mode_outlined, key: const ValueKey('sun'), color: iconColor, size: 18),
              ),
              const SizedBox(width: 8),

              // 2. Animated Text Label
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                          begin: const Offset(0.0, 0.2),
                          end: Offset.zero
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  isDark ? 'Dark' : 'Light',
                  key: ValueKey(isDark ? 'dark_text' : 'light_text'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: iconColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}