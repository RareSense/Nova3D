// ── Workflow state ────────────────────────────────────────────────────────────

enum WorkflowState {
  pending,
  running,
  completed,
  budgetExhausted,
  failed,
  terminated,
  unknown;

  static WorkflowState parse(String? s) => switch (s?.toLowerCase()) {
    'pending' => pending,
    'running' => running,
    'completed' || 'succeeded' || 'success' => completed,
    'budget_exhausted' => budgetExhausted,
    'failed' => failed,
    'terminated' || 'cancelled' || 'timed_out' || 'timeout' => terminated,
    _ => unknown,
  };

  bool get isTerminal =>
      this == completed ||
      this == budgetExhausted ||
      this == failed ||
      this == terminated;
}

// ── GraphFlow readiness (from GET /workflow/readiness/sketch_to_3d) ───────────

class GenerationReadiness {
  const GenerationReadiness({
    required this.ready,
    this.reason,
    this.projectedCost = 0,
    this.authorizedBudget = 0,
  });

  final bool ready;
  final String? reason;
  final num projectedCost;
  final num authorizedBudget;

  factory GenerationReadiness.fromJson(Map<String, dynamic> json) =>
      GenerationReadiness(
        ready: json['ready'] == true,
        reason: json['reason'] as String?,
        projectedCost: json['projected_cost'] as num? ?? 0,
        authorizedBudget: json['authorized_budget'] as num? ?? 0,
      );

  String get userMessage {
    if (ready) return 'Generation is ready.';
    if (reason == 'generation_service_unavailable') {
      return 'The generation service is unavailable right now. Please try again shortly.';
    }
    return 'Generation is not available right now.';
  }
}

// ── Workflow status (from GET /status/<id>) ───────────────────────────────────

class WorkflowStatus {
  final String workflowId;
  final WorkflowState state;
  final String? currentNode;
  final String? lastExitNode;
  final int retryCount;

  const WorkflowStatus({
    required this.workflowId,
    required this.state,
    this.currentNode,
    this.lastExitNode,
    this.retryCount = 0,
  });

  static const _terminalNodes = {
    'success_final',
    'success_original_glb',
    'failed_final',
  };

  static const _nodeLabels = {
    'sketch_to_3d_generator': 'Generating your 3D model...',
    'regenerate_3d_part': 'Regenerating the selected part...',
    'add_3d_part': 'Adding a new part...',
    'articulate_3d_model': 'Articulating your 3D model...',
  };

  String get progressLabel {
    final node = currentNode ?? lastExitNode ?? '';
    return _nodeLabels[node] ?? 'Generating…';
  }

  bool get isTerminalByNode =>
      _terminalNodes.contains(currentNode) ||
      _terminalNodes.contains(lastExitNode);

  bool get isTerminal => state.isTerminal || isTerminalByNode;

  factory WorkflowStatus.fromJson(
    String workflowId,
    Map<String, dynamic> json,
  ) {
    final runtime = json['runtime'] as Map<String, dynamic>? ?? {};
    final visitSeq = json['node_visit_seq'] as Map<String, dynamic>? ?? {};

    return WorkflowStatus(
      workflowId: workflowId,
      state: WorkflowState.parse(runtime['state'] as String?),
      currentNode: visitSeq.keys.isNotEmpty ? visitSeq.keys.last : null,
      lastExitNode: runtime['last_exit_node_id'] as String?,
      retryCount: 0,
    );
  }
}

// ── CAD result (from GET /result/<id>) ────────────────────────────────────────

class CadResult {
  final String? glbUrl;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final int jointCount;
  final bool failed;
  final String? errorMessage;
  final String? errorCategory;
  final String? provider;
  final String? operation;
  final Map<String, dynamic>? cost;
  final bool retryable;

  const CadResult({
    this.glbUrl,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.jointCount = 0,
    required this.failed,
    this.errorMessage,
    this.errorCategory,
    this.provider,
    this.operation,
    this.cost,
    this.retryable = false,
  });

