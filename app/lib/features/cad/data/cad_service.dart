import 'package:dio/dio.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/errors.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_service.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';

class CadException implements Exception {
  CadException(this.message);
  final String message;

  AppError toAppError() =>
      AppError(message, kind: AppErrorKind.network, cause: this);

  @override
  String toString() => message;
}

class CadService {
  static const _startReceiveTimeout = Duration(minutes: 2);
  static const _resultReceiveTimeout = Duration(minutes: 5);

  CadService(this._auth, this._apiKeys) {
    _dio = Dio(
      BaseOptions(
        baseUrl: kCadBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  final AuthService _auth;
  final ApiKeyService _apiKeys;
  late final Dio _dio;

  static String createWorkflowId() =>
      'state-${DateTime.now().microsecondsSinceEpoch}';

  Future<Options> _authOptions({Duration? receiveTimeout}) async {
    final token = await _auth.getToken();
    if (token == null) throw AuthException('Please sign in again.');
    return Options(
      headers: {'Authorization': 'Bearer $token'},
      receiveTimeout: receiveTimeout,
    );
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['error'] ?? data['message'];
      if (detail != null) {
        final message = detail.toString();
        if (e.response?.statusCode == 402) {
          return _creditFailureMessage(message);
        }
        if (e.response?.statusCode == 401) {
          return message.toLowerCase().contains('expired')
              ? 'Your session expired. Please sign in again.'
              : 'GraphFlow rejected the current sign-in token. Please sign out and sign in again.';
        }
        return message;
      }
    }
    if (e.response?.statusCode == 402) {
      return _creditFailureMessage(null);
    }
    if (e.response?.statusCode == 401) {
      return 'GraphFlow rejected the current sign-in token. Please sign out and sign in again.';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Generation is still starting. Nova3D will keep checking for the result.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'The generation service is unavailable right now. Please try again shortly.';
    }
    return 'Request failed (${e.response?.statusCode})';
  }

  String _creditFailureMessage(String? detail) {
    final text = detail ?? '';
    final required = RegExp(
      r'Required(?: authorization)?:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    final available = RegExp(
      r'Available:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    if (required != null && available != null) {
      return 'This model needs $required credits, but you have $available available. Buy more credits at /subscription and try again.';
    }
    return 'You do not have enough Nova3D credits for this model. Buy more credits at /subscription and try again.';
  }

  Future<GenerationReadiness> checkReadiness() async {
    try {
      return checkReadinessForWorkflow(kSketchTo3dPaidWorkflow);
    } on AuthException catch (e) {
      throw CadException(e.message);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  Future<GenerationReadiness> checkReadinessForWorkflow(
    String workflowName,
  ) async {
    try {
      final resp = await _dio.get(
        '/workflow/readiness/$workflowName',
        options: await _authOptions(),
      );
      return GenerationReadiness.fromJson(resp.data as Map<String, dynamic>);
    } on AuthException catch (e) {
      throw CadException(e.message);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  Future<GenerationCreditEstimate> estimateGenerationCredits(
    GenerationModelOption modelOption,
  ) async {
    if (!modelOption.isPaidCredit) {
      return const GenerationCreditEstimate(
        projectedMaxHold: 0,
        authorizedBudget: 0,
      );
    }
    try {
      final resp = await _dio.post(
        '/credits/estimate',
        data: {
          'workflow_name': modelOption.workflowName ?? kSketchTo3dPaidWorkflow,
          'num_variations': 1,
          'pricing_context': _paidPricingContext(modelOption),
        },
        options: await _authOptions(),
      );
      return GenerationCreditEstimate.fromJson(
        resp.data as Map<String, dynamic>,
      );
    } on AuthException catch (e) {
      throw CadException(e.message);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  /// Preflight estimate for a HOSTED (no caller key) `texture_3d_v2` run.
  ///
  /// Sends the same key-absent `pricing_context` the run itself will match
  /// (`gemini_api_key: ''`), so the returned hold equals the workflow-level
  /// hosted price from the tenant billing policy. BYOK runs (key provided)
  /// cost 0 credits and must skip this call — mirroring how BYOK generations
  /// skip [estimateGenerationCredits].
  Future<GenerationCreditEstimate> estimateTextureCredits() async {
    try {
      final resp = await _dio.post(
        '/credits/estimate',
        data: {
          'workflow_name': kTexture3dWorkflow,
          'num_variations': 1,
          'pricing_context': {'gemini_api_key': ''},
        },
        options: await _authOptions(),
      );
      return GenerationCreditEstimate.fromJson(
        resp.data as Map<String, dynamic>,
      );
    } on AuthException catch (e) {
      throw CadException(e.message);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  Future<String> startGeneration(
    GenerationRequest request, {
    String? workflowId,
    String? conversationId,
  }) async {
    final workflowName = _initialGenerationWorkflow(request.modelOption);
    final readiness = await checkReadinessForWorkflow(workflowName);
    if (!readiness.ready) throw CadException(readiness.userMessage);
    final requestedWorkflowId = workflowId ?? createWorkflowId();

    try {
      final response = await _dio.post(
        '/run/state/$workflowName',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': await _generationPayload(request, workflowName),
          'return_nodes': _generationReturnNodes(workflowName),
          if (conversationId != null)
            'conversation': _conversationLink(
              conversationId,
              relationType: 'initial_generation',
              operation: workflowName,
            ),
        },
        options: await _authOptions(receiveTimeout: _startReceiveTimeout),
      );
      final returnedWorkflowId = response.data['workflow_id'] as String?;
      if (returnedWorkflowId == null || returnedWorkflowId.isEmpty) {
        throw CadException('Generation did not return a workflow id.');
      }
      return returnedWorkflowId;
    } on DioException catch (e) {
      if (_mayHaveStarted(e)) {
        return requestedWorkflowId;
      }
      throw CadException(_errorMessage(e));
    }
  }

  String _initialGenerationWorkflow(GenerationModelOption option) =>
      option.workflowName ??
      (option.isPaidCredit ? kSketchTo3dPaidWorkflow : kSketchTo3dByokWorkflow);

  List<String> _generationReturnNodes(String workflowName) {
    if (workflowName == kSketchTo3dByokWorkflow) {
      return [
        'final_validated_correction',
        'final_latest_valid',
        'fail_generation',
        'require_byok_api_key',
      ];
    }
    return [
      'final_validated_correction',
      'final_latest_valid',
      'fail_generation',
    ];
  }

  Future<Map<String, dynamic>> _generationPayload(
    GenerationRequest request,
    String workflowName,
  ) async {
    if (request.modelOption.isPaidCredit) {
      return {
        'prompt': request.prompt.trim(),
        ..._paidPricingContext(request.modelOption),
        // Paid generations intentionally omit provider API keys. The toolkit
        // resolves provider credentials from the server environment.
        if (request.hasImage) ...{
          'has_reference_images': true,
          'image_artifact': request.imageDataUrls,
        },
      };
    }

    if (workflowName != kSketchTo3dByokWorkflow) {
      throw CadException(
        'This provider-key model is not configured for BYOK v2 generation.',
      );
    }
    final apiKey = await _apiKeyFor(request.modelOption);
    return {
      'prompt': request.prompt.trim(),
      'code_llm_profile':
          request.modelOption.codeLlmProfile ?? 'nova3d_code_generation',
      'code_llm_tier':
          request.modelOption.codeLlmTier ?? request.modelOption.llm,
      'code_llm_provider': request.modelOption.payloadProvider,
      'code_llm_api_key': apiKey,
      if (request.hasImage) ...{
        'has_reference_images': true,
        'image_artifact': request.imageDataUrls,
      },
    };
  }

  Map<String, dynamic> _paidPricingContext(GenerationModelOption option) => {
    'code_llm_profile': option.codeLlmProfile ?? 'nova3d_code_generation',
    'code_llm_tier': option.codeLlmTier ?? option.llm,
  };

  Future<String> startRegeneratePart({
    required Map<String, dynamic> codeArtifact,
    required String description,
    required GenerationModelOption modelOption,
    String? partType,
    String? workflowId,
    String? conversationId,
  }) {
    return _startEditWorkflow(
      workflow: kRegenerate3dPartWorkflow,
      returnNode: 'regenerate_3d_part',
      workflowId: workflowId,
      conversationId: conversationId,
      modelOption: modelOption,
      payload: {
        'code_artifact': codeArtifact,
        'description': description.trim(),
        'part_type': (partType == null || partType.trim().isEmpty)
            ? 'selected part'
            : partType.trim(),
      },
    );
  }

  Future<String> startAddPart({
    required Map<String, dynamic> codeArtifact,
    required String description,
    required GenerationModelOption modelOption,
    String? workflowId,
    String? conversationId,
  }) {
    return _startEditWorkflow(
      workflow: kAdd3dPartWorkflow,
      returnNode: 'add_3d_part',
      workflowId: workflowId,
      conversationId: conversationId,
      modelOption: modelOption,
      payload: {
        'code_artifact': codeArtifact,
        'description': description.trim(),
      },
    );
  }

  Future<String> startArticulation({
    required Map<String, dynamic> codeArtifact,
    required GenerationModelOption modelOption,
    Map<String, dynamic>? modelArtifact,
    String? modelUrl,
    String? instructionPrompt,
    String? articulationRequest,
    List<String> selectedMeshes = const [],
    List<String> screenshots = const [],
    String? workflowId,
    String? conversationId,
  }) async {
    final rawModelUrl = modelUrl?.trim();
    final cleanModelUrl =
        (rawModelUrl == null || rawModelUrl.startsWith('blob:'))
        ? null
        : rawModelUrl;
    if (modelArtifact == null &&
        (cleanModelUrl == null || cleanModelUrl.isEmpty)) {
      throw CadException(
        'This model does not include a source GLB artifact yet. Generate or edit it again before articulating.',
      );
    }

    final requestedWorkflowId = workflowId ?? createWorkflowId();
    try {
      final apiKey = await _apiKeyFor(modelOption);
      final payload = <String, dynamic>{
        'code_artifact': codeArtifact,
        if (cleanModelUrl != null && cleanModelUrl.isNotEmpty)
          'model_url': cleanModelUrl,
        if ((instructionPrompt ?? '').trim().isNotEmpty)
          'instruction_prompt': instructionPrompt!.trim(),
        if ((articulationRequest ?? '').trim().isNotEmpty)
          'articulation_request': articulationRequest!.trim(),
        if (selectedMeshes.isNotEmpty) 'selected_meshes': selectedMeshes,
        if (screenshots.isNotEmpty) 'screenshots': screenshots,
        'llm': modelOption.llm,
        'provider': modelOption.payloadProvider,
        'api_key': apiKey,
      };
      if (modelArtifact != null) payload['model_artifact'] = modelArtifact;

      final response = await _dio.post(
        '/run/state/$kArticulate3dModelWorkflow',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': payload,
          'return_nodes': ['articulate_3d_model'],
          if (conversationId != null)
            'conversation': _conversationLink(
              conversationId,
              relationType: 'articulate_model',
              operation: kArticulate3dModelWorkflow,
            ),
        },
        options: await _authOptions(receiveTimeout: _startReceiveTimeout),
      );
      final returnedWorkflowId = response.data['workflow_id'] as String?;
      if (returnedWorkflowId == null || returnedWorkflowId.isEmpty) {
        throw CadException(
          'Articulation workflow did not return a workflow id.',
        );
      }
      return returnedWorkflowId;
    } on DioException catch (e) {
      if (_mayHaveStarted(e)) return requestedWorkflowId;
      throw CadException(_errorMessage(e));
    }
  }

  Future<String> _startEditWorkflow({
    required String workflow,
    required String returnNode,
    required Map<String, dynamic> payload,
    required GenerationModelOption modelOption,
    String? workflowId,
    String? conversationId,
  }) async {
    if ((payload['description'] as String? ?? '').isEmpty) {
      throw CadException('Describe the edit you want to make.');
    }
    final requestedWorkflowId = workflowId ?? createWorkflowId();

    try {
      final apiKey = await _apiKeyFor(modelOption);
      final response = await _dio.post(
        '/run/state/$workflow',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': {
            ...payload,
            'llm': modelOption.llm,
            'provider': modelOption.payloadProvider,
            // TODO(security): remove once backend retrieves keys server-side
            // per user session instead of receiving them in the request body.
            'api_key': apiKey,
          },
          'return_nodes': [returnNode],
          if (conversationId != null)
            'conversation': _conversationLink(
              conversationId,
              relationType: workflow,
              operation: workflow,
            ),
        },
        options: await _authOptions(receiveTimeout: _startReceiveTimeout),
      );
      final returnedWorkflowId = response.data['workflow_id'] as String?;
      if (returnedWorkflowId == null || returnedWorkflowId.isEmpty) {
        throw CadException('Edit workflow did not return a workflow id.');
      }
      return returnedWorkflowId;
    } on DioException catch (e) {
      if (_mayHaveStarted(e)) return requestedWorkflowId;
      throw CadException(_errorMessage(e));
    }
  }

  // ── UV maps ────────────────────────────────────────────────────────────────
  // Derives game-ready UV atlases from a version's source CODE (never a GLB).
  // Independent of the edit workflows: no model option / provider key, and it
  // never produces an asset version — the result is a download attached to the
  // current version's code_artifact.

  Future<String> startUvMaps({
    required Map<String, dynamic> codeArtifact,
    String atlasMode = 'budget',
    int? maxAtlases,
    String? workflowId,
    String? conversationId,
  }) async {
    final requestedWorkflowId = workflowId ?? createWorkflowId();
    try {
      final response = await _dio.post(
        '/run/state/$kGenerateUvMapsWorkflow',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': {
            'code_artifact': codeArtifact,
            'atlas_mode': atlasMode,
            'max_atlases': ?maxAtlases,
          },
          'return_nodes': ['uv_unwrap'],
          if (conversationId != null)
            'conversation': _conversationLink(
              conversationId,
              relationType: kGenerateUvMapsWorkflow,
              operation: kGenerateUvMapsWorkflow,
            ),
        },
        options: await _authOptions(receiveTimeout: _startReceiveTimeout),
      );
      final returnedWorkflowId = response.data['workflow_id'] as String?;
      if (returnedWorkflowId == null || returnedWorkflowId.isEmpty) {
        throw CadException('UV map workflow did not return a workflow id.');
      }
      return returnedWorkflowId;
    } on DioException catch (e) {
      if (_mayHaveStarted(e)) return requestedWorkflowId;
      throw CadException(_errorMessage(e));
    }
  }

  // Mirrors runWorkflow's gentle poll, but parses the uv_unwrap node output.
  // Kept separate so the generation/edit path stays byte-for-byte unchanged.
  Future<UvMapsResult> runUvMapsWorkflow(
    String workflowId, {
    void Function(WorkflowStatus status)? onProgress,
  }) async {
    while (true) {
      await Future.delayed(const Duration(seconds: 3));
      final WorkflowStatus status;
      try {
        status = await getStatus(workflowId);
      } on CadException catch (e) {
        if (_isRecoverableWorkflowLookupError(e)) {
          onProgress?.call(
            WorkflowStatus(
              workflowId: workflowId,
              state: WorkflowState.pending,
              currentNode: 'uv_unwrap',
            ),
          );
          continue;
        }
        rethrow;
      }
      onProgress?.call(status);
      if (status.isTerminal) {
        if (status.state == WorkflowState.budgetExhausted) {
          throw CadException(
            'Your generation budget was exhausted before UV maps completed.',
          );
        }
        break;
      }
    }

    while (true) {
      try {
        final resp = await _dio.get(
          '/result/$workflowId',
          options: await _authOptions(receiveTimeout: _resultReceiveTimeout),
        );
        return UvMapsResult.fromResultJson(resp.data as Map<String, dynamic>);
      } on DioException catch (e) {
        final ex = CadException(_errorMessage(e));
        if (!_isRecoverableWorkflowLookupError(ex)) throw ex;
        onProgress?.call(
          WorkflowStatus(
            workflowId: workflowId,
            state: WorkflowState.running,
            currentNode: 'uv_unwrap',
          ),
        );
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  // Produce BOTH packings the UV tab shows in one action: a single combined
  // sheet (everything, max_atlases=1) plus the per-hierarchy-group sheets. Run
  // in parallel so the wall time is one unwrap, not two. Shared by the tab and
  // the full-screen editor button so the behavior is identical.
  Future<List<UvMapsSet>> runUvMapsBundle({
    required Map<String, dynamic> codeArtifact,
    void Function(String message)? onProgress,
    String? conversationId,
  }) async {
    final base = createWorkflowId();

    Future<UvMapsResult> run(String mode, int? maxAtlases, String suffix, String phase) async {
      final wf = await startUvMaps(
        codeArtifact: codeArtifact,
        atlasMode: mode,
        maxAtlases: maxAtlases,
        workflowId: '$base-$suffix',
        conversationId: conversationId,
      );
      return runUvMapsWorkflow(
        wf,
        onProgress: (s) => onProgress?.call('$phase — ${s.progressLabel}'),
      );
    }

    final results = await Future.wait([
      run('budget', 1, 'combined', 'Combined atlas'),
      run('group', null, 'groups', 'Per-group atlases'),
    ]);
    return [
      UvMapsSet(label: 'Combined', result: results[0]),
      UvMapsSet(label: 'Per-group', result: results[1]),
    ];
  }

  // ── Texturing ────────────────────────────────────────────────────────────
  // PBR-textures an existing generation via `texture_3d_v2`. The Gemini key is
  // optional: with a caller key the run is BYOK and costs 0 credits; without
  // one it runs on Nova3D's key and the tenant billing policy charges a
  // workflow-level credit price (see [estimateTextureCredits] — the credit
  // preflight lives in the chat provider, mirroring paid generations). It
  // targets the ORIGINAL generation's geometry via its `glb_artifact` +
  // `code_artifact`, never an AI-edited derivative. Kept separate so the
  // generation path stays byte-for-byte unchanged.

  static const _textureReturnNodes = <String>[
    'final_textured',
    'fail_texture_plan',
    'fail_texture_paint',
    'fail_texture_bake',
    'fail_pbr_derive',
    'fail_texture_apply',
  ];

  Future<String> startTexture({
    required Map<String, dynamic> glbArtifact,
    required Map<String, dynamic> codeArtifact,
    required TextureRequest request,
    String? workflowId,
    String? conversationId,
  }) async {
    final requestedWorkflowId = workflowId ?? createWorkflowId();
    try {
      final response = await _dio.post(
        '/run/state/$kTexture3dWorkflow',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': request.toPayload(
            glbArtifact: glbArtifact,
            codeArtifact: codeArtifact,
          ),
          'return_nodes': _textureReturnNodes,
          if (conversationId != null)
            'conversation': _conversationLink(
              conversationId,
              relationType: 'texture_model',
              operation: kTexture3dWorkflow,
            ),
        },
        options: await _authOptions(receiveTimeout: _startReceiveTimeout),
      );
      final returnedWorkflowId = response.data['workflow_id'] as String?;
      if (returnedWorkflowId == null || returnedWorkflowId.isEmpty) {
        throw CadException('Texturing did not return a workflow id.');
      }
      return returnedWorkflowId;
    } on DioException catch (e) {
      if (_mayHaveStarted(e)) return requestedWorkflowId;
      throw CadException(_errorMessage(e));
    }
  }

  // Mirrors [runWorkflow]'s gentle 3s poll, but parses the `final_textured`
  // node output. Kept separate so the generation result parser stays untouched.
  Future<TextureResult> runTextureWorkflow(
    String workflowId, {
    void Function(WorkflowStatus status)? onProgress,
    int? startupGraceRetries,
  }) async {
    await _awaitTerminalStatus(
      workflowId,
      startNode: 'material_groups',
      budgetMessage:
          'Your generation budget was exhausted before texturing completed.',
      startupGraceRetries: startupGraceRetries ?? _maxStartupLookupRetries,
      onProgress: onProgress,
    );

    for (var attempt = 1; ; attempt++) {
      try {
        final resp = await _dio.get(
          '/result/$workflowId',
          options: await _authOptions(receiveTimeout: _resultReceiveTimeout),
        );
        return TextureResult.fromResultJson(resp.data as Map<String, dynamic>);
      } on DioException catch (e) {
        final ex = CadException(_errorMessage(e));
        // The workflow is already terminal here, so /result errors can only be
        // transient — or permanent for a run that closed by raising. Bounded
        // retries keep the transient case working without the permanent case
        // polling forever.
        if (!_isRecoverableWorkflowLookupError(ex) ||
            attempt >= _maxResultFetchRetries) {
          throw ex;
        }
        onProgress?.call(
          WorkflowStatus(
            workflowId: workflowId,
            state: WorkflowState.running,
            currentNode: 'texture_apply',
          ),
        );
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<String> _apiKeyFor(GenerationModelOption option) async {
    final keyProvider = option.keyProvider;
    if (keyProvider == null) {
      throw CadException('This model uses Nova3D credits, not provider keys.');
    }
    final keys = await _apiKeys.loadValidKeys();
    final apiKey = keys[keyProvider.id];
    if (apiKey == null || apiKey.isEmpty) {
      throw CadException('Add a ${keyProvider.label} key in Settings.');
    }
    return apiKey;
  }

  Future<WorkflowStatus> getStatus(String workflowId) async {
    try {
      final resp = await _dio.get(
        '/status/$workflowId',
        options: await _authOptions(),
      );
      return WorkflowStatus.fromJson(
        workflowId,
        resp.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  Future<CadResult> getResult(String workflowId) async {
    try {
      final resp = await _dio.get(
        '/result/$workflowId',
        options: await _authOptions(receiveTimeout: _resultReceiveTimeout),
      );
      return CadResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  // Bounded startup grace: how many consecutive "workflow not found" status
  // lookups to tolerate before a NEVER-observed-alive workflow is treated as a
  // failed launch (≈ this many × 3s). A FRESH start needs headroom while the
  // workflow registers; a RESUME of a prior-session workflow uses a much
  // smaller grace ([resumeStartupGraceRetries]) because "not found" there means
  // the run has already closed, not that it is still starting.
  static const _maxStartupLookupRetries = 40;
  static const resumeStartupGraceRetries = 2;

  // /result retries after the workflow is already terminal (≈ 1 minute). A run
  // that closed by raising never yields a /result — without a bound the fetch
  // loop would poll forever (the state-…718200000 stuck-UI bug, second half).
  static const _maxResultFetchRetries = 20;

  /// Polls `/status` every 3s until the workflow reaches a terminal state, then
  /// returns so the caller can fetch `/result`. Throws [CadException] on budget
  /// exhaustion or an unrecoverable error.
  ///
  /// Critical failure case: a workflow that fails by RAISING (e.g.
  /// `texture_3d_v2`'s hard-fail nodes) is CLOSED on Temporal, so `/status` can
  /// no longer be queried and returns "workflow not found". That lookup error is
  /// otherwise treated as "still starting" and would poll forever. Once the
  /// workflow has been seen alive, a subsequent persistent lookup failure means
  /// it has CLOSED — we return so the caller's `/result` fetch surfaces the real
  /// (failed) outcome instead of the UI spinning indefinitely.
  Future<void> _awaitTerminalStatus(
    String workflowId, {
    required String startNode,
    required String budgetMessage,
    int startupGraceRetries = _maxStartupLookupRetries,
    void Function(WorkflowStatus status)? onProgress,
  }) async {
    var observedAlive = false;
    var consecutiveLookupFailures = 0;
    while (true) {
      await Future.delayed(const Duration(seconds: 3));
      final WorkflowStatus status;
      try {
        status = await getStatus(workflowId);
      } on CadException catch (e) {
        if (!_isRecoverableWorkflowLookupError(e)) rethrow;
        consecutiveLookupFailures++;
        // Seen alive before, now unreachable → the workflow closed
        // (failed/terminated). Stop; the caller's /result reports the outcome.
        if (observedAlive && consecutiveLookupFailures >= 2) return;
        // Never seen alive → bounded startup grace, then give up loudly.
        if (!observedAlive && consecutiveLookupFailures > startupGraceRetries) {
          rethrow;
        }
        onProgress?.call(
          WorkflowStatus(
            workflowId: workflowId,
            state: WorkflowState.pending,
            currentNode: startNode,
          ),
        );
        continue;
      }
      observedAlive = true;
      consecutiveLookupFailures = 0;
      onProgress?.call(status);
      if (status.isTerminal) {
        if (status.state == WorkflowState.budgetExhausted) {
          throw CadException(budgetMessage);
        }
        return;
      }
    }
  }

  // GraphFlow generations commonly take several minutes. Poll gently so
  // multiple browser chats can run in parallel without hammering the backend.
  Future<CadResult> runWorkflow(
    String workflowId, {
    void Function(WorkflowStatus status)? onProgress,
    int? startupGraceRetries,
  }) async {
    await _awaitTerminalStatus(
      workflowId,
      startNode: 'sketch_to_3d_generator',
      budgetMessage:
          'Your provider or generation budget was exhausted before the model completed.',
      startupGraceRetries: startupGraceRetries ?? _maxStartupLookupRetries,
      onProgress: onProgress,
    );

    for (var attempt = 1; ; attempt++) {
      try {
        return await getResult(workflowId);
      } on CadException catch (e) {
        // Terminal workflow: bounded retries (see runTextureWorkflow).
        if (!_isRecoverableWorkflowLookupError(e) ||
            attempt >= _maxResultFetchRetries) {
          rethrow;
        }
        onProgress?.call(
          WorkflowStatus(
            workflowId: workflowId,
            state: WorkflowState.running,
            currentNode: 'sketch_to_3d_generator',
          ),
        );
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  bool _mayHaveStarted(DioException e) =>
      e.type == DioExceptionType.receiveTimeout;

  bool _isRecoverableWorkflowLookupError(CadException e) {
    final message = e.message.toLowerCase();
    if (message.contains('sign in') || message.contains('token')) return false;
    if (message.contains('budget was exhausted')) return false;
    return message.contains('404') ||
        message.contains('workflow not found') ||
        message.contains('unavailable') ||
        message.contains('still starting') ||
        message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('request failed (null)') ||
        message.contains('request failed (502)') ||
        message.contains('request failed (503)') ||
        message.contains('request failed (504)');
  }

  Map<String, dynamic> _conversationLink(
    String conversationId, {
    required String relationType,
    required String operation,
  }) => {
    'conversation_id': conversationId,
    'relation_type': relationType,
    'link_metadata': {'operation': operation, 'client': 'flutter'},
  };
}
