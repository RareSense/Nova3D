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
  final String? messageType;
  final String? operation;
  final String? sourceModelUrl;
  final String? modelOptionId;
  final String? modelLabel;
  final String? instructionPrompt;
  // Shown as a thumbnail in the user bubble.
  final String? imageDataUrl;
  final List<String> imageDataUrls;
  // Downloadable assets (GLB/maps/tiles/atlases/UV layouts/settings) from a
  // texture run, each a JSON map {folder, name, url, content?, label}. Powers
  // the PBR tab in the result view.
  final List<Map<String, dynamic>> textureAssets;
  // Soft delete: a deleted message stays in every store (local + remote DB)
  // but is never rendered. Monotonic — there is no undelete path, which is
  // what makes the remote-merge rule safe (deletion always wins).
  final DateTime? deletedAt;
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
    this.messageType,
    this.operation,
    this.sourceModelUrl,
    this.modelOptionId,
    this.modelLabel,
    this.instructionPrompt,
    this.imageDataUrl,
    this.imageDataUrls = const [],
    this.textureAssets = const [],
    this.deletedAt,
    this.retryRequest,
  });

  bool get isDeleted => deletedAt != null;

  List<String> get allImageDataUrls {
    if (imageDataUrls.isNotEmpty) return imageDataUrls;
    final dataUrl = imageDataUrl;
    if (dataUrl == null || dataUrl.isEmpty) return const [];
    return [dataUrl];
  }

  MessageModel copyWith({
    String? text,
    bool? isStreaming,
    String? modelUrl,
    String? workflowId,
    Map<String, dynamic>? modelArtifact,
    Map<String, dynamic>? codeArtifact,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>>? joints,
    String? messageType,
    String? operation,
    String? sourceModelUrl,
    String? modelOptionId,
    String? modelLabel,
    String? instructionPrompt,
    String? imageDataUrl,
    List<String>? imageDataUrls,
    List<Map<String, dynamic>>? textureAssets,
    DateTime? deletedAt,
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
    messageType: messageType ?? this.messageType,
    operation: operation ?? this.operation,
    sourceModelUrl: sourceModelUrl ?? this.sourceModelUrl,
    modelOptionId: modelOptionId ?? this.modelOptionId,
    modelLabel: modelLabel ?? this.modelLabel,
    instructionPrompt: instructionPrompt ?? this.instructionPrompt,
    imageDataUrl: imageDataUrl ?? this.imageDataUrl,
    imageDataUrls: imageDataUrls ?? this.imageDataUrls,
    textureAssets: textureAssets ?? this.textureAssets,
    // Deletion is monotonic, so null never needs to overwrite a value here.
    deletedAt: deletedAt ?? this.deletedAt,
    retryRequest: clearRetryRequest
        ? null
        : (retryRequest ?? this.retryRequest),
  );

  // ── Local persistence (SharedPreferences) ─────────────────────────────────

  Map<String, dynamic> toLocalJson() => toContentJson();

  /// Serializes the message for persistence.
  ///
  /// [includeImages] controls whether the (potentially multi-MB, base64)
  /// reference images are embedded. It is `false` for the conversation-list
  /// snapshot, which is returned inline for every conversation and would
  /// otherwise make the list response grow without bound; restored bubbles
  /// still recover their images from the per-message content on open.
  Map<String, dynamic> toContentJson({bool includeImages = true}) {
    final images = includeImages ? allImageDataUrls : const <String>[];
    return {
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
      if (messageType != null) 'message_type': messageType,
      if (operation != null) 'operation': operation,
      if (sourceModelUrl != null) 'source_model_url': sourceModelUrl,
      if (modelOptionId != null) 'model_option_id': modelOptionId,
      if (modelLabel != null) 'model_label': modelLabel,
      if (instructionPrompt != null) 'instruction_prompt': instructionPrompt,
      if (images.isNotEmpty) 'image_data_url': images.first,
      if (images.isNotEmpty) 'image_data_urls': images,
      if (textureAssets.isNotEmpty) 'texture_assets': textureAssets,
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
    };
  }

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
    messageType: json['message_type'] as String?,
    operation: json['operation'] as String?,
    sourceModelUrl: json['source_model_url'] as String?,
    modelOptionId: json['model_option_id'] as String?,
    modelLabel: json['model_label'] as String?,
    instructionPrompt: json['instruction_prompt'] as String?,
    imageDataUrl: json['image_data_url'] as String?,
    imageDataUrls: _asStringList(json['image_data_urls']),
    textureAssets: _asStringMapList(json['texture_assets']),
    deletedAt: DateTime.tryParse((json['deleted_at'] as String?) ?? ''),
  );

  // ── Remote API response ───────────────────────────────────────────────────

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final remoteContent =
        _asStringMap(json['content_json']) ?? _asStringMap(json['content']);
    final content = remoteContent ?? json;
    final sentAt = json['sent_at'] as String?;
    final createdAt = json['created_at'] as String?;
    return MessageModel.fromLocalJson({
      ...content,
      'id':
          (content['id'] as String?) ??
          (json['client_message_id'] as String?) ??
          (json['id'] as String),
      'role': (content['role'] as String?) ?? (json['role'] as String),
      'text':
          (content['text'] as String?) ??
          (json['content_text'] as String?) ??
          '',
      'created_at':
          (content['created_at'] as String?) ??
          sentAt ??
          createdAt ??
          DateTime.now().toIso8601String(),
    });
  }

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

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  bool get isAssetVersionEvent =>
      messageType == 'asset_version' ||
      id.startsWith('edit-') ||
      operation == 'regenerate_3d_part' ||
      operation == 'add_3d_part' ||
      operation == 'articulate_3d_model';
}
