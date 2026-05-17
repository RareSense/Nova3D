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
    this.editModelOptions = const [],
    this.defaultEditModelOptionId,
  });

  final String src;
  final bool autoRotate;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final String? instructionPrompt;
  final String? sourceWorkflowId;
  final List<GenerationModelOption> editModelOptions;
  final String? defaultEditModelOptionId;

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
      editModelOptions: editModelOptions,
      defaultEditModelOptionId: defaultEditModelOptionId,
    );
  }
}
