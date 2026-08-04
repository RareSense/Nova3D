import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_local_source.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_service.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';

final apiKeyLocalSourceProvider = Provider<ApiKeyLocalSource>(
  (_) => ApiKeyLocalSource(),
);

final apiKeyServiceProvider = Provider<ApiKeyService>((ref) {
  return ApiKeyService(ref.watch(apiKeyLocalSourceProvider));
});

final apiKeysProvider = NotifierProvider<ApiKeysNotifier, ApiKeysState>(
  ApiKeysNotifier.new,
);

class ApiKeysNotifier extends Notifier<ApiKeysState> {
  int _authEpoch = 0;
  String? _activeUserId;

  @override
  ApiKeysState build() {
    final epoch = ++_authEpoch;
    final userId = ref.watch(
      authProvider.select((auth) => auth.valueOrNull?.id),
    );
    _activeUserId = userId;
    if (userId == null) return ApiKeysState.empty();
    Future.microtask(() => _load(epoch, userId));
    return ApiKeysState.empty();
  }

  ApiKeyService get _service => ref.read(apiKeyServiceProvider);

  bool _isCurrent(int epoch, String userId) =>
      epoch == _authEpoch &&
      userId == _activeUserId &&
      ref.read(authProvider).valueOrNull?.id == userId;

  Future<void> _load(int epoch, String userId) async {
    if (!_isCurrent(epoch, userId)) return;
    state = state.copyWith(loading: true, clearMessage: true);
    final keys = await _service.loadStates();
    if (!_isCurrent(epoch, userId)) return;
    state = state.copyWith(keys: keys, loading: false);
  }

  Future<void> save(AiProvider provider, String apiKey) async {
    final epoch = _authEpoch;
    final userId = _activeUserId;
    if (userId == null || !_isCurrent(epoch, userId)) return;
    final credentialEpoch = ApiKeyLocalSource.credentialEpoch;
    state = state.copyWith(validating: provider, clearMessage: true);
    final result = await _service.saveValidated(
      provider,
      apiKey,
      expectedEpoch: credentialEpoch,
    );
    if (!_isCurrent(epoch, userId) ||
        credentialEpoch != ApiKeyLocalSource.credentialEpoch) {
      return;
    }
    final updated = Map<AiProvider, ProviderKeyState>.from(state.keys);
    updated[provider] = ProviderKeyState(
      provider: provider,
      hasKey: result.isValid,
      isValid: result.isValid,
      lastValidatedAt: result.isValid ? DateTime.now() : null,
    );
    state = state.copyWith(
      keys: updated,
      clearValidating: true,
      message: result.message,
    );
    // Provider identity only. The key itself never leaves this method, and
    // Analytics._scrub would redact it even if a future edit tried.
    analytics.capture(
      result.isValid ? Ev.apiKeySaved : Ev.apiKeyValidationFailed,
      <String, Object?>{Pr.provider: provider.id},
    );
  }

  Future<void> clear(AiProvider provider) async {
    final epoch = _authEpoch;
    final userId = _activeUserId;
    if (userId == null || !_isCurrent(epoch, userId)) return;
    final credentialEpoch = ApiKeyLocalSource.credentialEpoch;
    final cleared = await _service.clear(
      provider,
      expectedEpoch: credentialEpoch,
    );
    if (!cleared ||
        !_isCurrent(epoch, userId) ||
        credentialEpoch != ApiKeyLocalSource.credentialEpoch) {
      return;
    }
    final updated = Map<AiProvider, ProviderKeyState>.from(state.keys);
    updated[provider] = ProviderKeyState(provider: provider);
    state = state.copyWith(
      keys: updated,
      message: '${provider.label} key removed.',
    );
    analytics.capture(Ev.apiKeyRemoved, <String, Object?>{
      Pr.provider: provider.id,
    });
  }
}
