import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final selectedTier = tiers.isEmpty
        ? null
        : tiers.firstWhere((tier) => tier.isPopular, orElse: () => tiers.first);
    final email = mcp.status?.identity?.email.isNotEmpty == true
        ? mcp.status!.identity!.email
        : (auth.valueOrNull?.email.isNotEmpty == true
              ? auth.valueOrNull!.email
              : 'Signed-in Nova3D account');
    final available =
        mcp.status?.credits?.available ?? billing.wallet?.available ?? 0;
    final clientName = McpBrowserContext.read()?.clientName ?? 'your editor';

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'credits required',
            title: 'Account connected, credits needed',
            subtitle:
                'Nova3D is linked to $clientName, but generation is not ready until this account has credits.',
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
                'Your sign-in is complete. Buy credits for this account, then return to your editor and Nova3D MCP will re-check readiness.',
          ),
          const SizedBox(height: 24),
          McpPrimaryButton(
            label: selectedTier == null
                ? 'Refresh credit packages'
                : 'Buy ${selectedTier.credits} credits',
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
}
