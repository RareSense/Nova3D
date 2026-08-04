import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_local_source.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/shared/services/glb_asset_cache.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

const String _privateCacheOwnerKey = '_nova3d_private_cache_owner';
const Duration _privateCachePreferenceTimeout = Duration(seconds: 2);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  AuthService get _service => ref.read(authServiceProvider);

  @override
  Future<UserModel?> build() async {
    try {
      final user = await _service.getCurrentUser();
      if (!await _bindPrivateCacheTo(user.id)) {
        await _clearSessionData();
        return null;
      }
      return user;
    } catch (e, st) {
      debugPrint('[AuthNotifier] restoring session failed: $e\n$st');
      await _clearSessionData();
      return null;
    }
  }

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    analytics.capture(Ev.signInStarted, <String, Object?>{
      Pr.authMethod: 'password',
    });
    try {
      await _service.signIn(email, password);
      final user = await _service.getCurrentUser();
      if (!await _bindPrivateCacheTo(user.id)) {
        throw AuthException(
          'Nova3D could not clear private model data from the previous '
          'session. Clear this site\'s browser data, then sign in again.',
        );
      }
      state = AsyncValue.data(user);
      // `identify` runs from analyticsIdentityProvider on the state change;
      // this only records the act of signing in.
      analytics.capture(Ev.signInSucceeded, <String, Object?>{
        Pr.authMethod: 'password',
      });
    } catch (e, st) {
      final error = e is AuthException
          ? e
          : AuthException('Sign in failed. Please try again.');
      analytics.capture(Ev.signInFailed, <String, Object?>{
        Pr.authMethod: 'password',
        Pr.errorMessage: error.message,
      });
      debugPrint('[AuthNotifier] signIn failed: $e\n$st');
      state = const AsyncValue.data(null);
      await _clearSessionData();
      throw error;
    }
  }

  Future<UserModel> signUp(String email, String password) async {
    analytics.capture(Ev.signUpStarted, <String, Object?>{
      Pr.authMethod: 'password',
    });
    try {
      final user = await _service.signUp(email, password);
      analytics.capture(Ev.signUpSucceeded, <String, Object?>{
        Pr.authMethod: 'password',
      });
      return user;
    } on AuthException catch (e) {
      analytics.capture(Ev.signUpFailed, <String, Object?>{
        Pr.authMethod: 'password',
        Pr.errorMessage: e.message,
      });
      rethrow;
    }
  }

  Future<void> handleOAuthCallback(String token) async {
    state = const AsyncValue.loading();
    try {
      await _service.handleOAuthCallback(token);
      final user = await _service.getCurrentUser();
      if (!await _bindPrivateCacheTo(user.id)) {
        throw AuthException(
          'Nova3D could not clear private model data from the previous '
          'session. Clear this site\'s browser data, then sign in again.',
        );
      }
      state = AsyncValue.data(user);
      analytics.capture(Ev.signInSucceeded, <String, Object?>{
        Pr.authMethod: 'oauth',
      });
    } catch (e, st) {
      final error = e is AuthException
          ? e
          : AuthException('Could not complete sign in. Please try again.');
      analytics.capture(Ev.signInFailed, <String, Object?>{
        Pr.authMethod: 'oauth',
        Pr.errorMessage: error.message,
      });
      debugPrint('[AuthNotifier] handleOAuthCallback failed: $e\n$st');
      state = const AsyncValue.data(null);
      await _clearSessionData();
      throw error;
    }
  }

  Future<void> signOut() async {
    // Update the UI and invalidate authenticated providers before touching
    // browser storage. A slow or broken storage backend must never leave the
    // app visibly signed in.
    state = const AsyncValue.data(null);
    final cleared = await _clearSessionData();
    if (!cleared) {
      debugPrint(
        '[AuthNotifier] signOut completed in memory, but browser storage '
        'cleanup could not be fully verified.',
      );
    }
  }

  Future<bool> _clearSessionData() async {
    // This is synchronous, so a validation that completes on the next event
    // loop turn cannot persist credentials after the boundary begins.
    ApiKeyLocalSource.invalidatePendingSaves();

    var tokenCleared = false;
    var privateDataCleared = false;
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          await _service.signOut();
          tokenCleared = true;
        } catch (e, st) {
          debugPrint('[AuthNotifier] token cleanup failed: $e\n$st');
        }
      }(),
      () async {
        privateDataCleared = await _bindPrivateCacheTo(null);
      }(),
    ]);
    return tokenCleared && privateDataCleared;
  }

  Future<bool> _bindPrivateCacheTo(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _privateCachePreferenceTimeout,
      );
      final previousOwner = prefs.getString(_privateCacheOwnerKey);
      final nextOwner = userId?.trim();
      final hasNextOwner = nextOwner != null && nextOwner.isNotEmpty;

      if (hasNextOwner && previousOwner == nextOwner) return true;

      // Retain only a proven same-user authenticated cold-start cache. Missing
      // ownership is treated as untrusted so upgrades are safe by default.
      final cleared = await Future.wait<bool>(<Future<bool>>[
        GlbAssetCache.clearPrivateData(),
        ApiKeyLocalSource().clearAll(),
      ]);
      final ownershipIsSafe = cleared.every((result) => result);

      if (hasNextOwner && ownershipIsSafe) {
        final stored = await prefs
            .setString(_privateCacheOwnerKey, nextOwner)
            .timeout(_privateCachePreferenceTimeout);
        return stored && prefs.getString(_privateCacheOwnerKey) == nextOwner;
      }

      final ownerRemoved = await _removePrivateCacheOwner(prefs);
      return !hasNextOwner && ownershipIsSafe && ownerRemoved;
    } catch (e, st) {
      debugPrint('[AuthNotifier] private cache ownership failed: $e\n$st');
      // Storage failure means ownership cannot be proved. Clear best-effort and
      // accept losing cache performance rather than risking cross-account data.
      await Future.wait<bool>(<Future<bool>>[
        GlbAssetCache.clearPrivateData(),
        ApiKeyLocalSource().clearAll(),
      ]);
      return false;
    }
  }

  Future<bool> _removePrivateCacheOwner(SharedPreferences prefs) async {
    if (!prefs.containsKey(_privateCacheOwnerKey)) return true;
    final removed = await prefs
        .remove(_privateCacheOwnerKey)
        .timeout(_privateCachePreferenceTimeout);
    return removed && !prefs.containsKey(_privateCacheOwnerKey);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(
  AuthNotifier.new,
);
