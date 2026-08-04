import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/analytics/analytics_router_observer.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/auth/presentation/forgot_password_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/oauth_callback_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/sign_in_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/sign_up_page.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_complete_page.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_connect_page.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_no_credits_page.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_purchase_success_page.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/features/account_api_keys/presentation/account_api_keys_page.dart';
import 'package:nova3d_frontend/features/chat/presentation/chat_page.dart';
import 'package:nova3d_frontend/features/home/presentation/home_page.dart';
import 'package:nova3d_frontend/features/home/presentation/model_preview_page.dart';
import 'package:nova3d_frontend/features/home/presentation/settings_page.dart';
import 'package:nova3d_frontend/features/showcase/presentation/showcase_page.dart';
import 'package:nova3d_frontend/features/subscription/presentation/payment_success_page.dart';
import 'package:nova3d_frontend/features/subscription/presentation/subscription_page.dart';
import 'package:nova3d_frontend/shared/widgets/app_layout.dart';
import 'package:nova3d_frontend/shared/widgets/auth_guard.dart';

CustomTransitionPage<void> _fadePage(LocalKey key, Widget child) =>
    CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

// Bridges Riverpod auth state into a ChangeNotifier so GoRouter can listen
// via refreshListenable without recreating the router on every auth change.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<UserModel?>>(
      authProvider,
      (_, _) => notifyListeners(),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefreshNotifier(ref);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      // Read current auth state each time redirect fires — never watch.
      final authState = ref.read(authProvider);
      final isAuthenticated = authState.valueOrNull != null;
      final isLoading = authState.isLoading;
      final path = state.uri.path;

      const publicPaths = {
        '/signin',
        '/signup',
        '/forgot-password',
        '/oauth-callback',
        '/success',
        '/showcase',
        '/mcp/connect',
        '/mcp/complete',
        '/mcp/no-credits',
        '/mcp/purchase-success',
      };
      const authEntryPaths = {
        '/signin',
        '/signup',
        '/forgot-password',
        '/oauth-callback',
      };

      if (isLoading) return null;
      // The showcase is public at /showcase and every per-tab sub-path
      // (/showcase/textures, /showcase/rings, …).
      final isPublic = publicPaths.contains(path) ||
          path == '/showcase' ||
          path.startsWith('/showcase/');
      if (!isAuthenticated && !isPublic) return '/signin';
      if (isAuthenticated && authEntryPaths.contains(path)) return '/';
      return null;
    },
    routes: [
      // ── Public routes ────────────────────────────────────────────────────
      GoRoute(
        path: '/signin',
        pageBuilder: (_, state) => _fadePage(state.pageKey, const SignInPage()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => _fadePage(state.pageKey, const SignUpPage()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const ForgotPasswordPage()),
      ),
      GoRoute(
        path: '/oauth-callback',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const OAuthCallbackPage()),
      ),
      GoRoute(
        path: '/success',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const PaymentSuccessPage()),
      ),
      GoRoute(
        path: '/mcp/connect',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const McpConnectPage()),
      ),
      GoRoute(
        path: '/mcp/complete',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const McpCompletePage()),
      ),
      GoRoute(
        path: '/mcp/no-credits',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const McpNoCreditsPage()),
      ),
      GoRoute(
        path: '/mcp/purchase-success',
        pageBuilder: (_, state) =>
            _fadePage(state.pageKey, const McpPurchaseSuccessPage()),
      ),
      // Showcase: one page, per-tab URLs. A STABLE page key across /showcase
      // and /showcase/:tab keeps the embedded gallery iframe alive when the
      // tab changes (no reload of the Three.js grid) — only ShowcasePage's tab
      // param updates and is messaged into the iframe.
      GoRoute(
        path: '/showcase',
        pageBuilder: (_, state) =>
            _fadePage(const ValueKey('showcase'), const ShowcasePage()),
      ),
      GoRoute(
        path: '/showcase/:tab',
        pageBuilder: (_, state) => _fadePage(
          const ValueKey('showcase'),
          ShowcasePage(tab: state.pathParameters['tab']),
        ),
      ),

      // ── Authenticated shell ──────────────────────────────────────────────
      ShellRoute(
        builder: (_, _, child) => AuthGuard(child: AppLayout(child: child)),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) =>
                NoTransitionPage(key: state.pageKey, child: const HomePage()),
          ),
          GoRoute(
            path: '/chat/:id',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: ChatPage(conversationId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/subscription',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const SubscriptionPage(),
            ),
          ),
          GoRoute(
            path: '/api-key',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const AccountApiKeysPage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/model-preview',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ModelPreviewPage(),
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      backgroundColor: kCream,
      body: Center(
        child: Text(
          'Page not found: ${state.uri}',
          style: const TextStyle(color: kInkSoft),
        ),
      ),
    ),
  );

  // Manual pageviews + the session-replay guard for key-bearing screens.
  final detachAnalytics = attachAnalyticsToRouter(router);

  ref.onDispose(() {
    detachAnalytics();
    router.dispose();
    notifier.dispose();
  });

  return router;
});
