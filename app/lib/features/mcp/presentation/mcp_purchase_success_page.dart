import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/startup_url_bootstrap.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_shared.dart';
import 'package:nova3d_frontend/features/mcp/state/mcp_provider.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';

class McpPurchaseSuccessPage extends ConsumerStatefulWidget {
  const McpPurchaseSuccessPage({super.key});

  @override
  ConsumerState<McpPurchaseSuccessPage> createState() =>
      _McpPurchaseSuccessPageState();
}

class _McpPurchaseSuccessPageState
    extends ConsumerState<McpPurchaseSuccessPage> {
  String? _verifiedSessionId;
  late final String? _checkoutSessionId;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkoutSessionId = StartupUrlBootstrap.takeCheckoutSessionId();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final sessionId = _checkoutSessionId;
    if (sessionId != null &&
        sessionId.trim().isNotEmpty &&
        sessionId != _verifiedSessionId) {
      _verifiedSessionId = sessionId;
      await ref.read(billingProvider.notifier).verifyCheckout(sessionId);
    }
    await ref.read(mcpProvider.notifier).refreshStatus();
    await ref.read(billingProvider.notifier).refreshWallet();
    _syncPolling();
  }

  void _syncPolling() {
    final ready = _isReady();
    _pollTimer?.cancel();
    if (ready) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      await ref.read(mcpProvider.notifier).refreshStatus();
      await ref.read(billingProvider.notifier).refreshWallet();
      if (!mounted) return;
      if (_isReady()) {
        _pollTimer?.cancel();
      }
    });
  }

  bool _isReady() {
    final mcp = ref.read(mcpProvider);
    final billing = ref.read(billingProvider);
    final available =
        mcp.status?.credits?.available ?? billing.wallet?.available ?? 0;
    return mcp.status?.generationReady == true || available > 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mcp = ref.watch(mcpProvider);
    final billing = ref.watch(billingProvider);
    final available =
        mcp.status?.credits?.available ?? billing.wallet?.available;
    final clientName = McpBrowserContext.read()?.clientName ?? 'your editor';
    final ready = mcp.status?.generationReady == true || (available ?? 0) > 0;

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'purchase complete',
            title: ready ? 'Nova3D funding confirmed' : 'Refreshing credits',
            subtitle: ready
                ? 'Your Nova3D account has credits again. Return to $clientName to finish the MCP setup handoff.'
                : 'Stripe confirmed the payment. Nova3D is refreshing your account balance now.',
          ),
          const SizedBox(height: 24),
          McpInfoPanel(
            children: [
              McpStatusRow(
                label: 'Account',
                value: mcp.status?.identity?.email.isNotEmpty == true
                    ? mcp.status!.identity!.email
                    : (auth.valueOrNull?.email.isNotEmpty == true
                          ? auth.valueOrNull!.email
                          : 'Signed-in Nova3D account'),
              ),
              McpStatusRow(
                label: 'Available credits',
                value: available == null ? 'Refreshing...' : '$available',
              ),
              McpStatusRow(
                label: 'Next step',
                value: ready
                    ? 'Return to your editor and continue setup.'
                    : 'Keep this tab open or check again in a moment.',
              ),
            ],
          ),
          if (mcp.error != null || billing.error != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message: mcp.error ?? billing.error!,
              isError: true,
            ),
          ] else if (billing.notice != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(message: billing.notice!),
          ],
          const SizedBox(height: 24),
          McpPrimaryButton(
            label: ready ? 'Continue setup in browser' : 'Check again',
            onTap: ready ? () => context.go('/mcp/complete') : _bootstrap,
            loading: billing.verifyingCheckout || mcp.loadingStatus,
          ),
          const SizedBox(height: 12),
          McpSecondaryButton(
            label: ready ? 'Close tab and return to editor' : 'Back to credits',
            onTap: ready ? null : () => context.go('/mcp/no-credits'),
          ),
        ],
      ),
    );
  }
}
