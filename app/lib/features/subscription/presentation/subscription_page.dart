import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/startup_url_bootstrap.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/subscription/models/billing_models.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  String? _verifiedSessionId;
  late final String? _returnSessionId;

  @override
  void initState() {
    super.initState();
    _returnSessionId = StartupUrlBootstrap.takeCheckoutSessionId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(billingProvider.notifier).load();
      _verifyReturnSession();
    });
  }

  void _verifyReturnSession() {
    final sessionId = _returnSessionId;
    if (sessionId == null ||
        sessionId.trim().isEmpty ||
        sessionId == _verifiedSessionId) {
      return;
    }
    _verifiedSessionId = sessionId;
    ref.read(billingProvider.notifier).verifyCheckout(sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(billingProvider);
    final user = ref.watch(authProvider).valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            children: [
              const NovaCube(size: 72),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: kMintBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kInk, width: 1.5),
                ),
                child: Text('credits', style: kSilkscreen(10, color: kInk)),
              ),
              const SizedBox(height: 16),
              Text('Nova3D Credits', style: kVt323(54)),
              const SizedBox(height: 8),
              Text(
                'Buy credits for Nova3D generation and editing.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _BillingMessage(state: billing),
              _WalletSummary(
                wallet: billing.wallet,
                email: user?.email ?? '',
                loading: billing.refreshingWallet || billing.verifyingCheckout,
              ),
              const SizedBox(height: 24),
              _TierContent(state: billing),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingMessage extends ConsumerWidget {
  const _BillingMessage({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = state.error;
    final notice = state.notice;
    if (error == null && notice == null) return const SizedBox.shrink();
    final isError = error != null;
    final message = error ?? notice!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? kPinkBg : kMintBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isError ? kErrorRed : kMint, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: kInk,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: kInk, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => isError
                  ? ref.read(billingProvider.notifier).clearError()
                  : ref.read(billingProvider.notifier).clearNotice(),
              child: const Icon(Icons.close, size: 18, color: kInkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSummary extends ConsumerWidget {
  const _WalletSummary({
    required this.wallet,
    required this.email,
    required this.loading,
  });

  final BillingWallet? wallet;
  final String email;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = wallet?.available ?? 0;
    final accountLabel = email.trim().isNotEmpty
        ? email.trim()
        : 'Signed-in account';
    final creditsLabel = wallet == null ? '--' : '$available';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: kChunkyCard(bg: kMintBg, radius: 8, shadow: false),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 420,
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, color: kInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Credits are attached to this signed-in account.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kInk, width: 1.3),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Available credits',
                      style: const TextStyle(color: kInkSoft, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(creditsLabel, style: kSilkscreen(18, color: kInk)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 42,
                height: 42,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kInk,
                        ),
                      )
                    : IconButton(
                        tooltip: 'Refresh credits',
                        onPressed: () =>
                            ref.read(billingProvider.notifier).refreshWallet(),
                        icon: const Icon(Icons.refresh, color: kInk),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierContent extends ConsumerWidget {
  const _TierContent({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.tiers.isEmpty) {
      return const SizedBox(height: 8);
    }

    if (state.tiers.isEmpty) {
      return _EmptyTiers(
        onRetry: () => ref.read(billingProvider.notifier).load(force: true),
      );
    }

    return _TierGrid(tiers: state.tiers, checkoutTierId: state.checkoutTierId);
  }
}

class _EmptyTiers extends StatelessWidget {
  const _EmptyTiers({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: kChunkyCard(radius: 8),
      child: Column(
        children: [
          Text('No credit packages are available.', style: kVt323(28)),
          const SizedBox(height: 12),
          SizedBox(
            width: 180,
            child: _CheckoutButton(
              label: 'Refresh',
              loading: false,
              onTap: onRetry,
              color: kMintBg,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierGrid extends StatelessWidget {
  const _TierGrid({required this.tiers, required this.checkoutTierId});

  final List<BillingTier> tiers;
  final String? checkoutTierId;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    if (isMobile) {
      return Column(
        children: [
          for (final tier in tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _TierCard(tier: tier, checkoutTierId: checkoutTierId),
            ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tier in tiers)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _TierCard(tier: tier, checkoutTierId: checkoutTierId),
              ),
            ),
        ],
      ),
    );
  }
}

class _TierCard extends StatefulWidget {
  const _TierCard({required this.tier, required this.checkoutTierId});

  final BillingTier tier;
  final String? checkoutTierId;

  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;
    final accent = _accentForTier(tier);
    final disabled = widget.checkoutTierId != null;
    final loading = widget.checkoutTierId == tier.tierId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: _pressed
          ? Matrix4.translationValues(2, 2, 0)
          : Matrix4.identity(),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _pressed ? Colors.transparent : kInk,
            offset: _pressed ? Offset.zero : const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (tier.isPopular) _PopularBadge(color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(tier.displayPrice, style: kVt323(44, color: accent)),
              const SizedBox(height: 4),
              Text(
                tier.title,
                style: const TextStyle(
                  color: kInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tier.purchaseModeLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Divider(color: kInk.withValues(alpha: 0.15), thickness: 1),
              const SizedBox(height: 16),
              _FeatureRow(text: '${tier.credits} account credits'),
              const _FeatureRow(text: 'Text and image generation'),
              const _FeatureRow(text: 'Part edits and articulation'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: SizedBox(
              width: double.infinity,
              child: _CheckoutButton(
                label: 'Buy credits',
                loading: loading,
                onTap: disabled ? null : () => _startCheckout(context, tier),
                onPressChanged: (pressed) => setState(() => _pressed = pressed),
                color: _buttonColorForTier(tier),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCheckout(BuildContext context, BillingTier tier) async {
    final ref = ProviderScope.containerOf(context, listen: false);
    final url = await ref.read(billingProvider.notifier).createCheckout(tier);
    if (!context.mounted || url == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      ref
          .read(billingProvider.notifier)
          .setError('Billing returned an invalid checkout URL.');
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    );
    if (!launched) {
      ref
          .read(billingProvider.notifier)
          .setError('Could not open Stripe checkout.');
    }
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        'Popular',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check, size: 14, color: kSuccessGreen),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: kInkSoft,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutButton extends StatefulWidget {
  const _CheckoutButton({
    required this.label,
    required this.loading,
    required this.onTap,
    required this.color,
    this.onPressChanged,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final Color color;
  final ValueChanged<bool>? onPressChanged;

  @override
  State<_CheckoutButton> createState() => _CheckoutButtonState();
}

class _CheckoutButtonState extends State<_CheckoutButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null || widget.loading;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: disabled ? null : () => _setPressed(false),
      onTap: disabled ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed
            ? Matrix4.translationValues(2, 2, 0)
            : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: disabled ? kLineSoft : widget.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: disabled ? kInkMuted : kInk, width: 1.5),
          boxShadow: disabled || _pressed
              ? []
              : const [
                  BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
                ],
        ),
        child: Center(
          child: widget.loading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                )
              : Text(
                  widget.label,
                  style: kSilkscreen(9, color: disabled ? kInkMuted : kInk),
                ),
        ),
      ),
    );
  }

  void _setPressed(bool pressed) {
    setState(() => _pressed = pressed);
    widget.onPressChanged?.call(pressed);
  }
}

Color _accentForTier(BillingTier tier) {
  if (tier.credits >= 1500) return kMint;
  if (tier.credits >= 500) return kLilac;
  return kInk;
}

Color _buttonColorForTier(BillingTier tier) {
  if (tier.credits >= 1500) return kMintBg;
  if (tier.credits >= 500) return kPinkBg;
  return kLilacBg;
}
