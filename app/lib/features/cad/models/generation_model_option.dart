import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';

enum GenerationProvider {
  anthropic('anthropic', 'Anthropic'),
  openrouter('openrouter', 'OpenRouter');

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
    return null;
  }

  String get compactLabel => label;

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
    if ((keys[AiProvider.openrouter.id] ?? '').isNotEmpty) {
      options.addAll(_openRouterOptions);
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
    GenerationModelOption? fableByok;
    GenerationModelOption? first;
    for (final option in options) {
      first ??= option;
      if (option.id == 'credits_claude_fable_5_anthropic') return option;
      if (option.id == 'anthropic_claude_fable_5') fableByok = option;
    }
    return fableByok ?? first;
  }

  static const paidCreditOptions = [
    GenerationModelOption(
      id: 'credits_claude_opus_5_openrouter',
      label: 'Claude Opus 5',
      llm: 'claude_opus_5_anthropic',
      provider: GenerationProvider.anthropic,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'claude_opus_5_anthropic',
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
      id: 'credits_kimi_k3_openrouter',
      label: 'Kimi K3',
      llm: 'kimi_k3_openrouter',
      provider: GenerationProvider.openrouter,
      billingMode: GenerationBillingMode.credits,
      creditCost: 40,
      workflowName: kSketchTo3dPaidWorkflow,
      codeLlmProfile: _codeLlmProfile,
      codeLlmTier: 'kimi_k3_openrouter',
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
];

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
];
