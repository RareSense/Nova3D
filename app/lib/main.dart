import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_provider.dart';
import 'package:nova3d_frontend/core/router.dart';
import 'package:nova3d_frontend/core/startup_url_bootstrap.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:web/web.dart' as web;

/// Routes uncaught Flutter + platform errors into PostHog error tracking.
///
/// Installed before `runApp` so a crash during first build is still reported.
/// Both handlers delegate to the original behaviour first: analytics must
/// observe failures, never swallow them (a swallowed error would vanish from
/// the browser console and make local debugging worse).
void _installErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    analytics.captureException(
      details.exception,
      details.stack,
      context: details.library ?? 'flutter',
      handled: false,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.captureException(
      error,
      stack,
      context: 'platform_dispatcher',
      handled: false,
    );
    // false = keep propagating to the default handler / console.
    return false;
  };
}

/// Removes checkout, MCP handoff, and OAuth credentials from the address bar
/// before any third-party SDK can observe the page URL.
void _sanitizeStartupUrl() {
  final sanitized = StartupUrlBootstrap.capture(Uri.base);
  if (sanitized == null) return;
  web.window.history.replaceState(null, '', sanitized.toString());
}

void main() {
  // URL credentials must be removed before analytics initialization. PostHog
  // adds browser URL context outside our custom-property scrubber.
  _sanitizeStartupUrl();

  // Analytics first: session replay should cover as much of the session as
  // possible, and the error handlers below need it live.
  analytics.init();
  _installErrorHandlers();

  // Resolve Inter/VT323/Silkscreen from the bundled asset fonts (declared
  // in pubspec.yaml) instead of fetching from fonts.gstatic.com at runtime.
  // Eliminates the first-frame font swap that runtime fetching causes.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Use clean path-based URLs (/route) instead of hash-based (/#/route).
  // Without this, GoRouter reads the OAuth fragment (#access_token=...) as a
  // route path, fails to match it, and crashes with a RouteMatchList assertion.
  usePathUrlStrategy();

  runApp(const ProviderScope(child: Nova3DApp()));
}

class Nova3DApp extends ConsumerWidget {
  const Nova3DApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps PostHog identity in step with auth state for the app's lifetime.
    ref.watch(analyticsIdentityProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Nova3D',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
