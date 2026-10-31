// lib/features/profile/update_profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/firebase_error_parser.dart';
import '../../main.dart';
import '../common/widgets/ui_kit.dart';
import '../common/widgets/async_error_widget.dart';

final contactDetailsProvider = FutureProvider.autoDispose<({String bio, String phone})>((ref) async {
  final user = await ref.watch(authRepoProvider).currentUser();
  if (user == null) throw Exception('User not logged in');
  return ref.watch(authRepoProvider).contactDetails(user.id);
});

class UpdateProfilePage extends ConsumerStatefulWidget {
  const UpdateProfilePage({super.key});

  @override
  ConsumerState<UpdateProfilePage> createState() => _UpdateProfilePageState();
}

class _UpdateProfilePageState extends ConsumerState<UpdateProfilePage> {
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isLoading = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(contactDetailsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit details')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorWidget(message: FirebaseErrorParser.getMessage(err), onRetry: () => ref.invalidate(contactDetailsProvider)),
        data: (profileData) {
          if (!_prefilled) {
            _prefilled = true;
            _bioCtrl.text = profileData.bio;
            _phoneCtrl.text = profileData.phone;
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _bioCtrl,
                  decoration: const InputDecoration(labelText: 'About you', alignLabelWithHint: true),
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    helperText: "For contact only. It doesn't change how you sign in.",
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : () => _updateProfile(ref),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateProfile(WidgetRef ref) async {
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(authRepoProvider).currentUser();
      if (user == null) throw Exception('User not logged in');
      await ref.read(authRepoProvider).updateContactDetails(
        user.id,
        bio: _bioCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (mounted) {
        showMessage(context, 'Saved.', success: true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, FirebaseErrorParser.getMessage(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}