class AssetVersion {
  const AssetVersion({
    required this.messageId,
    required this.label,
    required this.operation,
    required this.modelUrl,
    required this.workflowId,
    this.sourceModelUrl,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
  });

  final String messageId;
  final String label;
  final String operation;
  final String modelUrl;
  final String workflowId;
  final String? sourceModelUrl;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'label': label,
    'operation': operation,
    'model_url': modelUrl,
    'workflow_id': workflowId,
    if (sourceModelUrl != null) 'source_model_url': sourceModelUrl,
    if (modelArtifact != null) 'model_artifact': modelArtifact,
    if (codeArtifact != null) 'code_artifact': codeArtifact,
    if (jointsArtifact != null) 'joints_artifact': jointsArtifact,
    if (joints.isNotEmpty) 'joints': joints,
  };
}

class AiEditCompletion {
  const AiEditCompletion({
    required this.operation,
    required this.description,
    required this.modelUrl,
    required this.workflowId,
    this.sourceModelUrl,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.modelOptionId,
    this.instructionPrompt,
  });

  final String operation;
  final String description;
  final String modelUrl;
  final String workflowId;
  final String? sourceModelUrl;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final String? modelOptionId;
  final String? instructionPrompt;
}
