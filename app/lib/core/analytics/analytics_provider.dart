// Binds PostHog identity to Riverpod auth state.
//
// Watched once at the app root. Kept out of AuthNotifier on purpose: auth is
// domain logic that must stay testable without a browser, and analytics is an
// observer of it, not a participant.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';

/// Calls `identify` when a user appears and `reset` when they sign out.
///
/// `identify` is idempotent per user id inside [Analytics], so the rebuild
/// churn of an AsyncNotifier does not produce duplicate identify calls.
final analyticsIdentityProvider = Provider<void>((ref) {
  void apply(UserModel? user) {
    if (user == null) return;
    analytics.identify(
      userId: user.id,
      email: user.email,
      isVerified: user.isVerified,
      extraPersonProperties: <String, Object?>{
        'is_superuser': user.isSuperuser,
        'is_active': user.isActive,
      },
    );
  }

  ref.listen<AsyncValue<UserModel?>>(authProvider, (previous, next) {
    final wasSignedIn = previous?.valueOrNull != null;
    final user = next.valueOrNull;

    if (user != null) {
      apply(user);
      return;
    }
    // Only reset on a real sign-out (authenticated → null), never on the
    // loading → null path at startup, which would wipe the anonymous session
    // id on every cold boot and break funnel continuity.
    if (wasSignedIn && next is AsyncData) {
      analytics.capture(Ev.signedOut);
      analytics.reset();
    }
  });

  apply(ref.read(authProvider).valueOrNull);
});
