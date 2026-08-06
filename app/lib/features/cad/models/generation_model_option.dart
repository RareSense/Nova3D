import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';

enum GenerationProvider {
  auto('auto', 'Auto'),
  anthropic('anthropic', 'Anthropic'),
  openai('openai', 'OpenAI'),
  openrouter('openrouter', 'OpenRouter'),
  gemini('gemini', 'Gemini'),
  zai('zai', 'Z.AI'),
  moonshot('moonshot', 'Moonshot AI');

  const GenerationProvider(this.id, this.label);
  final String id;
  final String label;
}

enum GenerationBillingMode { credits, providerKey }

class GenerationModelOption {
  const GenerationModelOption({
    required this.id,
    required this.label,
    required this.llm,
    required this.provider,
    this.keyProvider,
    this.billingMode = GenerationBillingMode.providerKey,
    this.creditCost,
    this.workflowName,
    this.codeLlmProfile,
    this.codeLlmTier,
  });

  final String id;
  final String label;
  final String llm;
  final GenerationProvider provider;
  final AiProvider? keyProvider;
  final GenerationBillingMode billingMode;
  final int? creditCost;
  final String? workflowName;
  final String? codeLlmProfile;
  final String? codeLlmTier;

  String get payloadProvider => provider.id;
  bool get isPaidCredit => billingMode == GenerationBillingMode.credits;
  bool get requiresProviderKey =>
      billingMode == GenerationBillingMode.providerKey;

  String get displayLabel {
    if (isPaidCredit) return '$label (${creditCost ?? 0} credits)';
    final providerLabel = keyProvider?.label ?? provider.label;
    return '$label ($providerLabel key)';
  }

  String get detailLabel {
    if (isPaidCredit) return '${creditCost ?? 0} credits';
    final providerLabel = keyProvider?.label ?? provider.label;
    return '$providerLabel key';
  }

  String? get badgeLabel {
    if (!isPaidCredit) return null;
    if (codeLlmTier == 'claude_fable_5_anthropic') return 'Recommended';
    if (codeLlmTier == 'gemini_3_1_pro_google') return 'Fastest';
    return null;
  }

  String get compactLabel {
    if (label == 'Gemini 3.1 Pro Preview') return 'Gemini 3.1 Pro';
    return label;
  }

  String get persistedLabel => label;

  /// Routing and billing facts shared by hosted estimate and run requests.
  /// An explicit empty key makes the server-funded contract unambiguous while
  /// keeping provider credentials exclusively on the backend.
  Map<String, String> get hostedGenerationContext => {
    'code_llm_profile': codeLlmProfile ?? _codeLlmProfile,
    'code_llm_tier': codeLlmTier ?? llm,
    'code_llm_api_key': '',
  };

  static List<GenerationModelOption> byokForKeys(Map<String, String> keys) {
    final options = <GenerationModelOption>[];
    if ((keys[AiProvider.anthropic.id] ?? '').isNotEmpty) {
      options.addAll(_anthropicOptions);
    }
    if ((keys[AiProvider.openai.id] ?? '').isNotEmpty) {
      options.add(_openAiOption);
    }
    if ((keys[AiProvider.openrouter.id] ?? '').isNotEmpty) {
      options.addAll(_openRouterOptions);
    }
    if ((keys[AiProvider.gemini.id] ?? '').isNotEmpty) {
      options.add(_geminiOption);
    }
    return options;
  }

  static GenerationModelOption? findById(
    Iterable<GenerationModelOption> options,
    String? id,
  ) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return defaultFor(options);
  }

  static GenerationModelOption? defaultFor(
    Iterable<GenerationModelOption> options,
  ) {
    GenerationModelOption? geminiByok;
    GenerationModelOption? first;
    for (final option in options) {
      first ??= option;
      if (option.id == 'credits_gemini_3_1_pro_google') return option;
      if (option.id == 'gemini_gemini') geminiByok = option;
    }
    return geminiByok ?? first;
  }

  static const paidCreditOptions = [
    GenerationModelOption(
      id: 'credits_claude_opus_5_anthropic',
      label: 'Claude Opus 5 — Anthropic',
      llm: 'claude_opus_5_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_opus_5_anthropic',
    ),
    GenerationModelOption(
      id: 'credits_claude_opus_5_openrouter',
      label: 'Claude Opus 5 — OpenRouter',
      llm: 'claude_opus_5_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_opus_5_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_glm_5_2_zai',
      label: 'GLM-5.2 — Z.AI',
      llm: 'glm_5_2_zai',
      provider: GenerationProvider.zai,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'glm_5_2_zai',
    ),
    GenerationModelOption(
      id: 'credits_glm_5_2_openrouter',
      label: 'GLM-5.2 — OpenRouter',
      llm: 'glm_5_2_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'glm_5_2_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_kimi_k3_moonshot',
      label: 'Kimi K3 — Moonshot AI',
      llm: 'kimi_k3_moonshot',
      provider: GenerationProvider.moonshot,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'kimi_k3_moonshot',
    ),
    GenerationModelOption(
      id: 'credits_kimi_k3_openrouter',
      label: 'Kimi K3 — OpenRouter',
      llm: 'kimi_k3_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'kimi_k3_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_claude_fable_5_anthropic',
      label: 'Claude Fable 5',
      llm: 'claude_fable_5_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 60,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_fable_5_anthropic',
    ),
    GenerationModelOption(
      id: 'credits_claude_opus_4_8_anthropic',
      label: 'Claude Opus 4.8',
      llm: 'claude_opus_4_8_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 25,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_opus_4_8_anthropic',
    ),
    GenerationModelOption(
      id: 'credits_claude_sonnet_5_anthropic',
      label: 'Claude Sonnet 5',
      llm: 'claude_sonnet_5_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 18,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_sonnet_5_anthropic',
    ),
    GenerationModelOption(
      id: 'credits_claude_sonnet_4_6_anthropic',
      label: 'Claude Sonnet 4.6',
      llm: 'claude_sonnet_4_6_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 15,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_sonnet_4_6_anthropic',
    ),
    GenerationModelOption(
      id: 'credits_gpt_5_6_sol_openrouter',
      label: 'GPT-5.6 Sol',
      llm: 'gpt_5_6_sol_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 30,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'gpt_5_6_sol_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_gpt_5_5_openrouter',
      label: 'GPT-5.5',
      llm: 'gpt_5_5_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 28,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'gpt_5_5_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_gpt_5_6_terra_openrouter',
      label: 'GPT-5.6 Terra',
      llm: 'gpt_5_6_terra_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 18,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'gpt_5_6_terra_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_gpt_5_6_luna_openrouter',
      label: 'GPT-5.6 Luna',
      llm: 'gpt_5_6_luna_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 10,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'gpt_5_6_luna_openrouter',
    ),
    GenerationModelOption(
      id: 'credits_gemini_3_1_pro_google',
      label: 'Gemini 3.1 Pro Preview',
      llm: 'gemini_3_1_pro_google',
      provider: GenerationProvider.gemini,
      billingMode: GenerationBillingMode.credits,
      creditCost: 12,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'gemini_3_1_pro_google',
    ),
  ];
}

