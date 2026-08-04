import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/startup_url_bootstrap.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:web/web.dart' as web;

class OAuthCallbackPage extends ConsumerStatefulWidget {
  const OAuthCallbackPage({super.key});

  @override
  ConsumerState<OAuthCallbackPage> createState() => _OAuthCallbackPageState();
}

class _OAuthCallbackPageState extends ConsumerState<OAuthCallbackPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCallback());
  }

  Future<void> _handleCallback() async {
    // main() captures the OAuth fragment before analytics and GoRouter start.
    // The sessionStorage read supports callbacks parked by an older app build;
    // the live hash remains a development hot-reload fallback.
    final bootstrap = StartupUrlBootstrap.takeOAuthFragment() ?? '';
    final stored = web.window.sessionStorage.getItem('_nova3d_oauth') ?? '';
    web.window.sessionStorage.removeItem('_nova3d_oauth');

    final hash = web.window.location.hash;
    final fragment = bootstrap.isNotEmpty
        ? bootstrap
        : stored.isNotEmpty
        ? stored
        : (hash.startsWith('#') ? hash.substring(1) : hash);

    final params = Uri.splitQueryString(fragment);

    final token = params['access_token'];
    final error = params['error'];

    if (error != null) {
      if (mounted) context.go('/signin?error=${Uri.encodeComponent(error)}');
      return;
    }

    if (token == null || token.isEmpty) {
      if (mounted) context.go('/signin?error=no_token');
      return;
    }

    try {
      await ref.read(authProvider.notifier).handleOAuthCallback(token);
      final mcpContext = McpBrowserContext.read();
      if (mounted) {
        context.go(mcpContext != null ? '/mcp/complete' : '/');
      }
    } catch (e, st) {
      debugPrint('[OAuthCallback] auth failed: $e\n$st');
      if (mounted) context.go('/signin?error=auth_failed');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: kBgDark,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: kAccentBlue),
          SizedBox(height: 16),
          Text('Finishing sign-in…', style: TextStyle(color: kTextSecondary)),
        ],
      ),
    ),
  );
}
