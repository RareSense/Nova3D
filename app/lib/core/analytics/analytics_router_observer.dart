// Route-driven analytics: manual pageviews, and the session-replay guard that
// brackets screens where a provider key is visible on the canvas.
//
// Why not a NavigatorObserver: GoRouter's observers fire per Navigator, and the
// authenticated shell nests one inside another, so a ShellRoute tab change does
// not reliably produce a push/pop on the root observer. `routerDelegate` is a
// Listenable whose `currentConfiguration` always holds the resolved match list,
// which makes it the one hook that sees every navigation exactly once.

import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';

/// Routes that render provider API keys, the Nova3D MCP key, or checkout
/// fields. Session replay is stopped for the whole time one is on screen.
///
/// Input masking is not sufficient here: the Flutter shell paints to a
/// <canvas>, so replay captures raster frames and a key drawn as canvas text
/// would be plainly readable in playback. Stopping the recorder is the only
/// reliable protection.
const Set<String> kReplayBlockedRoutes = <String>{
  '/api-key',
  '/settings',
  '/mcp/complete',
  '/mcp/purchase-success',
};

/// Collapses concrete paths into their GoRouter patterns so insights group by
/// screen instead of exploding into one row per conversation id.
///
/// Derived from the route table by hand rather than read out of go_router's
/// internals: the table is small, and this keeps us off private API that moves
/// between minor versions.
String routePatternFor(String path) {
  if (path.startsWith('/chat/')) return '/chat/:id';
  if (path.startsWith('/showcase/')) return '/showcase/:tab';
  return path;
}

/// Wires pageview capture + the replay guard to [router]. Returns a disposer
/// the provider calls on teardown.
void Function() attachAnalyticsToRouter(GoRouter router) {
  String? previousPath;
  var replayPausedForRoute = false;

  void onRouteChanged() {
    final config = router.routerDelegate.currentConfiguration;
    if (config.matches.isEmpty) return;
    final path = config.uri.path;
    if (path == previousPath) return;

    final pattern = routePatternFor(path);

    // Toggle the replay guard BEFORE capturing the pageview, so the event that
    // marks entry into a secret screen is the last thing recorded.
    final shouldBlock = kReplayBlockedRoutes.contains(path);
    if (shouldBlock && !replayPausedForRoute) {
      analytics.pauseReplay();
      replayPausedForRoute = true;
    } else if (!shouldBlock && replayPausedForRoute) {
      analytics.resumeReplay();
      replayPausedForRoute = false;
    }

    analytics.pageview(
      path: path,
      pattern: pattern,
      previousPath: previousPath,
    );
    previousPath = path;
  }

  router.routerDelegate.addListener(onRouteChanged);
  // Fire once for the landing route; the delegate does not notify for it.
  onRouteChanged();

  return () {
    router.routerDelegate.removeListener(onRouteChanged);
    if (replayPausedForRoute) {
      analytics.resumeReplay();
      replayPausedForRoute = false;
    }
  };
}
