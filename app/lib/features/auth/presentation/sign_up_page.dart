import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/shared/widgets/grid_background.dart';
import 'package:nova3d_frontend/shared/widgets/nova_logo.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).signUp(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created — check your email to verify.'),
            backgroundColor: kSuccessGreen,
          ),
        );
        context.go('/signin');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignUp() async {
    try {
      final url = await ref
          .read(authServiceProvider)
          .getGoogleAuthorizationUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    } catch (_) {
      setState(() => _error = 'Failed to start Google sign-up');
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
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NovaLogo(size: 32),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: kChunkyCard(shadow: true),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Heading
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: kVt323(44, color: kInk),
                              children: [
                                const TextSpan(text: 'create account'),
                                TextSpan(
                                  text: '!',
                                  style: TextStyle(color: kPink),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Google button
                          _ChunkyOutlinedButton(
                            onTap: _googleSignUp,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('G',
                                    style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF4285F4))),
                                const SizedBox(width: 10),
                                Text('CONTINUE WITH GOOGLE',
                                    style: kSilkscreen(12, color: kInk)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Divider
                          Row(
                            children: [
                              const Expanded(
                                  child:
                                      Divider(color: kLineSoft, thickness: 1.5)),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14),
                                child: Text('OR',
                                    style: kSilkscreen(10,
                                        color: kInkMuted,
                                        letterSpacing: 0.8)),
                              ),
                              const Expanded(
                                  child:
                                      Divider(color: kLineSoft, thickness: 1.5)),
                            ],
                          ),
                          const SizedBox(height: 18),

                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kErrorRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kErrorRed),
                              ),
                              child: Text(_error!,
                                  style: GoogleFonts.inter(
                                      color: kErrorRed, fontSize: 13)),
                            ),
                            const SizedBox(height: 14),
                          ],

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.inter(
                                color: kInk, fontSize: 14),
                            decoration: const InputDecoration(
                                hintText: 'you@studio.io'),
                            validator: (v) =>
                                (v == null || !v.contains('@'))
                                    ? 'Enter a valid email'
                                    : null,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            style: GoogleFonts.inter(
                                color: kInk, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: kInkMuted,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 8)
                                ? 'At least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscure,
                            style: GoogleFonts.inter(
                                color: kInk, fontSize: 14),
                            decoration: const InputDecoration(
                                hintText: 'Confirm password'),
                            validator: (v) => v != _passwordCtrl.text
                                ? 'Passwords do not match'
                                : null,
                            onFieldSubmitted: (_) => _signUp(),
                          ),
                          const SizedBox(height: 20),

                          _ChunkyFilledButton(
                            onTap: _loading ? null : _signUp,
                            child: _loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kInk),
                                  )
                                : Text('CREATE ACCOUNT',
                                    style: kSilkscreen(12, color: kInk)),
                          ),
                          const SizedBox(height: 18),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Already have an account?',
                                  style: GoogleFonts.inter(
                                      fontSize: 13, color: kInkSoft)),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => context.go('/signin'),
                                child: Text('Sign in →',
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: kInk,
                                        fontWeight: FontWeight.w600,
                                        decoration:
                                            TextDecoration.underline)),
                              ),
                            ],
                          ),
                        ],
                      ),
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

// ── Shared chunky button helpers ──────────────────────────────────────────────

class _ChunkyFilledButton extends StatefulWidget {
  const _ChunkyFilledButton({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_ChunkyFilledButton> createState() => _ChunkyFilledButtonState();
}

class _ChunkyFilledButtonState extends State<_ChunkyFilledButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(
              _pressed ? 2 : 0, _pressed ? 2 : 0, 0),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: widget.onTap == null ? kLineSoft : kPink,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: (_pressed || widget.onTap == null)
                ? []
                : const [
                    BoxShadow(
                        color: kInk, offset: Offset(2, 2), blurRadius: 0)
                  ],
          ),
          child: Center(child: widget.child),
        ),
      );
}

class _ChunkyOutlinedButton extends StatefulWidget {
  const _ChunkyOutlinedButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ChunkyOutlinedButton> createState() => _ChunkyOutlinedButtonState();
}

class _ChunkyOutlinedButtonState extends State<_ChunkyOutlinedButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(
              _pressed ? 2 : 0, _pressed ? 2 : 0, 0),
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: _pressed
                ? []
                : const [
                    BoxShadow(
                        color: kInk, offset: Offset(2, 2), blurRadius: 0)
                  ],
          ),
          child: Center(child: widget.child),
        ),
      );
}
