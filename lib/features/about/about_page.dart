// lib/features/about/about_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/widgets/profile_avatar_action.dart';
import '../common/widgets/app_drawer.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const String appVersion = '1.0.0 (Enterprise Build)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text(
          'About',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: const [ProfileAvatarAction()],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // 1. HERO HEADER
            // -----------------------------------------------------------------
            Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.tertiary.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.school_rounded, size: 64, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'CampusTrack',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Version $appVersion',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20), // Padding for the overlap
                      ],
                    ),
                  ),
                ),

                // Floating Description Card
                Positioned(
                  bottom: -40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Text(
                      'A unified, enterprise-grade smart campus ecosystem. Seamlessly connecting Students, Teachers, and Administrators through real-time data.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 60),

            // -----------------------------------------------------------------
            // 2. CORE ARCHITECTURE & FEATURES
            // -----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Core Architecture',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 16),

                  const _ModernFeatureCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Secure QR Attendance',
                    subtitle: 'Time-boxed, dynamically generated QR codes by faculty ensure secure and proxy-free student attendance logging.',
                    iconColor: Colors.blue,
                  ),
                  const SizedBox(height: 12),

                  const _ModernFeatureCard(
                    icon: Icons.edit_calendar_rounded,
                    title: 'Dynamic Timetable & Overrides',
                    subtitle: 'Live master schedules built by Admins, with real-time class cancellation and rescheduling powers for Teachers. Instant push notifications sync to Student dashboards.',
                    iconColor: Colors.orange,
                  ),
                  const SizedBox(height: 12),

                  const _ModernFeatureCard(
                    icon: Icons.assessment_rounded,
                    title: 'Automated Internal Marks',
                    subtitle: 'Intelligent aggregation of attendance thresholds, assignments, and exam scores into a unified internal marks ledger.',
                    iconColor: Colors.teal,
                  ),
                  const SizedBox(height: 12),

                  const _ModernFeatureCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Role-Based Workspace Switching',
                    subtitle: 'Enterprise-grade security allowing Administrators to seamlessly toggle between Admin and Faculty workspaces without logging out.',
                    iconColor: Colors.purple,
                  ),
                  const SizedBox(height: 12),

                  const _ModernFeatureCard(
                    icon: Icons.support_agent_rounded,
                    title: 'Integrated Help Desk',
                    subtitle: 'A centralized query resolution system bridging the gap between student issues and administrative action.',
                    iconColor: Colors.red,
                  ),

                  const SizedBox(height: 40),

                  // -----------------------------------------------------------------
                  // 3. TECHNOLOGY STACK
                  // -----------------------------------------------------------------
                  Text(
                    'Technology Stack',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _TechChip(label: 'Flutter 3.x', icon: Icons.flutter_dash_rounded, color: Colors.blue.shade600),
                      _TechChip(label: 'Riverpod State', icon: Icons.waves_rounded, color: Colors.teal.shade600),
                      _TechChip(label: 'Firebase Firestore', icon: Icons.cloud_done_rounded, color: Colors.orange.shade600),
                      _TechChip(label: 'GoRouter', icon: Icons.route_rounded, color: Colors.indigo.shade500),
                      _TechChip(label: 'Material 3', icon: Icons.color_lens_rounded, color: Colors.pink.shade500),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // -----------------------------------------------------------------
                  // 4. DEVELOPMENT TEAM
                  // -----------------------------------------------------------------
                  Text(
                    'Engineered By',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo,
                            child: Icon(Icons.code_rounded, color: Colors.white),
                          ),
                          title: Text('Mohit Chauhan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text('Full Stack Flutter Engineer', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        Divider(height: 1, color: isDark ? Colors.white24 : Colors.black12),
                        const ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: Icon(Icons.architecture_rounded, color: Colors.white),
                          ),
                          title: Text('Yash Gulati', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text('Full Stack Flutter Engineer', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      '© ${DateTime.now().year} CampusTrack. All rights reserved.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODERN FEATURE CARD
// -----------------------------------------------------------------------------
class _ModernFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final MaterialColor iconColor;

  const _ModernFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? iconColor.shade900.withValues(alpha: 0.4) : iconColor.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isDark ? iconColor.shade300 : iconColor.shade700,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TECH CHIP
// -----------------------------------------------------------------------------
class _TechChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _TechChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: isDark ? color : color.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}