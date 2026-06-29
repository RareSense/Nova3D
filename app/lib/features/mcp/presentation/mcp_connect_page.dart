import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_completion_copy.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_shared.dart';
import 'package:web/web.dart' as web;

class McpConnectPage extends ConsumerStatefulWidget {
  const McpConnectPage({super.key});

  @override
  ConsumerState<McpConnectPage> createState() => _McpConnectPageState();
}

class _McpConnectPageState extends ConsumerState<McpConnectPage> {
  bool _startingGoogle = false;
  String? _error;
  bool _autoProgressed = false;

  Future<void> _startGoogleSignIn() async {
    final contextData = McpBrowserContext.readOrCapture(Uri.base);
    if (contextData != null) McpBrowserContext.persist(contextData);

    setState(() {
      _startingGoogle = true;
      _error = null;
    });
    try {
      final url = await ref
          .read(authServiceProvider)
          .getGoogleAuthorizationUrl();
      web.window.location.href = url;
    } catch (_) {
      if (mounted) {
        setState(() {
          _startingGoogle = false;
          _error = 'Failed to start Nova3D sign-in.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final contextData = McpBrowserContext.readOrCapture(Uri.base);
    final user = auth.valueOrNull;

    if (!_autoProgressed && !auth.isLoading && user != null) {
      _autoProgressed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/mcp/complete');
      });
    }

    final clientName = contextData?.clientName;
    final missingContext = contextData == null || !contextData.isValid;

    return McpScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McpHeader(
            badge: 'mcp setup',
            title: 'Connect Nova3D',
            subtitle: McpCompletionCopy.connectSubtitle(clientName),
          ),
          const SizedBox(height: 24),
          McpInfoPanel(
            children: [
              McpStatusRow(
                label: 'Step 1',
                value: 'Sign in to your Nova3D account',
              ),
              McpStatusRow(
                label: 'Step 2',
                value: 'Finish the local handoff on this device',
              ),
              const McpStatusRow(
                label: 'Step 3',
                value: 'Buy credits only if your account is currently unfunded',
              ),
            ],
          ),
          const SizedBox(height: 18),
          McpMessageBanner(
            message:
                '${McpCompletionCopy.handoffExpectationMessage(clientName)} ${McpCompletionCopy.handoffReturnMessage(clientName)}',
          ),
          if (missingContext) ...[
            const SizedBox(height: 18),
            McpMessageBanner(
              message: McpCompletionCopy.missingContextMessage(clientName),
              isError: true,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            McpMessageBanner(message: _error!, isError: true),
          ],
          const SizedBox(height: 24),
          McpPrimaryButton(
            label: user != null ? 'Continue setup' : 'Continue with Google',
            onTap: missingContext
                ? null
                : user != null
                ? () => context.go('/mcp/complete')
                : _startGoogleSignIn,
            loading: _startingGoogle || auth.isLoading,
          ),
        ],
      ),
    );
  }
}
