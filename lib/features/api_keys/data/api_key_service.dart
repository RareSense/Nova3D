import 'package:dio/dio.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_local_source.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';

class ApiKeyValidationResult {
  const ApiKeyValidationResult({required this.isValid, required this.message});
  final bool isValid;
  final String message;
}

class ApiKeyService {
  ApiKeyService(this._local);

  final ApiKeyLocalSource _local;

  // ── Storage delegation ────────────────────────────────────────────────────

  Future<Map<AiProvider, ProviderKeyState>> loadStates() => _local.loadStates();

  Future<Map<String, String>> loadValidKeys() => _local.loadValidKeys();

  Future<void> clear(AiProvider provider) => _local.clear(provider);

  // ── Validation + save orchestration ──────────────────────────────────────

  Future<ApiKeyValidationResult> saveValidated(
    AiProvider provider,
    String apiKey,
  ) async {
    final trimmed = apiKey.trim();
    final formatError = _formatError(provider, trimmed);
    if (formatError != null) {
      return ApiKeyValidationResult(isValid: false, message: formatError);
    }

    final validation = await validate(provider, trimmed);
    if (!validation.isValid) return validation;

    await _local.save(provider, trimmed, isValid: true);
    return validation;
  }

  // TODO(security): replace direct provider calls with POST /api/keys/validate
  // once that backend endpoint is implemented, so keys never leave our backend.
  Future<ApiKeyValidationResult> validate(
    AiProvider provider,
    String apiKey,
  ) async {
    try {
      switch (provider) {
        case AiProvider.gemini:
          return await _validateGemini(apiKey);
        case AiProvider.anthropic:
          return await _validateAnthropic(apiKey);
        case AiProvider.openai:
          return await _validateOpenAi(apiKey);
        case AiProvider.openrouter:
          return await _validateOpenRouter(apiKey);
      }
    } catch (e) {
      final hint =
          e is DioException &&
              (e.type == DioExceptionType.connectionError ||
                  e.type == DioExceptionType.unknown)
          ? 'Check your internet connection and try again.'
          : 'Unexpected error — please try again.';
      return ApiKeyValidationResult(
        isValid: false,
        message: 'Could not validate ${provider.label} key. $hint',
      );
    }
  }

  Future<ApiKeyValidationResult> _validateGemini(String apiKey) async {
    final dio = Dio();
    try {
      await dio.get(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': apiKey},
      );
      return const ApiKeyValidationResult(
        isValid: true,
        message:
            'Gemini key saved. Keep at least \$10 credit available for generation.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400) {
        // 400 = INVALID_ARGUMENT — the key itself is malformed or invalid
        return const ApiKeyValidationResult(
          isValid: false,
          message: 'Gemini rejected this key. Double-check it is correct.',
        );
      }
      if (status == 403) {
        // 403 = PERMISSION_DENIED — key is valid but the Generative Language
        // API is not enabled in the associated Google Cloud project.
        return const ApiKeyValidationResult(
          isValid: false,
          message:
              'Gemini key is recognised but access is denied. Enable the '
              '"Generative Language API" in your Google Cloud Console, then try again.',
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return const ApiKeyValidationResult(
          isValid: false,
          message:
              'Could not reach Gemini to validate the key. Check your connection and try again.',
        );
      }
      rethrow;
    }
  }

  Future<ApiKeyValidationResult> _validateAnthropic(String apiKey) async {
    final dio = Dio();
    try {
      await dio.get(
        'https://api.anthropic.com/v1/models',
        options: Options(
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-dangerous-direct-browser-access': 'true',
          },
        ),
      );
      return ApiKeyValidationResult(
        isValid: true,
        message:
            'Anthropic key saved. Keep at least \$10 credit available for generation.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const ApiKeyValidationResult(
          isValid: false,
          message: 'Anthropic rejected this key.',
        );
      }
      rethrow;
    }
  }

  Future<ApiKeyValidationResult> _validateOpenAi(String apiKey) async {
    final dio = Dio();
    try {
      await dio.get(
        'https://api.openai.com/v1/models',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      return ApiKeyValidationResult(
        isValid: true,
        message:
            'OpenAI key saved. Keep at least \$10 credit available for generation.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const ApiKeyValidationResult(
          isValid: false,
          message: 'OpenAI rejected this key.',
        );
      }
      rethrow;
    }
  }

  Future<ApiKeyValidationResult> _validateOpenRouter(String apiKey) async {
    final dio = Dio();
    try {
      final resp = await dio.get(
        'https://openrouter.ai/api/v1/key',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      final data = resp.data is Map ? resp.data as Map : const {};
      final keyData = data['data'] is Map ? data['data'] as Map : const {};
      final remaining = keyData['limit_remaining'];
      if (remaining is num && remaining <= 0) {
        return const ApiKeyValidationResult(
          isValid: false,
          message:
              'OpenRouter accepted this key, but it has no remaining spend limit or balance.',
        );
      }
      return ApiKeyValidationResult(
        isValid: true,
        message:
            'OpenRouter key saved. Keep enough provider balance available for generation.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const ApiKeyValidationResult(
          isValid: false,
          message: 'OpenRouter rejected this key.',
        );
      }
      rethrow;
    }
  }

  String? _formatError(AiProvider provider, String apiKey) {
    if (apiKey.length < 16) return 'Key is too short.';
    switch (provider) {
      case AiProvider.gemini:
        return apiKey.startsWith('AIza')
            ? null
            : 'Gemini keys usually start with AIza.';
      case AiProvider.anthropic:
        return apiKey.startsWith('sk-ant-')
            ? null
            : 'Anthropic keys usually start with sk-ant-.';
      case AiProvider.openai:
        return apiKey.startsWith('sk-') &&
                !apiKey.startsWith('sk-ant-') &&
                !apiKey.startsWith('sk-or-')
            ? null
            : 'OpenAI keys usually start with sk-.';
      case AiProvider.openrouter:
        return apiKey.startsWith('sk-or-')
            ? null
            : 'OpenRouter keys usually start with sk-or-.';
    }
  }
}
