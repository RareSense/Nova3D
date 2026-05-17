import 'package:nova3d_frontend/features/cad/models/generation_request.dart';

enum MessageRole { user, assistant }

class MessageModel {
  final String id;
  final MessageRole role;
  final String text;
  final DateTime createdAt;
  final bool isStreaming;
  final String? modelUrl;
  final String? workflowId;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final String? modelOptionId;
  final String? instructionPrompt;
  // Shown as a thumbnail in the user bubble.
  final String? imageDataUrl;
  // Non-null on failed assistant messages — enables the retry button.
  final GenerationRequest? retryRequest;

  const MessageModel({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.isStreaming = false,
    this.modelUrl,
    this.workflowId,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.modelOptionId,
    this.instructionPrompt,
    this.imageDataUrl,
    this.retryRequest,
  });

  MessageModel copyWith({
    String? text,
    bool? isStreaming,
    String? modelUrl,
    String? workflowId,
    Map<String, dynamic>? modelArtifact,
    Map<String, dynamic>? codeArtifact,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>>? joints,
    String? modelOptionId,
    String? instructionPrompt,
    String? imageDataUrl,
    GenerationRequest? retryRequest,
    bool clearRetryRequest = false,
  }) => MessageModel(
    id: id,
    role: role,
    text: text ?? this.text,
    createdAt: createdAt,
    isStreaming: isStreaming ?? this.isStreaming,
    modelUrl: modelUrl ?? this.modelUrl,
    workflowId: workflowId ?? this.workflowId,
    modelArtifact: modelArtifact ?? this.modelArtifact,
    codeArtifact: codeArtifact ?? this.codeArtifact,
    jointsArtifact: jointsArtifact ?? this.jointsArtifact,
    joints: joints ?? this.joints,
    modelOptionId: modelOptionId ?? this.modelOptionId,
    instructionPrompt: instructionPrompt ?? this.instructionPrompt,
    imageDataUrl: imageDataUrl ?? this.imageDataUrl,
    retryRequest: clearRetryRequest
        ? null
        : (retryRequest ?? this.retryRequest),
  );

  // ── Local persistence (SharedPreferences) ─────────────────────────────────

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'role': role == MessageRole.user ? 'user' : 'assistant',
    'text': text,
    'created_at': createdAt.toIso8601String(),
    'is_streaming': isStreaming,
    if (modelUrl != null) 'model_url': modelUrl,
    if (workflowId != null) 'workflow_id': workflowId,
    if (modelArtifact != null) 'model_artifact': modelArtifact,
    if (codeArtifact != null) 'code_artifact': codeArtifact,
    if (jointsArtifact != null) 'joints_artifact': jointsArtifact,
    if (joints.isNotEmpty) 'joints': joints,
    if (modelOptionId != null) 'model_option_id': modelOptionId,
    if (instructionPrompt != null) 'instruction_prompt': instructionPrompt,
    if (imageDataUrl != null) 'image_data_url': imageDataUrl,
  };

  factory MessageModel.fromLocalJson(Map<String, dynamic> json) => MessageModel(
    id: json['id'] as String,
    role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
    text: (json['text'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    isStreaming: json['is_streaming'] == true,
    modelUrl: json['model_url'] as String?,
    workflowId: json['workflow_id'] as String?,
    modelArtifact: _asStringMap(json['model_artifact']),
    codeArtifact: _asStringMap(json['code_artifact']),
    jointsArtifact: _asStringMap(json['joints_artifact']),
    joints: _asStringMapList(json['joints']),
    modelOptionId: json['model_option_id'] as String?,
    instructionPrompt: json['instruction_prompt'] as String?,
    imageDataUrl: json['image_data_url'] as String?,
  );

  // ── Remote API response ───────────────────────────────────────────────────

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
    id: json['id'] as String,
    role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
    text: (json['content']?['text'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    modelUrl: json['content']?['model_url'] as String?,
    workflowId: json['content']?['workflow_id'] as String?,
    modelArtifact: _asStringMap(json['content']?['model_artifact']),
    codeArtifact: _asStringMap(json['content']?['code_artifact']),
    jointsArtifact: _asStringMap(json['content']?['joints_artifact']),
    joints: _asStringMapList(json['content']?['joints']),
    modelOptionId: json['content']?['model_option_id'] as String?,
    instructionPrompt: json['content']?['instruction_prompt'] as String?,
    imageDataUrl: json['content']?['image_data_url'] as String?,
  );

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Map<String, dynamic>> _asStringMapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
}
