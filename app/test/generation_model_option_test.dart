import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

void main() {
  test('returns paid options plus supported byok providers', () {
    final options = GenerationModelOption.forKeys({
      AiProvider.gemini.id: 'gemini-key',
      AiProvider.anthropic.id: 'anthropic-key',
      AiProvider.openai.id: 'openai-key',
      AiProvider.openrouter.id: 'openrouter-key',
      'legacy_provider': 'legacy-key',
    });
    final byok = options
        .where((option) => option.requiresProviderKey)
        .toList(growable: false);

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
        'openai',
        'openrouter',
        'openrouter',
        'openrouter',
        'openrouter',
        'gemini',
      ]),
    );
    expect(
      {
        for (final option in byok)
          option.id: '${option.llm}:${option.codeLlmTier}',
      },
      equals({
        'anthropic_claude_sonnet': 'claude-sonnet:claude_sonnet_4_6_anthropic',
        'anthropic_claude_opus_4_8': 'claude-opus:claude_opus_4_8_anthropic',
        'openai_gpt55': 'gpt55:gpt_5_5_openai',
        'openrouter_gpt55': 'gpt55:gpt_5_5_openrouter',
        'openrouter_gemini': 'gemini:gemini_3_1_pro_openrouter',
        'openrouter_claude_sonnet':
            'claude-sonnet:claude_sonnet_4_6_openrouter',
        'openrouter_claude_opus': 'claude-opus:claude_opus_4_8_openrouter',
        'gemini_gemini': 'gemini:gemini_3_1_pro_google',
      }),
    );
    expect(byok.map((option) => option.workflowName).toSet(), {
      kSketchTo3dByokWorkflow,
    });
    expect(
      GenerationModelOption.paidCreditOptions
          .where((option) => option.badgeLabel != null)
          .map((option) => '${option.compactLabel}:${option.badgeLabel}'),
      orderedEquals(['GPT-5.5:Recommended', 'Gemini 3.1 Pro:Fastest']),
    );
    expect(
      GenerationModelOption.findById(options, null)?.id,
      'credits_gemini_3_1_pro_google',
    );
  });

  test('returns byok options for available provider keys', () {
    final options = GenerationModelOption.byokForKeys({
      AiProvider.gemini.id: 'gemini-key',
    });

    expect(options, hasLength(1));
    expect(options.single.id, 'gemini_gemini');
    expect(options.single.displayLabel, 'Gemini 3.1 Pro Preview (Gemini key)');
    expect(GenerationModelOption.findById(options, null)?.id, 'gemini_gemini');
  });
}
