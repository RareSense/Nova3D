import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/api_keys/state/api_key_provider.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

final cadServiceProvider = Provider<CadService>((ref) {
  return CadService(
    ref.watch(authServiceProvider),
    ref.watch(apiKeyServiceProvider),
  );
});

class GenerationReadinessNotifier
    extends Notifier<AsyncValue<GenerationReadiness>> {
  int _requestEpoch = 0;

  @override
  AsyncValue<GenerationReadiness> build() {
    final auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const AsyncValue.loading();
    }
    if (auth.valueOrNull == null) {
      return AsyncValue.error(
        CadException('Please sign in again before generating.'),
        StackTrace.current,
      );
    }

    final requestEpoch = ++_requestEpoch;
    unawaited(_load(requestEpoch));
    return const AsyncValue.loading();
  }

  Future<void> _load(int requestEpoch) async {
    final nextState = await AsyncValue.guard(
      () => ref.read(cadServiceProvider).checkReadiness(),
    );
    // Authentication changes, an explicit retry, or a successful direct
    // preflight supersede older responses. Never let a late response restore
    // stale readiness state.
    if (requestEpoch == _requestEpoch) state = nextState;
  }

  void accept(GenerationReadiness readiness) {
    _requestEpoch++;
    state = AsyncValue.data(readiness);
  }

  Future<void> retry() async {
    final requestEpoch = ++_requestEpoch;
    state = const AsyncValue.loading();
    await _load(requestEpoch);
  }
}

final generationReadinessProvider =
    NotifierProvider<
      GenerationReadinessNotifier,
      AsyncValue<GenerationReadiness>
    >(GenerationReadinessNotifier.new);

// Initial generation is credits-only. BYOK is offered solely for edit
// operations (regenerate / add part / articulate) via
// [byokGenerationModelOptionsProvider]. Because the paid-credit catalog is
// static and independent of stored provider keys, this provider does not watch
// API-key state.
final generationModelOptionsProvider =
    FutureProvider<List<GenerationModelOption>>(
      (ref) => GenerationModelOption.paidCreditOptions,
    );

final byokGenerationModelOptionsProvider =
    FutureProvider<List<GenerationModelOption>>((ref) async {
      ref.watch(apiKeysProvider);
      final keys = await ref.watch(apiKeyServiceProvider).loadValidKeys();
      return GenerationModelOption.byokForKeys(keys);
    });