  factory CadResult.fromJson(Map<String, dynamic> json) {
    final payload = _extractGeneratorPayload(json);
    final glbUrl = payload == null ? null : _extractGlbUrl(payload);
    final modelArtifact = payload == null
        ? null
        : _extractModelArtifact(payload);
    final codeArtifact = payload == null ? null : _extractCodeArtifact(payload);
    final jointsArtifact = payload == null
        ? null
        : _extractJointsArtifact(payload);
    final joints = payload == null
        ? const <Map<String, dynamic>>[]
        : _extractJoints(payload);
    final jointCount = payload == null
        ? 0
        : (_intValue(_unwrapResult(payload)['joint_count']) ?? joints.length);
    final operation = payload == null
        ? null
        : _stringValue(_unwrapResult(payload)['operation']);
    final cost = payload == null
        ? null
        : _asStringMap(_unwrapResult(payload)['cost']);
    final failure = payload == null ? null : _extractFailure(payload);
    final errorMessage = failure?.message ?? _extractRootError(json);
    final failed = glbUrl == null && (_isFailed(json) || errorMessage != null);

    return CadResult(
      glbUrl: glbUrl,
      modelArtifact: modelArtifact,
      codeArtifact: codeArtifact,
      jointsArtifact: jointsArtifact,
      joints: joints,
      jointCount: jointCount,
      failed: failed,
      errorMessage: errorMessage,
      errorCategory: failure?.category,
      provider: failure?.provider,
      operation: operation,
      cost: cost,
      retryable: failure?.retryable ?? false,
    );
  }

  static Map<String, dynamic>? _extractGeneratorPayload(
    Map<String, dynamic> json,
  ) {
    for (final key in [
      'sketch_to_3d_generator',
      'regenerate_3d_part',
      'add_3d_part',
      'articulate_3d_model',
    ]) {
      final node = json[key];
      if (node is! List || node.isEmpty) continue;
      final first = node.first;
      if (first is Map) return _asStringMap(first);
    }
    return null;
  }

