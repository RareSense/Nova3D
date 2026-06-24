import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:web/web.dart' as web;

void main() {
  // Resolve Inter/VT323/Silkscreen from the bundled asset fonts (declared
  // in pubspec.yaml) instead of fetching from fonts.gstatic.com at runtime.
  // Eliminates the first-frame font swap that runtime fetching causes.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Use clean path-based URLs (/route) instead of hash-based (/#/route).
  // Without this, GoRouter reads the OAuth fragment (#access_token=...) as a
  // route path, fails to match it, and crashes with a RouteMatchList assertion.
  usePathUrlStrategy();

  // Strip the OAuth token out of the URL fragment before GoRouter initializes.
  // GoRouter's route matcher asserts uri.path.startsWith(matchedLocation),
  // which fails when the fragment is still attached to the path string.
  // We park the fragment in sessionStorage; OAuthCallbackPage reads it from there.
  final hash = web.window.location.hash;
  if (hash.contains('access_token=')) {
    web.window.sessionStorage.setItem(
      '_nova3d_oauth',
      hash.startsWith('#') ? hash.substring(1) : hash,
    );
    web.window.history.replaceState(
      null,
      '',
      '${web.window.location.pathname}${web.window.location.search}',
    );
  }

  runApp(const ProviderScope(child: Nova3DApp()));
}

class Nova3DApp extends ConsumerWidget {
  const Nova3DApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Nova3D',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
