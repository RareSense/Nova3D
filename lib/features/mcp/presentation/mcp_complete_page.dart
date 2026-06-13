import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';
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

    if (!status.authenticated ||
        status.nextAction == 'sign_in' ||
        status.nextAction == 'session_expired') {
      context.go('/mcp/connect');
      return;
    }
    if (status.needsPurchase) {
      context.go('/mcp/no-credits');
      return;
    }

    final contextData = McpBrowserContext.readOrCapture(Uri.base);
    if (contextData == null || !contextData.isValid) return;

    setState(() => _preparingLoopback = true);
    final sessionCode = await ref
        .read(mcpProvider.notifier)
        .createSessionCode();
    if (!mounted) return;
    setState(() {
      _preparingLoopback = false;
      _handoffUrl = sessionCode == null
          ? null
          : contextData.loopbackUrlForCode(sessionCode);
    });
    _startPolling();
  }

  Future<void> _openLoopback() async {
    final handoffUrl = _handoffUrl;
    if (handoffUrl == null) return;
    final uri = Uri.tryParse(handoffUrl);
    if (uri == null) return;
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
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
      if (status.needsPurchase) {
        _pollTimer?.cancel();
        context.go('/mcp/no-credits');
        return;
      }
      if (!status.authenticated ||
          status.nextAction == 'sign_in' ||
          status.nextAction == 'session_expired') {
        _pollTimer?.cancel();
        context.go('/mcp/connect');
        return;
      }
      if (status.mcpSession?.established == true || status.generationReady) {
        _pollTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mcp = ref.watch(mcpProvider);
    final status = mcp.status;
    final contextData = McpBrowserContext.read();
    final identity =
        status?.identity ?? _identityFromAuth(auth.valueOrNull?.email);
    final canContinue =
        _handoffUrl != null && !mcp.loadingStatus && !_preparingLoopback;

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'mcp setup',
            title: status?.generationReady == true
                ? 'Nova3D is ready'
                : 'Finish editor connection',
            subtitle:
                'Your Nova3D browser sign-in is complete. Continue the local editor handoff so your MCP session can be established without copying a token.',
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
                    ? 'Waiting for local editor callback'
                    : 'Preparing one-time handoff',
              ),
              McpStatusRow(
                label: 'Editor',
                value: contextData?.clientName ?? 'Connected local editor',
              ),
            ],
          ),
          if (mcp.error != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(message: mcp.error!, isError: true),
          ] else if (status?.generationReady == true) ...[
            const SizedBox(height: 18),
            const McpMessageBanner(
              message:
                  'Nova3D confirmed your account is funded and ready. Continue in your editor to complete the local MCP session handoff.',
            ),
          ] else if (status?.nextAction == 'service_unavailable') ...[
            const SizedBox(height: 18),
            const McpMessageBanner(
              message:
                  'Nova3D setup is temporarily unavailable. Keep this tab open and check again in a moment.',
              isError: true,
            ),
          ],
          const SizedBox(height: 24),
          if (mcp.loadingStatus || _preparingLoopback)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            )
          else ...[
            McpPrimaryButton(
              label: canContinue
                  ? 'Continue in your editor'
                  : 'Refresh Nova3D status',
              onTap: canContinue ? _openLoopback : _bootstrap,
            ),
            const SizedBox(height: 12),
            McpSecondaryButton(
              label: status?.needsPurchase == true
                  ? 'Buy credits'
                  : 'Check status again',
              onTap: status?.needsPurchase == true
                  ? () => context.go('/mcp/no-credits')
                  : _bootstrap,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'If the local editor callback does not complete immediately, keep this tab open and retry the editor handoff from your MCP setup surface.',
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