  static String? _extractGlbUrl(Map<String, dynamic> payload) {
    final unwrapped = _unwrapResult(payload);

    final modelUrl = unwrapped['model_url'] as String?;
    if (modelUrl != null && modelUrl.isNotEmpty) return modelUrl;

    for (final artifactKey in ['model', 'model_artifact']) {
      final artifact = unwrapped[artifactKey];
      if (artifact is Map) {
        final url = artifact['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _extractModelArtifact(
    Map<String, dynamic> payload,
  ) {
    final unwrapped = _unwrapResult(payload);
    for (final artifactKey in ['model_artifact', 'model']) {
      final artifact = _asStringMap(unwrapped[artifactKey]);
      if (artifact != null) return artifact;
    }
    return null;
  }

  static Map<String, dynamic>? _extractCodeArtifact(
    Map<String, dynamic> payload,
  ) {
    final unwrapped = _unwrapResult(payload);
    for (final artifactKey in [
      'code_artifact',
      'source_code_artifact',
      'input_code_artifact',
    ]) {
      final artifact = _asStringMap(unwrapped[artifactKey]);
      if (artifact != null) return artifact;
    }
    return null;
  }

  static Map<String, dynamic>? _extractJointsArtifact(
    Map<String, dynamic> payload,
  ) {
    final unwrapped = _unwrapResult(payload);
    return _asStringMap(unwrapped['joints_artifact']);
  }

  static List<Map<String, dynamic>> _extractJoints(
    Map<String, dynamic> payload,
  ) {
    final unwrapped = _unwrapResult(payload);
    final raw = unwrapped['joints'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (joint) => joint.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  static _FailureInfo? _extractFailure(Map<String, dynamic> payload) {
    final unwrapped = _unwrapResult(payload);
    final status = (unwrapped['status'] as String?)?.toLowerCase();
    final action = (unwrapped['action'] as String?)?.toLowerCase();
    final ok = unwrapped['ok'];
    final failureMap = _asStringMap(unwrapped['failure']);

    final failed =
        status == 'failed' ||
        action == 'error' ||
        ok == false ||
        failureMap != null ||
        unwrapped['error_category'] != null ||
        unwrapped['user_message'] != null;
    if (!failed) return null;

    final category =
        _stringValue(failureMap?['category']) ??
        _stringValue(unwrapped['error_category']);
    final provider =
        _stringValue(failureMap?['provider']) ??
        _stringValue(unwrapped['provider']);
    final retryable =
        _boolValue(failureMap?['retryable']) ??
        _boolValue(unwrapped['retryable']) ??
        false;

    final message =
        _stringValue(failureMap?['user_message']) ??
        _stringValue(failureMap?['message']) ??
        _stringValue(unwrapped['user_message']) ??
        _stringValue(unwrapped['message']) ??
        _stringValue(unwrapped['detail']) ??
        _stringValue(unwrapped['error']) ??
        _messageForCategory(category, provider, retryable);

    return _FailureInfo(
      message: message,
      category: category,
      provider: provider,
      retryable: retryable,
    );
  }

  static String? _extractRootError(Map<String, dynamic> json) {
    final error = json['error'] ?? json['detail'] ?? json['message'];
    if (error == null) return null;
    return _stringValue(error) ?? error.toString();
  }

  static Map<String, dynamic> _unwrapResult(Map<String, dynamic> payload) {
    final result = _asStringMap(payload['result']);
    return result ?? payload;
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is Map) {
      final userMessage = _stringValue(value['user_message']);
      if (userMessage != null) return userMessage;
      final message = _stringValue(value['message']);
      if (message != null) return message;
    }
    return value.toString();
  }

  static bool? _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _messageForCategory(
    String? category,
    String? provider,
    bool retryable,
  ) {
    final label = provider == null || provider.isEmpty
        ? 'The selected provider'
        : provider;
    return switch (category) {
      'invalid_api_key' =>
        '$label rejected this API key. Check the key in Settings or use another provider.',
      'missing_api_key' =>
        '$label is missing an API key. Add a key in Settings and try again.',
      'model_access_denied' =>
        '$label does not allow this key to use the selected model. Choose another model or provider key.',
      'unsupported_provider_for_model' =>
        '$label cannot run the selected model. Choose a compatible model/provider pair.',
      'insufficient_credits' =>
        '$label does not have enough credits or balance for this generation.',
      'quota_or_rate_limit' =>
        '$label quota or rate limit was reached. Wait a bit or use another provider key.',
      'provider_unavailable' =>
        '$label is temporarily unavailable or overloaded. Retry shortly or switch providers.',
      'api_timeout' =>
        '$label timed out while generating. Retry or switch providers.',
      'blender_generation_failed' =>
        'The generated 3D script could not produce a valid model after automatic repair attempts.',
      'artifact_upload_failed' =>
        'The model was generated, but Nova3D could not prepare the download artifact.',
      'generation_timeout' =>
        'Generation took longer than expected. It may still finish later; retry if it does not appear in history.',
      _ =>
        retryable
            ? 'Generation failed. Retry shortly or switch providers.'
            : 'Generation failed. Try another prompt, model, or provider key.',
    };
  }

  static bool _isFailed(Map<String, dynamic> json) {
    final state = (json['state'] as String?)?.toLowerCase();
    if (state == 'failed' || state == 'failure') return true;
    final runtime = json['runtime'] as Map<String, dynamic>?;
    final rState = (runtime?['state'] as String?)?.toLowerCase();
    if (rState == 'failed' ||
        rState == 'failure' ||
        rState == 'budget_exhausted') {
      return true;
    }
    return false;
  }
}

class _FailureInfo {
  const _FailureInfo({
    required this.message,
    this.category,
    this.provider,
    this.retryable = false,
  });

  final String message;
  final String? category;
  final String? provider;
  final bool retryable;
}

// ── Credits (from GET /api/credits/balance/me) ────────────────────────────────

class CadCredits {
  final int balance;
  final int available;

  const CadCredits({required this.balance, required this.available});

  factory CadCredits.fromJson(Map<String, dynamic> json) => CadCredits(
    balance: (json['balance'] as num).toInt(),
    available: (json['available'] as num).toInt(),
  );
}
