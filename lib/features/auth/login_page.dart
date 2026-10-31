// lib/features/auth/login_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/settings_repository.dart';
import '../../main.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../core/utils/phone.dart';
import '../../theme.dart';
import '../common/widgets/ui_kit.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Hide keyboard
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      await ref.read(authRepoProvider).loginWithEmail(
        _emailCtrl.text.trim(),
        _passCtrl.text.trim(),
      );
      // GoRouter in main.dart will handle the redirect based on auth state
    } catch (e) {
      if (!mounted) return;

      final msg = FirebaseErrorParser.getMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: context.palette.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotDialog() async {
    final resetEmailCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your email address to receive a password reset link.'),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final email = resetEmailCtrl.text.trim();
                if (!email.contains('@') && PhoneNumber.normalize(email) != null) {
                  // Mobile-number logins have no inbox to send a reset link to.
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('You sign in with your mobile number. Please ask your institute to reset your password.')),
                  );
                  return;
                }
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email.')),
                  );
                  return;
                }

                try {
                  await ref.read(authRepoProvider).requestPasswordReset(email);
                  if (ctx.mounted) Navigator.pop(ctx); // Close dialog
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reset link sent! Check your email.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(FirebaseErrorParser.getMessage(e)),
                      backgroundColor: context.palette.danger,
                    ));
                  }
                }
              },
              child: const Text('Send link'),
            ),
          ],
        );
      },
    );

    resetEmailCtrl.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final instituteName = ref.watch(settingsProvider).name;

    final children = <Widget>[
      Row(
        children: [
          const BrandMark(size: 32),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              instituteName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: p.ink),
            ),
          ),
        ],
      ),
      const SizedBox(height: 56),
      Text('Sign in', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 32),
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email, AutofillHints.telephoneNumber],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Email or mobile number',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Enter your email or mobile number';
          if (!v.contains('@') && PhoneNumber.normalize(v) == null) {
            return 'Enter a valid email or 10-digit mobile number';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _passCtrl,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onFieldSubmitted: (_) => _onLogin(),
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            icon: AnimatedSwitcher(
              duration: Motion.fast,
              child: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                key: ValueKey(_obscurePassword),
              ),
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters required' : null,
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _showForgotDialog,
          child: const Text('Forgot password?'),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: _isLoading ? null : _onLogin,
          child: AnimatedSwitcher(
            duration: Motion.fast,
            child: _isLoading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: p.inkMuted),
                  )
                : const Text('Sign in', key: ValueKey('label')),
          ),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, child: children[i]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
