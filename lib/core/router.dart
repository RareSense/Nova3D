import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/auth/presentation/forgot_password_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/oauth_callback_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/sign_in_page.dart';
import 'package:nova3d_frontend/features/auth/presentation/sign_up_page.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/features/account_api_keys/presentation/account_api_keys_page.dart';
import 'package:nova3d_frontend/features/chat/presentation/chat_page.dart';
import 'package:nova3d_frontend/features/home/presentation/home_page.dart';
import 'package:nova3d_frontend/features/home/presentation/model_preview_page.dart';
import 'package:nova3d_frontend/features/home/presentation/settings_page.dart';
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
      };

      if (isLoading) return null;
      if (!isAuthenticated && !publicPaths.contains(path)) return '/signin';
      if (isAuthenticated && publicPaths.contains(path)) return '/';
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

  ref.onDispose(() {
    router.dispose();
    notifier.dispose();
  });

  return router;
});
