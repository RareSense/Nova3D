import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';

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
    try {
      await _service.signIn(email, password);
      state = AsyncValue.data(await _service.getCurrentUser());
    } on AuthException {
      state = const AsyncValue.data(null);
      rethrow;
    }
  }

  Future<UserModel> signUp(String email, String password) =>
      _service.signUp(email, password);

  Future<void> handleOAuthCallback(String token) async {
    state = const AsyncValue.loading();
    try {
      await _service.handleOAuthCallback(token);
      state = AsyncValue.data(await _service.getCurrentUser());
    } catch (e, st) {
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
