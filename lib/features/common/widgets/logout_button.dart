// lib/features/common/widgets/logout_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';

class LogoutButton extends ConsumerWidget {
  final bool confirm;
  final Color? color;

  const LogoutButton({
    super.key,
    this.confirm = true,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Logout',
      icon: Icon(
        Icons.logout,
        // Use provided color, or default to error color (red)
        color: color ?? Theme.of(context).colorScheme.error,
      ),
      onPressed: () async {
        bool shouldLogout = true;

        if (confirm) {
          shouldLogout = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign out?'),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Logout'),
                ),
              ],
            ),
          ) ??
              false;
        }

        if (!shouldLogout) return;

        try {
          // Logout triggers auth state change handler globally,
          // which performs navigation, session clearing, and notification sync stop.
          await ref.read(authRepoProvider).logout();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error logging out')),
            );
          }
        }
      },
    );
  }
}
