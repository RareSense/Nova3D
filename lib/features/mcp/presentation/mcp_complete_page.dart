import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_completion_copy.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_completion_flow.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_shared.dart';
import 'package:nova3d_frontend/features/mcp/state/mcp_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class McpCompletePage extends ConsumerStatefulWidget {
  const McpCompletePage({super.key});

  @override
  ConsumerState<McpCompletePage> createState() => _McpCompletePageState();
}

class _McpCompletePageState extends ConsumerState<McpCompletePage> {
  bool _initialized = false;
  bool _preparingLoopback = false;
  bool _routeToCreditsAfterHandoff = false;
  String? _handoffUrl;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = ref.read(authProvider);
    if (auth.valueOrNull == null) {
      if (mounted) context.go('/mcp/connect');
      return;
    }

    final status = await ref.read(mcpProvider.notifier).refreshStatus();
    if (!mounted || status == null) return;

    final contextData = McpBrowserContext.readOrCapture(Uri.base);
    switch (McpCompletionFlow.bootstrapAction(
      status: status,
      hasValidContext: contextData?.isValid == true,
    )) {
      case McpBootstrapAction.goToConnect:
        context.go('/mcp/connect');
        return;
      case McpBootstrapAction.goToNoCredits:
        context.go('/mcp/no-credits');
        return;
      case McpBootstrapAction.idle:
        return;
      case McpBootstrapAction.prepareHandoff:
        break;
    }
    if (contextData == null || !contextData.isValid) return;

    setState(() => _preparingLoopback = true);
    final sessionCode = await ref
        .read(mcpProvider.notifier)
        .createSessionCode();
    if (!mounted) return;
    setState(() {
      _preparingLoopback = false;
      _routeToCreditsAfterHandoff = status.needsPurchase;
      _handoffUrl = sessionCode == null
          ? null
          : contextData.loopbackUrlForCode(sessionCode);
    });
    if (_handoffUrl != null) {
      await _openLoopback(showFailureFeedback: false);
    }
    _startPolling();
  }

  Future<void> _openLoopback({bool showFailureFeedback = true}) async {
    final handoffUrl = _handoffUrl;
    if (handoffUrl == null) return;
    final uri = Uri.tryParse(handoffUrl);
    if (uri == null) return;
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted && showFailureFeedback) {
      ref.read(mcpProvider.notifier).clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reach the local MCP callback.'),
        ),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final status = await ref.read(mcpProvider.notifier).refreshStatus();
      if (!mounted || status == null) return;
      switch (McpCompletionFlow.pollAction(
        status: status,
        routeToCreditsAfterHandoff: _routeToCreditsAfterHandoff,
      )) {
        case McpPollAction.goToConnect:
          _pollTimer?.cancel();
          context.go('/mcp/connect');
          return;
        case McpPollAction.goToNoCredits:
          _pollTimer?.cancel();
          context.go('/mcp/no-credits');
          return;
        case McpPollAction.stopPolling:
          _pollTimer?.cancel();
          return;
        case McpPollAction.continuePolling:
          return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mcp = ref.watch(mcpProvider);
    final status = mcp.status;
    final contextData = McpBrowserContext.read();
    final clientName = contextData?.clientName;
    final identity =
        status?.identity ?? _identityFromAuth(auth.valueOrNull?.email);
    final canContinue = _handoffUrl != null && !_preparingLoopback;
    final showBlockingSpinner = McpCompletionCopy.showBlockingSpinner(
      loadingStatus: mcp.loadingStatus,
      preparingLoopback: _preparingLoopback,
      hasHandoffUrl: _handoffUrl != null,
    );

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'mcp setup',
            title: status?.generationReady == true
                ? 'Nova3D is ready'
                : 'Finish local MCP connection',
            subtitle:
                'Your Nova3D browser sign-in is complete. Continue the local MCP handoff so your session can be established without copying a token.',
          ),
          const SizedBox(height: 24),
          McpInfoPanel(
            children: [
              McpStatusRow(
                label: 'Account',
                value: identity?.email.isNotEmpty == true
                    ? identity!.email
                    : 'Signed-in Nova3D account',
              ),
              McpStatusRow(
                label: 'Credits',
                value: status?.credits == null
                    ? 'Checking credits...'
                    : '${status!.credits!.available} available',
              ),
              McpStatusRow(
                label: 'MCP session',
                value: status?.mcpSession?.established == true
                    ? 'Established'
                    : status?.nextAction == 'service_unavailable'
                    ? 'Nova3D setup service unavailable'
                    : _handoffUrl != null
                    ? 'Waiting for local MCP client callback'
                    : 'Preparing one-time handoff',
              ),
              McpStatusRow(
                label: 'MCP client',
                value: McpCompletionCopy.targetName(clientName),
              ),
            ],
          ),
          const SizedBox(height: 18),
          McpMessageBanner(
            message:
                '${McpCompletionCopy.handoffExpectationMessage(clientName)} ${McpCompletionCopy.handoffReturnMessage(clientName)}',
          ),
          if (mcp.error != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(message: mcp.error!, isError: true),
          ] else if (_routeToCreditsAfterHandoff &&
              status?.mcpSession?.established != true) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message: McpCompletionCopy.handoffPendingMessage(clientName),
            ),
          ] else if (status?.generationReady == true) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message:
                  'Nova3D confirmed your account is funded and ready. Continue in ${McpCompletionCopy.targetName(clientName)} to complete the local MCP session handoff.',
            ),
          ] else if (status?.nextAction == 'service_unavailable') ...[
            const SizedBox(height: 18),
            const McpMessageBanner(
              message:
                  'Nova3D setup is temporarily unavailable. Keep this tab open and check again in a moment.',
              isError: true,
            ),
          ] else if (mcp.loadingStatus && _handoffUrl != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message: McpCompletionCopy.checkingStatusMessage(clientName),
            ),
          ],
          const SizedBox(height: 24),
          if (showBlockingSpinner)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            )
          else ...[
            McpPrimaryButton(
              label: canContinue
                  ? McpCompletionCopy.continueLabel(clientName)
                  : 'Refresh Nova3D status',
              onTap: canContinue ? () => _openLoopback() : _bootstrap,
            ),
            const SizedBox(height: 12),
            McpSecondaryButton(
              label:
                  status?.needsPurchase == true &&
                      status?.mcpSession?.established == true
                  ? 'Buy credits'
                  : 'Check status again',
              onTap:
                  status?.needsPurchase == true &&
                      status?.mcpSession?.established == true
                  ? () => context.go('/mcp/no-credits')
                  : _bootstrap,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'If the local callback does not complete immediately, keep this tab open and retry the handoff from your MCP setup surface.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  McpIdentity? _identityFromAuth(String? email) {
    final trimmed = (email ?? '').trim();
    if (trimmed.isEmpty) return null;
    return McpIdentity(userId: '', email: trimmed, tenantId: '');
  }
}
