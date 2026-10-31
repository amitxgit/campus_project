import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/widgets/ui_kit.dart';

/// ---------------------------------------------------------------------------
/// SPLASH PAGE
/// ---------------------------------------------------------------------------
///
/// • Navigation and auth logic is handled globally (e.g. GoRouter redirect)
/// • This widget is purely visual
///
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.slow,
          curve: Motion.curve,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 64),
              const SizedBox(height: 16),
              Text(
                'Batchwise',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
