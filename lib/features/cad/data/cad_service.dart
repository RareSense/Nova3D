import 'package:dio/dio.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/api_keys/data/api_key_service.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';

class CadException implements Exception {
  CadException(this.message);
  final String message;

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
        if (e.response?.statusCode == 401) {
          return message.toLowerCase().contains('expired')
              ? 'Your session expired. Please sign in again.'
              : 'GraphFlow rejected the current sign-in token. Please sign out and sign in again.';
        }
        return message;
      }
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

  Future<GenerationReadiness> checkReadiness() async {
    try {
      final resp = await _dio.get(
        '/workflow/readiness/$kSketchTo3dWorkflow',
        options: await _authOptions(),
      );
      return GenerationReadiness.fromJson(resp.data as Map<String, dynamic>);
    } on AuthException catch (e) {
      throw CadException(e.message);
    } on DioException catch (e) {
      throw CadException(_errorMessage(e));
    }
  }

  Future<String> startGeneration(
    GenerationRequest request, {
    String? workflowId,
  }) async {
    final readiness = await checkReadiness();
    if (!readiness.ready) throw CadException(readiness.userMessage);
    final requestedWorkflowId = workflowId ?? createWorkflowId();

    try {
      final apiKey = await _apiKeyFor(request.modelOption);
      final response = await _dio.post(
        '/run/state/$kSketchTo3dWorkflow',
        queryParameters: {'request_id': requestedWorkflowId},
        data: {
          'payload': {
            'prompt': request.prompt.trim(),
            'llm': request.modelOption.llm,
            'provider': request.modelOption.payloadProvider,
            'api_key': apiKey,
            'validate': false,
            if (request.hasImage) ...{
              // Send plain base64 so GraphFlow passes it through to the tool.
              // data: URLs are normalized to CAS artifacts before tool execution.
              'image_base64': request.imageBase64Payload,
              'image_mime': request.imageMime,
            },
          },
          'return_nodes': ['sketch_to_3d_generator'],
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

  Future<String> startRegeneratePart({
    required Map<String, dynamic> codeArtifact,
    required String description,
    required GenerationModelOption modelOption,
    String? partType,
    String? workflowId,
  }) {
    return _startEditWorkflow(
      workflow: kRegenerate3dPartWorkflow,
      returnNode: 'regenerate_3d_part',
      workflowId: workflowId,
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
  }) {
    return _startEditWorkflow(
      workflow: kAdd3dPartWorkflow,
      returnNode: 'add_3d_part',
      workflowId: workflowId,
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
            'api_key': apiKey,
          },
          'return_nodes': [returnNode],
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

  Future<String> _apiKeyFor(GenerationModelOption option) async {
    final keys = await _apiKeys.loadValidKeys();
    final apiKey = keys[option.keyProvider.id];
    if (apiKey == null || apiKey.isEmpty) {
      throw CadException('Add a ${option.keyProvider.label} key in Settings.');
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

  // GraphFlow generations commonly take several minutes. Poll gently so
  // multiple browser chats can run in parallel without hammering the backend.
  Future<CadResult> runWorkflow(
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
              currentNode: 'sketch_to_3d_generator',
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
            'Your provider or generation budget was exhausted before the model completed.',
          );
        }
        break;
      }
    }

    while (true) {
      try {
        return await getResult(workflowId);
      } on CadException catch (e) {
        if (!_isRecoverableWorkflowLookupError(e)) rethrow;
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
}
