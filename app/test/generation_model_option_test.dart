import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

void main() {
  test('paid credit catalog plus supported byok providers', () {
    // Initial generation is credits-only; BYOK options are surfaced separately
    // for edit operations. This composes both catalogs to assert their shapes.
    final options = [
      ...GenerationModelOption.paidCreditOptions,
      ...GenerationModelOption.byokForKeys({
        AiProvider.gemini.id: 'gemini-key',
        AiProvider.anthropic.id: 'anthropic-key',
        AiProvider.openai.id: 'openai-key',
        AiProvider.openrouter.id: 'openrouter-key',
        'legacy_provider': 'legacy-key',
      }),
    ];
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
        'credits_claude_fable_5_anthropic',
        'credits_claude_opus_4_8_anthropic',
        'credits_claude_sonnet_5_anthropic',
        'credits_claude_sonnet_4_6_anthropic',
        'credits_gpt_5_6_sol_openrouter',
        'credits_gpt_5_5_openrouter',
        'credits_gpt_5_6_terra_openrouter',
        'credits_gpt_5_6_luna_openrouter',
        'credits_gemini_3_1_pro_google',
      ]),
    );
    expect(
      {
        for (final option
            in options.where((option) => option.isPaidCredit))
          option.id: option.creditCost,
      },
      equals({
        'credits_claude_fable_5_anthropic': 60,
        'credits_claude_opus_4_8_anthropic': 25,
        'credits_claude_sonnet_5_anthropic': 18,
        'credits_claude_sonnet_4_6_anthropic': 15,
        'credits_gpt_5_6_sol_openrouter': 30,
        'credits_gpt_5_5_openrouter': 28,
        'credits_gpt_5_6_terra_openrouter': 18,
        'credits_gpt_5_6_luna_openrouter': 10,
        'credits_gemini_3_1_pro_google': 12,
      }),
    );
    expect(
      options
          .where((option) => option.requiresProviderKey)
          .map((option) => option.payloadProvider),
      unorderedEquals([
        'anthropic',
        'anthropic',
        'anthropic',
        'anthropic',
        'openai',
        'openrouter',
        'openrouter',
        'openrouter',
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
        'anthropic_claude_fable_5': 'claude-fable:claude_fable_5_anthropic',
        'anthropic_claude_sonnet_5':
            'claude-sonnet-5:claude_sonnet_5_anthropic',
        'anthropic_claude_sonnet': 'claude-sonnet:claude_sonnet_4_6_anthropic',
        'anthropic_claude_opus_4_8': 'claude-opus:claude_opus_4_8_anthropic',
        'openai_gpt55': 'gpt55:gpt_5_5_openai',
        'openrouter_gpt56_sol': 'gpt56-sol:gpt_5_6_sol_openrouter',
        'openrouter_gpt56_terra': 'gpt56-terra:gpt_5_6_terra_openrouter',
        'openrouter_gpt56_luna': 'gpt56-luna:gpt_5_6_luna_openrouter',
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
      orderedEquals(['Claude Fable 5:Recommended', 'Gemini 3.1 Pro:Fastest']),
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
