import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthNotifier extends AsyncNotifier<UserModel?> {
  AuthService get _service => ref.read(authServiceProvider);

  @override
  Future<UserModel?> build() async {
    try {
      return await _service.getCurrentUser();
    } catch (_) {
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
      state = AsyncValue.data(await _service.getCurrentUser());
      // `identify` runs from analyticsIdentityProvider on the state change;
      // this only records the act of signing in.
      analytics.capture(Ev.signInSucceeded, <String, Object?>{
        Pr.authMethod: 'password',
      });
    } on AuthException catch (e) {
      analytics.capture(Ev.signInFailed, <String, Object?>{
        Pr.authMethod: 'password',
        Pr.errorMessage: e.message,
      });
      state = const AsyncValue.data(null);
      rethrow;
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
      state = AsyncValue.data(await _service.getCurrentUser());
      analytics.capture(Ev.signInSucceeded, <String, Object?>{
        Pr.authMethod: 'oauth',
      });
    } catch (e, st) {
      analytics.capture(Ev.signInFailed, <String, Object?>{
        Pr.authMethod: 'oauth',
        Pr.errorMessage: e.toString(),
      });
      debugPrint('[AuthNotifier] handleOAuthCallback failed: $e\n$st');
      state = const AsyncValue.data(null);
      throw AuthException(e is AuthException ? e.message : e.toString());
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
    state = const AsyncValue.data(null);
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);
