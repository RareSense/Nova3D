import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/shared/widgets/grid_background.dart';
import 'package:nova3d_frontend/shared/widgets/nova_logo.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).forgotPassword(email);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: GridBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NovaLogo(),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: kChunkyCard(shadow: true),
                    child: _sent
                        ? _SuccessContent()
                        : _FormContent(
                            emailCtrl: _emailCtrl,
                            error: _error,
                            loading: _loading,
                            onSubmit: _submit,
                            onBack: () => context.go('/signin'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormContent extends StatelessWidget {
  const _FormContent({
    required this.emailCtrl,
    required this.error,
    required this.loading,
    required this.onSubmit,
    required this.onBack,
  });
  final TextEditingController emailCtrl;
  final String? error;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Enter your email and we'll send you a reset link.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kErrorRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kErrorRed.withValues(alpha: 0.3)),
              ),
              child: Text(error!,
                  style: const TextStyle(color: kErrorRed, fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: kTextPrimary),
            decoration: const InputDecoration(hintText: 'Email'),
            onFieldSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kInk),
                  )
                : const Text('Send Reset Link'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: kTextSecondary),
            child: const Text('Back to sign in'),
          ),
        ],
      );
}

class _SuccessContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Icon(Icons.mark_email_read_outlined,
              color: kSuccessGreen, size: 48),
          const SizedBox(height: 16),
          Text('Check your inbox',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "We've sent a password reset link to your email.",
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/signin'),
            child: const Text('Back to Sign In'),
          ),
        ],
      );
}
