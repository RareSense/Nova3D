enum AiProvider {
  gemini('gemini', 'Gemini'),
  anthropic('anthropic', 'Anthropic'),
  openai('openai', 'OpenAI'),
  openrouter('openrouter', 'OpenRouter');

  const AiProvider(this.id, this.label);
  final String id;
  final String label;
}

class ProviderKeyState {
  const ProviderKeyState({
    required this.provider,
    this.hasKey = false,
    this.isValid = false,
    this.lastValidatedAt,
  });

  final AiProvider provider;
  final bool hasKey;
  final bool isValid;
  final DateTime? lastValidatedAt;

  ProviderKeyState copyWith({
    bool? hasKey,
    bool? isValid,
    DateTime? lastValidatedAt,
  }) => ProviderKeyState(
    provider: provider,
    hasKey: hasKey ?? this.hasKey,
    isValid: isValid ?? this.isValid,
    lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
  );
}

class ApiKeysState {
  const ApiKeysState({
    required this.keys,
    this.loading = false,
    this.validating,
    this.message,
  });

  factory ApiKeysState.empty() => ApiKeysState(
    keys: {
      for (final provider in AiProvider.values)
        provider: ProviderKeyState(provider: provider),
    },
  );

  final Map<AiProvider, ProviderKeyState> keys;
  final bool loading;
  final AiProvider? validating;
  final String? message;

  bool get hasValidKey => keys.values.any((key) => key.isValid);

  ProviderKeyState keyFor(AiProvider provider) =>
      keys[provider] ?? ProviderKeyState(provider: provider);

  ApiKeysState copyWith({
    Map<AiProvider, ProviderKeyState>? keys,
    bool? loading,
    AiProvider? validating,
    bool clearValidating = false,
    String? message,
    bool clearMessage = false,
  }) => ApiKeysState(
    keys: keys ?? this.keys,
    loading: loading ?? this.loading,
    validating: clearValidating ? null : validating ?? this.validating,
    message: clearMessage ? null : message ?? this.message,
  );
}
