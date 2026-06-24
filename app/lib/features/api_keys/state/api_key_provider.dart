import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_local_source.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_service.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
final apiKeyLocalSourceProvider =
    Provider<ApiKeyLocalSource>((_) => ApiKeyLocalSource());

final apiKeyServiceProvider = Provider<ApiKeyService>((ref) {
  return ApiKeyService(ref.watch(apiKeyLocalSourceProvider));
});

final apiKeysProvider =
    NotifierProvider<ApiKeysNotifier, ApiKeysState>(ApiKeysNotifier.new);

class ApiKeysNotifier extends Notifier<ApiKeysState> {
  @override
  ApiKeysState build() {
    Future.microtask(load);
    return ApiKeysState.empty();
  }

  ApiKeyService get _service => ref.read(apiKeyServiceProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearMessage: true);
    final keys = await _service.loadStates();
    state = state.copyWith(keys: keys, loading: false);
  }

  Future<void> save(AiProvider provider, String apiKey) async {
    state = state.copyWith(validating: provider, clearMessage: true);
    final result = await _service.saveValidated(provider, apiKey);
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
  }

  Future<void> clear(AiProvider provider) async {
    await _service.clear(provider);
    final updated = Map<AiProvider, ProviderKeyState>.from(state.keys);
    updated[provider] = ProviderKeyState(provider: provider);
    state = state.copyWith(
      keys: updated,
      message: '${provider.label} key removed.',
    );
  }
}
