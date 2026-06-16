import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_shared.dart';
import 'package:nova3d_frontend/features/mcp/state/mcp_provider.dart';
import 'package:nova3d_frontend/features/subscription/models/billing_models.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class McpNoCreditsPage extends ConsumerStatefulWidget {
  const McpNoCreditsPage({super.key});

  @override
  ConsumerState<McpNoCreditsPage> createState() => _McpNoCreditsPageState();
}

class _McpNoCreditsPageState extends ConsumerState<McpNoCreditsPage> {
  String? _selectedTierId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(mcpProvider.notifier).refreshStatus();
      await ref.read(billingProvider.notifier).load();
      await ref.read(billingProvider.notifier).refreshWallet();
    });
  }

  Future<void> _startCheckout(BillingTier tier) async {
    final url = await ref
        .read(billingProvider.notifier)
        .createCheckout(tier, source: BillingCheckoutSource.mcp);
    if (!mounted || url == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
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
    if (!launched && mounted) {
      ref
          .read(billingProvider.notifier)
          .setError('Could not open Stripe checkout.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mcp = ref.watch(mcpProvider);
    final billing = ref.watch(billingProvider);
    final tiers = billing.tiers;
    final selectedTier =
        tiers.where((tier) => tier.tierId == _selectedTierId).firstOrNull ??
        _defaultTier(tiers);
    final email = mcp.status?.identity?.email.isNotEmpty == true
        ? mcp.status!.identity!.email
        : (auth.valueOrNull?.email.isNotEmpty == true
              ? auth.valueOrNull!.email
              : 'Signed-in Nova3D account');
    final available =
        mcp.status?.credits?.available ?? billing.wallet?.available ?? 0;
    final clientName =
        (McpBrowserContext.read()?.clientName ?? 'your MCP client').trim();

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'credits required',
            title: 'You\'re connected. Add credits to start generating.',
            subtitle:
                'Choose a credit pack for this account, then return to $clientName to unlock generation.',
          ),
          const SizedBox(height: 24),
          McpInfoPanel(
            tint: const Color(0xFFFFF2E6),
            children: [
              McpStatusRow(label: 'Account', value: email),
              McpStatusRow(label: 'Available credits', value: '$available'),
              const McpStatusRow(
                label: 'Wallet model',
                value: 'Web and MCP use the same Nova3D credit balance.',
              ),
            ],
          ),
          if (mcp.error != null || billing.error != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message: mcp.error ?? billing.error!,
              isError: true,
            ),
          ],
          const SizedBox(height: 18),
          const McpMessageBanner(
            message:
                'Pick a credit pack for this account. If you\'re trying Nova3D for the first time, the starter pack is the easiest way to begin.',
          ),
          const SizedBox(height: 24),
          if (tiers.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                if (wide) {
                  return Row(
                    children: [
                      for (var i = 0; i < tiers.length; i++) ...[
                        Expanded(
                          child: _CreditPackCard(
                            tier: tiers[i],
                            selected: selectedTier?.tierId == tiers[i].tierId,
                            loading: billing.checkoutTierId == tiers[i].tierId,
                            badge: _badgeForTier(tiers[i]),
                            onTap: () => setState(
                              () => _selectedTierId = tiers[i].tierId,
                            ),
                          ),
                        ),
                        if (i != tiers.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < tiers.length; i++) ...[
                      _CreditPackCard(
                        tier: tiers[i],
                        selected: selectedTier?.tierId == tiers[i].tierId,
                        loading: billing.checkoutTierId == tiers[i].tierId,
                        badge: _badgeForTier(tiers[i]),
                        onTap: () =>
                            setState(() => _selectedTierId = tiers[i].tierId),
                      ),
                      if (i != tiers.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          McpPrimaryButton(
            label: selectedTier == null
                ? 'Refresh credit packages'
                : 'Buy ${selectedTier.credits} credits for ${selectedTier.displayPrice}',
            onTap: billing.checkoutTierId != null
                ? null
                : selectedTier == null
                ? () => ref.read(billingProvider.notifier).load(force: true)
                : () => _startCheckout(selectedTier),
            loading:
                selectedTier != null &&
                billing.checkoutTierId == selectedTier.tierId,
          ),
          const SizedBox(height: 12),
          McpSecondaryButton(
            label: 'I already purchased, check again',
            onTap: () async {
              await ref.read(mcpProvider.notifier).refreshStatus();
              await ref.read(billingProvider.notifier).refreshWallet();
              if (!context.mounted) return;
              final updated = ref.read(mcpProvider).status;
              if (updated?.needsPurchase == false &&
                  (updated?.generationReady == true ||
                      (updated?.credits?.available ?? 0) > 0)) {
                context.go('/mcp/complete');
              }
            },
          ),
        ],
      ),
    );
  }

  BillingTier? _defaultTier(List<BillingTier> tiers) {
    if (tiers.isEmpty) return null;
    return tiers.firstWhere(
      (tier) => tier.credits == 100,
      orElse: () => tiers.first,
    );
  }

  String? _badgeForTier(BillingTier tier) {
    if (tier.credits == 100) return 'Starter';
    if (tier.credits == 500) return 'Most Popular';
    if (tier.credits == 1500) return 'Best Value';
    return null;
  }
}

class _CreditPackCard extends StatelessWidget {
  const _CreditPackCard({
    required this.tier,
    required this.selected,
    required this.loading,
    required this.onTap,
    this.badge,
  });

  final BillingTier tier;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: kChunkyCard(
            bg: selected ? kButterBg : kSurface,
            radius: 12,
            shadow: selected,
            borderColor: selected ? kInk : kLineSoft,
            shadowColor: selected ? kButter : kInk,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? kPinkBg : kMintBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kInk, width: 1.1),
                  ),
                  child: Text(badge!, style: kSilkscreen(9, color: kInk)),
                ),
                const SizedBox(height: 12),
              ],
              Text(tier.title, style: kVt323(30)),
              const SizedBox(height: 4),
              Text(
                tier.displayPrice,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: kInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _descriptionForTier(tier),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: kInkSoft, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: selected ? kInk : kInkMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    selected ? 'Selected' : 'Select this pack',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? kInk : kInkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionForTier(BillingTier tier) {
    return switch (tier.credits) {
      100 => 'Low-commitment starter pack for first-time experiments.',
      500 => 'Balanced option for most workflows and repeat generations.',
      1500 => 'Best value if you already know you\'ll use Nova3D heavily.',
      _ => tier.purchaseModeLabel,
    };
  }
}
