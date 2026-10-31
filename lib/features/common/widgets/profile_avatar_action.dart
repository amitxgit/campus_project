import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart';

class ProfileAvatarAction extends ConsumerWidget {
  const ProfileAvatarAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      // -----------------------------------------------------------------------
      // DATA
      // -----------------------------------------------------------------------
      data: (user) {
        // Not logged in → show login icon
        if (user == null) {
          return IconButton(
            icon: const Icon(Icons.login),
            tooltip: 'Login',
            onPressed: () => context.go('/login'),
          );
        }

        // Logged in → show avatar
        final String initial = user.name.trim().isNotEmpty
            ? user.name.trim()[0].toUpperCase()
            : '?';

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(50),
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },

      // -----------------------------------------------------------------------
      // LOADING
      // -----------------------------------------------------------------------
      loading: () => const Padding(
        padding: EdgeInsets.only(right: 16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),

      // -----------------------------------------------------------------------
      // ERROR
      // -----------------------------------------------------------------------
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
