import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

void main() {
  test('returns paid options plus supported byok providers', () {
    final options = GenerationModelOption.forKeys({
      AiProvider.gemini.id: 'gemini-key',
      AiProvider.anthropic.id: 'anthropic-key',
      AiProvider.openai.id: 'openai-key',
      'legacy_provider': 'legacy-key',
    });

    expect(options, isNotEmpty);
    expect(
      GenerationProvider.values.map((provider) => provider.id),
      orderedEquals(['auto', 'anthropic', 'openai', 'openrouter', 'gemini']),
    );
    expect(
      options.where((option) => option.isPaidCredit).map((option) => option.id),
      orderedEquals([
        'credits_claude_opus_4_8_anthropic',
        'credits_claude_sonnet_4_6_anthropic',
        'credits_gpt_5_5_openrouter',
        'credits_gemini_3_1_pro_google',
      ]),
    );
    expect(
      options
          .where((option) => option.requiresProviderKey)
          .map((option) => option.payloadProvider),
      unorderedEquals([
        'anthropic',
        'anthropic',
        'anthropic',
        'openai',
        'gemini',
      ]),
    );
    expect(
      {
        for (final option in options.where(
          (option) => option.requiresProviderKey,
        ))
          option.llm: option.label,
      },
      equals({
        'claude-sonnet': 'Claude Sonnet 4.6',
        'claude-opus': 'Claude Opus 4.6',
        'claude-opus-latest': 'Claude Opus 4.7',
        'gpt55': 'GPT-5.5',
        'gemini': 'Gemini 3.1 Pro Preview',
      }),
    );
    expect(
      GenerationModelOption.paidCreditOptions
          .where((option) => option.badgeLabel != null)
          .map((option) => '${option.compactLabel}:${option.badgeLabel}'),
      orderedEquals(['GPT-5.5:Recommended', 'Gemini 3.1 Pro:Fastest']),
    );
  });

  test('returns byok options only for edit workflows', () {
    final options = GenerationModelOption.byokForKeys({
      AiProvider.gemini.id: 'gemini-key',
    });

    expect(options, hasLength(1));
    expect(options.single.id, 'gemini_gemini');
    expect(options.single.displayLabel, 'Gemini 3.1 Pro Preview (Gemini key)');
  });
}
