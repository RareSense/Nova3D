import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

class GlbViewerPlatform extends StatelessWidget {
  const GlbViewerPlatform({
    super.key,
    required this.src,
    required this.autoRotate,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.instructionPrompt,
    this.sourceWorkflowId,
    this.conversationId,
    this.assetVersions = const [],
    this.editModelOptions = const [],
    this.defaultEditModelOptionId,
    this.onArticulationCompleted,
    this.onEditCompleted,
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
  final List<AssetVersion> assetVersions;
  final List<GenerationModelOption> editModelOptions;
  final String? defaultEditModelOptionId;
  final void Function(
    String,
    String,
    Map<String, dynamic>?,
    List<Map<String, dynamic>>,
  )?
  onArticulationCompleted;
  final void Function(AiEditCompletion completion)? onEditCompleted;
  final String? viewerStateKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: const Text(
        '3D preview is available in the web app.',
        style: TextStyle(color: kTextSecondary, fontSize: 13),
      ),
    );
  }
}
