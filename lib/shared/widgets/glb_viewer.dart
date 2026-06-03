import 'package:flutter/material.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

import 'glb_viewer_stub.dart'
    if (dart.library.js_interop) 'glb_viewer_web.dart';

class GlbViewer extends StatelessWidget {
  const GlbViewer({
    super.key,
    required this.src,
    this.autoRotate = true,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.instructionPrompt,
    this.sourceWorkflowId,
    this.conversationId,
    this.editModelOptions = const [],
    this.defaultEditModelOptionId,
    this.onArticulationCompleted,
    this.viewerStateKey,
  });

  final String src;
  final bool autoRotate;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final String? instructionPrompt;
  final String? sourceWorkflowId;
  final String? conversationId;
  final List<GenerationModelOption> editModelOptions;
  final String? defaultEditModelOptionId;
  final void Function(
    String glbUrl,
    String workflowId,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>> joints,
  )?
  onArticulationCompleted;

  /// Stable key used for IndexedDB state persistence. Pass the message ID so
  /// the key does not change even when the model URL is updated (e.g. after
  /// articulation replaces the GLB). Defaults to a hash of [src].
  final String? viewerStateKey;

  @override
  Widget build(BuildContext context) {
    return GlbViewerPlatform(
      src: src,
      autoRotate: autoRotate,
      modelArtifact: modelArtifact,
      codeArtifact: codeArtifact,
      jointsArtifact: jointsArtifact,
      joints: joints,
      instructionPrompt: instructionPrompt,
      sourceWorkflowId: sourceWorkflowId,
      conversationId: conversationId,
      editModelOptions: editModelOptions,
      defaultEditModelOptionId: defaultEditModelOptionId,
      onArticulationCompleted: onArticulationCompleted,
      viewerStateKey: viewerStateKey,
    );
  }
}
