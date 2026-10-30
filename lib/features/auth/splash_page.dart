import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/settings_repository.dart';

/// ---------------------------------------------------------------------------
/// SPLASH PAGE
/// ---------------------------------------------------------------------------
///
/// • Navigation and auth logic is handled globally (e.g. GoRouter redirect)
/// • This widget is purely visual
///
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = theme.scaffoldBackgroundColor;
    final cardColor = isDark
        ? theme.cardTheme.color ?? theme.colorScheme.surface
        : theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.school,
                size: 56,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              const Text(
                'CAMPUS TRACK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Attendance & Timetable',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Loading ${ref.watch(settingsProvider).name}...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
