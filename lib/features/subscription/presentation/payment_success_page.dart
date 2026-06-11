import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';
import 'package:nova3d_frontend/shared/widgets/grid_background.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class PaymentSuccessPage extends ConsumerStatefulWidget {
  const PaymentSuccessPage({super.key});

  @override
  ConsumerState<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends ConsumerState<PaymentSuccessPage> {
  String? _verifiedSessionId;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final billing = ref.watch(billingProvider);
    final user = auth.valueOrNull;
    final sessionId = Uri.base.queryParameters['session_id'] ?? '';
    final canVerify = user != null && sessionId.isNotEmpty;

    if (canVerify && _verifiedSessionId != sessionId) {
      _verifiedSessionId = sessionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(billingProvider.notifier).verifyCheckout(sessionId);
      });
    }

    final verifying = billing.verifyingCheckout;
    final fulfilled = billing.notice != null && !verifying;
    final unauthenticated = !auth.isLoading && user == null;
    final available = billing.wallet?.available;

    return Scaffold(
      backgroundColor: kCream,
      body: GridBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: kChunkyCard(radius: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NovaCube(size: 56),
                    const SizedBox(height: 20),
                    Text(
                      _titleFor(
                        verifying: verifying,
                        fulfilled: fulfilled,
                        unauthenticated: unauthenticated,
                      ),
                      textAlign: TextAlign.center,
                      style: kVt323(44),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _messageFor(
                        verifying: verifying,
                        fulfilled: fulfilled,
                        unauthenticated: unauthenticated,
                        available: available,
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 24),
                    if (verifying || auth.isLoading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: kInk,
                          strokeWidth: 2.4,
                        ),
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ActionButton(
                            label: user == null ? 'Sign in' : 'Credits',
                            onTap: () => context.go(
                              user == null ? '/signin' : '/subscription',
                            ),
                          ),
                          _ActionButton(
                            label: 'Home',
                            quiet: true,
                            onTap: () => context.go('/'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleFor({
    required bool verifying,
    required bool fulfilled,
    required bool unauthenticated,
  }) {
    if (verifying) return 'Adding credits';
    if (fulfilled) return 'Credits added';
    if (unauthenticated) return 'Payment received';
    return 'Payment confirmed';
  }

  String _messageFor({
    required bool verifying,
    required bool fulfilled,
    required bool unauthenticated,
    required int? available,
  }) {
    if (verifying) {
      return 'Stripe confirmed the payment. Nova3D is updating your credit balance now.';
    }
    if (fulfilled && available != null) {
      return 'Your account now has $available available credits.';
    }
    if (unauthenticated) {
      return 'Your payment is confirmed. Credits are applied to the signed-in account by the billing webhook, even if this browser is not signed in here.';
    }
    return 'Your payment is confirmed. Refresh credits if the updated balance is not visible yet.';
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool quiet;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: _pressed
            ? Matrix4.translationValues(2, 2, 0)
            : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: widget.quiet ? kSurface : kPink,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: _pressed
              ? []
              : const [
                  BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
                ],
        ),
        child: Text(widget.label, style: kSilkscreen(10, color: kInk)),
      ),
    );
  }
}
