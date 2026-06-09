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

final generationReadinessProvider = FutureProvider<GenerationReadiness>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.isLoading) {
    throw CadException('Checking your sign-in session...');
  }
  if (auth.valueOrNull == null) {
    throw CadException('Please sign in again before generating.');
  }
  return ref.watch(cadServiceProvider).checkReadiness();
});

final generationModelOptionsProvider =
    FutureProvider<List<GenerationModelOption>>((ref) async {
      ref.watch(apiKeysProvider);
      final keys = await ref.watch(apiKeyServiceProvider).loadValidKeys();
      return GenerationModelOption.forKeys(keys);
    });

final byokGenerationModelOptionsProvider =
    FutureProvider<List<GenerationModelOption>>((ref) async {
      ref.watch(apiKeysProvider);
      final keys = await ref.watch(apiKeyServiceProvider).loadValidKeys();
      return GenerationModelOption.byokForKeys(keys);
    });