const _codeLlmProfile = 'nova3d_code_generation';

const _anthropicOptions = [
  GenerationModelOption(
    id: 'anthropic_claude_fable_5',
    label: 'Claude Fable 5',
    llm: 'claude-fable',
    provider: GenerationProvider.anthropic,
    keyProvider: AiProvider.anthropic,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_fable_5_anthropic',
  ),
  GenerationModelOption(
    id: 'anthropic_claude_sonnet_5',
    label: 'Claude Sonnet 5',
    llm: 'claude-sonnet-5',
    provider: GenerationProvider.anthropic,
    keyProvider: AiProvider.anthropic,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_sonnet_5_anthropic',
  ),
  GenerationModelOption(
    id: 'anthropic_claude_sonnet',
    label: 'Claude Sonnet 4.6',
    llm: 'claude-sonnet',
    provider: GenerationProvider.anthropic,
    keyProvider: AiProvider.anthropic,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_sonnet_4_6_anthropic',
  ),
  GenerationModelOption(
    id: 'anthropic_claude_opus_4_8',
    label: 'Claude Opus 4.8',
    llm: 'claude-opus',
    provider: GenerationProvider.anthropic,
    keyProvider: AiProvider.anthropic,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_opus_4_8_anthropic',
  ),
];

const _openAiOption = GenerationModelOption(
  id: 'openai_gpt55',
  label: 'GPT-5.5',
  llm: 'gpt55',
  provider: GenerationProvider.openai,
  keyProvider: AiProvider.openai,
  workflowName: kSketchTo3dByokWorkflow,
  codeLlmProfile: _codeLlmProfile,
  codeLlmTier: 'gpt_5_5_openai',
);

const _openRouterOptions = [
  GenerationModelOption(
    id: 'openrouter_gpt56_sol',
    label: 'GPT-5.6 Sol',
    llm: 'gpt56-sol',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'gpt_5_6_sol_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_gpt56_terra',
    label: 'GPT-5.6 Terra',
    llm: 'gpt56-terra',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'gpt_5_6_terra_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_gpt56_luna',
    label: 'GPT-5.6 Luna',
    llm: 'gpt56-luna',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'gpt_5_6_luna_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_gpt55',
    label: 'GPT-5.5',
    llm: 'gpt55',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'gpt_5_5_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_gemini',
    label: 'Gemini 3.1 Pro Preview',
    llm: 'gemini',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'gemini_3_1_pro_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_claude_sonnet',
    label: 'Claude Sonnet 4.6',
    llm: 'claude-sonnet',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_sonnet_4_6_openrouter',
  ),
  GenerationModelOption(
    id: 'openrouter_claude_opus',
    label: 'Claude Opus 4.8',
    llm: 'claude-opus',
    provider: GenerationProvider.openrouter,
    keyProvider: AiProvider.openrouter,
    workflowName: kSketchTo3dByokWorkflow,
    codeLlmProfile: _codeLlmProfile,
    codeLlmTier: 'claude_opus_4_8_openrouter',
  ),
];

const _geminiOption = GenerationModelOption(
  id: 'gemini_gemini',
  label: 'Gemini 3.1 Pro Preview',
  llm: 'gemini',
  provider: GenerationProvider.gemini,
  keyProvider: AiProvider.gemini,
  workflowName: kSketchTo3dByokWorkflow,
  codeLlmProfile: _codeLlmProfile,
  codeLlmTier: 'gemini_3_1_pro_google',
);
