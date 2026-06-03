import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/shared/services/glb_asset_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

@JS('nova3dRegisterEditHandler')
external void _registerEditHandler(JSString viewerId, JSFunction handler);

@JS('nova3dUnregisterEditHandler')
external void _unregisterEditHandler(JSString viewerId);

class GlbViewerPlatform extends ConsumerStatefulWidget {
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

  /// Called when articulation completes. Provides the articulated model's
  /// persistent URL, workflow ID, and joint data so the caller can persist them.
  final void Function(
    String glbUrl,
    String workflowId,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>> joints,
  )?
  onArticulationCompleted;

  /// Stable key for IndexedDB state persistence. Defaults to a hash of [src].
  final String? viewerStateKey;

  @override
  ConsumerState<GlbViewerPlatform> createState() => _GlbViewerPlatformState();
}

class _GlbViewerPlatformState extends ConsumerState<GlbViewerPlatform> {
  static int _counter = 0;

  late final String _viewType;
  late final String _viewerId;
  late final web.HTMLIFrameElement _iframe;

  String? _resolvedSrc;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _viewerId = 'nova3d-viewer-${++_counter}';
    _viewType = _viewerId;
    _iframe = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.borderRadius = '12px'
      ..style.background = '#0d0d0d'
      ..setAttribute('allow', 'fullscreen *')
      ..setAttribute('allowfullscreen', 'true');

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) => _iframe,
    );

    _resolveAndLoad(widget.src);
    _registerEditHandler(_viewerId.toJS, _handleEditRequest.toJS);
  }

  @override
  void didUpdateWidget(covariant GlbViewerPlatform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.autoRotate != widget.autoRotate) {
      GlbAssetCache.revoke(_resolvedSrc ?? '');
      _resolvedSrc = null;
      _resolveAndLoad(widget.src);
      return;
    }

    if (oldWidget.modelArtifact != widget.modelArtifact ||
        oldWidget.codeArtifact != widget.codeArtifact ||
        oldWidget.jointsArtifact != widget.jointsArtifact ||
        oldWidget.joints != widget.joints ||
        oldWidget.instructionPrompt != widget.instructionPrompt ||
        oldWidget.sourceWorkflowId != widget.sourceWorkflowId ||
        oldWidget.defaultEditModelOptionId != widget.defaultEditModelOptionId ||
        !_sameModelOptions(
          oldWidget.editModelOptions,
          widget.editModelOptions,
        )) {
      _postEditConfig();
    }
  }

  @override
  void dispose() {
    _unregisterEditHandler(_viewerId.toJS);
    GlbAssetCache.revoke(_resolvedSrc ?? '');
    super.dispose();
  }

  Future<void> _resolveAndLoad(String src) async {
    if (_loadError) setState(() => _loadError = false);

    final resolved = await GlbAssetCache.resolve(src);
    if (!mounted || src != widget.src) {
      if (resolved != null) GlbAssetCache.revoke(resolved);
      return;
    }

    if (resolved != null) {
      setState(() => _resolvedSrc = resolved);
      _iframe.src = _buildViewerUrl(resolved);
      _postEditConfigSoon(src);
      return;
    }

    // URL inaccessible (expired SAS token). Re-fetch a fresh URL via the API.
    final workflowId = widget.sourceWorkflowId;
    if (workflowId == null || workflowId.isEmpty) {
      setState(() => _loadError = true);
      return;
    }

    try {
      final freshUrl =
          (await ref.read(cadServiceProvider).getResult(workflowId)).glbUrl;
      if (!mounted || src != widget.src || freshUrl == null) {
        if (mounted && src == widget.src) setState(() => _loadError = true);
        return;
      }
      final freshResolved = await GlbAssetCache.resolve(freshUrl);
      if (!mounted || src != widget.src) {
        if (freshResolved != null) GlbAssetCache.revoke(freshResolved);
        return;
      }
      if (freshResolved == null) {
        setState(() => _loadError = true);
        return;
      }
      setState(() {
        _resolvedSrc = freshResolved;
        _loadError = false;
      });
      _iframe.src = _buildViewerUrl(freshResolved);
      _postEditConfigSoon(freshUrl);
    } catch (_) {
      if (mounted && src == widget.src) setState(() => _loadError = true);
    }
  }

  void _postEditConfigSoon(String src) {
    for (final delay in const [
      Duration(milliseconds: 250),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 2500),
    ]) {
      Future<void>.delayed(delay, () {
        if (!mounted || src != widget.src) return;
        _postEditConfig();
      });
    }
  }

  String _buildViewerUrl(String modelUrl) {
    final params = {
      'viewerId': _viewerId,
      'stateKey':
          widget.viewerStateKey ?? widget.src.hashCode.toRadixString(16),
      'glb': modelUrl,
      'sourceModelUrl': widget.src,
      'autoRotate': widget.autoRotate.toString(),
      if (widget.modelArtifact != null)
        'modelArtifact': json.encode(widget.modelArtifact),
      if (widget.codeArtifact != null)
        'codeArtifact': json.encode(widget.codeArtifact),
      if (widget.jointsArtifact != null)
        'jointsArtifact': json.encode(widget.jointsArtifact),
      if (widget.joints.isNotEmpty) 'joints': json.encode(widget.joints),
      if ((widget.instructionPrompt ?? '').isNotEmpty)
        'instructionPrompt': widget.instructionPrompt!,
      if (widget.sourceWorkflowId != null)
        'sourceWorkflowId': widget.sourceWorkflowId!,
      'editModelOptions': json.encode(_editModelOptionsPayload()),
      if (widget.defaultEditModelOptionId != null)
        'editDefaultModelId': widget.defaultEditModelOptionId!,
    };
    return Uri(path: '/nova3d_viewer.html', queryParameters: params).toString();
  }

  List<Map<String, String>> _editModelOptionsPayload() => widget
      .editModelOptions
      .map(
        (option) => {
          'id': option.id,
          'label': option.label,
          'provider': option.provider.label,
        },
      )
      .toList();

  void _postEditConfig() {
    _iframe.contentWindow?.postMessage(
      {
        'type': 'nova3d-edit-config',
        if (widget.modelArtifact != null) 'modelArtifact': widget.modelArtifact,
        if (widget.codeArtifact != null) 'codeArtifact': widget.codeArtifact,
        if (widget.jointsArtifact != null)
          'jointsArtifact': widget.jointsArtifact,
        if (widget.joints.isNotEmpty) 'joints': widget.joints,
        'sourceModelUrl': widget.src,
        'instructionPrompt': widget.instructionPrompt ?? '',
        'sourceWorkflowId': widget.sourceWorkflowId ?? '',
        'editModelOptions': _editModelOptionsPayload(),
        'editDefaultModelId': widget.defaultEditModelOptionId ?? '',
      }.jsify(),
      '*'.toJS,
    );
  }

  bool _sameModelOptions(
    List<GenerationModelOption> a,
    List<GenerationModelOption> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].label != b[i].label) return false;
    }
    return true;
  }

  void _handleEditRequest(JSString requestJson) {
    final request = _decodeEditRequest(requestJson.toDart);
    _runEditWorkflow(
      requestId: request.requestId,
      operation: request.operation,
      description: request.description,
      partType: request.partType,
      codeArtifact: request.codeArtifact,
      modelArtifact: request.modelArtifact,
      sourceModelUrl: request.sourceModelUrl,
      instructionPrompt: request.instructionPrompt,
      selectedMeshes: request.selectedMeshes,
      screenshots: request.screenshots,
      sourceWorkflowId: request.sourceWorkflowId,
      modelOptionId: request.modelOptionId,
    );
  }

  Future<void> _runEditWorkflow({
    required String requestId,
    required String operation,
    required String description,
    required String partType,
    required Map<String, dynamic>? codeArtifact,
    required Map<String, dynamic>? modelArtifact,
    required String sourceModelUrl,
    required String instructionPrompt,
    required List<String> selectedMeshes,
    required List<String> screenshots,
    required String sourceWorkflowId,
    required String modelOptionId,
  }) async {
    final cad = ref.read(cadServiceProvider);
    final modelOption = GenerationModelOption.findById(
      widget.editModelOptions,
      modelOptionId,
    );
    var editableCodeArtifact = codeArtifact;
    var editableModelArtifact = modelArtifact ?? widget.modelArtifact;
    var editableModelUrl = sourceModelUrl.trim().isNotEmpty
        ? sourceModelUrl.trim()
        : widget.src;
    final workflowIdForSource = sourceWorkflowId.isNotEmpty
        ? sourceWorkflowId
        : (widget.sourceWorkflowId ?? '');
    final needsSourceResult =
        workflowIdForSource.isNotEmpty &&
        (editableCodeArtifact == null ||
            (operation == 'articulate_3d_model' &&
                editableModelArtifact == null &&
                editableModelUrl.isEmpty));
    if (needsSourceResult) {
      _postEditResult({
        'requestId': requestId,
        'status': 'running',
        'message': 'Loading editable source from the original workflow...',
      });
      try {
        final sourceResult = await cad.getResult(workflowIdForSource);
        editableCodeArtifact ??= sourceResult.codeArtifact;
        editableModelArtifact ??= sourceResult.modelArtifact;
        if (editableModelUrl.isEmpty && sourceResult.glbUrl != null) {
          editableModelUrl = sourceResult.glbUrl!;
        }
      } on CadException catch (e) {
        _postEditResult({
          'requestId': requestId,
          'status': 'failed',
          'message': _editableSourceLoadMessage(e, workflowIdForSource),
        });
        return;
      }
    }

    if (editableCodeArtifact == null) {
      _postEditResult({
        'requestId': requestId,
        'status': 'failed',
        'message':
            'This model does not include editable source code yet. Generate it again before using AI edits.',
      });
      return;
    }
    if (operation == 'articulate_3d_model' &&
        editableModelArtifact == null &&
        editableModelUrl.isEmpty) {
      _postEditResult({
        'requestId': requestId,
        'status': 'failed',
        'message':
            'This model does not include a source GLB artifact yet. Generate or edit it again before articulating.',
      });
      return;
    }
    if (modelOption == null) {
      _postEditResult({
        'requestId': requestId,
        'status': 'failed',
        'message': 'Add a Gemini, Anthropic, or OpenAI key in Settings.',
      });
      return;
    }

    try {
      _postEditResult({
        'requestId': requestId,
        'status': 'running',
        'message': switch (operation) {
          'add_3d_part' => 'Starting add-part workflow...',
          'articulate_3d_model' => 'Starting articulation workflow...',
          _ => 'Starting selected-part regeneration...',
        },
      });
      final workflowId = switch (operation) {
        'add_3d_part' => await cad.startAddPart(
          codeArtifact: editableCodeArtifact,
          description: description,
          modelOption: modelOption,
          conversationId: widget.conversationId,
        ),
        'articulate_3d_model' => await cad.startArticulation(
          codeArtifact: editableCodeArtifact,
          modelArtifact: editableModelArtifact,
          modelUrl: editableModelUrl,
          instructionPrompt: instructionPrompt,
          articulationRequest: description,
          selectedMeshes: selectedMeshes,
          screenshots: screenshots,
          modelOption: modelOption,
          conversationId: widget.conversationId,
        ),
        _ => await cad.startRegeneratePart(
          codeArtifact: editableCodeArtifact,
          description: description,
          modelOption: modelOption,
          partType: partType,
          conversationId: widget.conversationId,
        ),
      };

      final result = await cad.runWorkflow(
        workflowId,
        onProgress: (status) => _postEditResult({
          'requestId': requestId,
          'status': 'running',
          'workflowId': workflowId,
          'message': status.progressLabel,
        }),
      );
      if (result.failed ||
          result.glbUrl == null ||
          result.codeArtifact == null) {
        _postEditResult({
          'requestId': requestId,
          'status': 'failed',
          'workflowId': workflowId,
          'message':
              result.errorMessage ??
              'The edit workflow did not produce a model.',
        });
        return;
      }

      final resolved = await GlbAssetCache.resolve(result.glbUrl!);
      if (!mounted) {
        if (resolved != null) GlbAssetCache.revoke(resolved);
        return;
      }
      if (resolved == null) {
        _postEditResult({
          'requestId': requestId,
          'status': 'failed',
          'message': 'The edited model could not be loaded. Try again.',
        });
        return;
      }
      _postEditResult({
        'requestId': requestId,
        'status': 'completed',
        'operation': operation,
        'workflowId': workflowId,
        'modelUrl': resolved,
        'sourceModelUrl': result.glbUrl,
        'modelArtifact': result.modelArtifact,
        'codeArtifact': result.codeArtifact,
        'jointsArtifact': result.jointsArtifact,
        'joints': result.joints,
        'jointCount': result.jointCount,
      });
      if (operation == 'articulate_3d_model' && result.joints.isNotEmpty) {
        widget.onArticulationCompleted?.call(
          result.glbUrl!,
          workflowId,
          result.jointsArtifact,
          result.joints,
        );
      }
    } on CadException catch (e) {
      _postEditResult({
        'requestId': requestId,
        'status': 'failed',
        'message': e.message,
      });
    } catch (_) {
      _postEditResult({
        'requestId': requestId,
        'status': 'failed',
        'message': 'Edit failed. Try again or switch provider keys.',
      });
    }
  }

  _EditRequest _decodeEditRequest(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const _EditRequest();
      final request = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return _EditRequest(
        requestId: (request['requestId'] as String?) ?? '',
        operation: (request['operation'] as String?) ?? '',
        description: (request['description'] as String?) ?? '',
        partType: (request['partType'] as String?) ?? '',
        modelOptionId: (request['modelOptionId'] as String?) ?? '',
        sourceWorkflowId: (request['sourceWorkflowId'] as String?) ?? '',
        sourceModelUrl: (request['sourceModelUrl'] as String?) ?? '',
        instructionPrompt: (request['instructionPrompt'] as String?) ?? '',
        codeArtifact: _asStringMap(request['codeArtifact']),
        modelArtifact: _asStringMap(request['modelArtifact']),
        selectedMeshes: _asStringList(request['selectedMeshes']),
        screenshots: _asStringList(request['screenshots']),
      );
    } catch (_) {
      return const _EditRequest();
    }
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  void _postEditResult(Map<String, dynamic> payload) {
    _iframe.contentWindow?.postMessage(
      {'type': 'nova3d-edit-result', ...payload}.jsify(),
      '*'.toJS,
    );
  }

  String _editableSourceLoadMessage(CadException error, String workflowId) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (lower.contains('workflow not found') || lower.contains('404')) {
      return workflowId.isEmpty
          ? 'This model does not include editable source code yet. Generate it again before using AI edits.'
          : 'This model does not include editable source code, and Nova3D could not find source for workflow $workflowId. Generate it again before using AI edits.';
    }
    return message.isEmpty
        ? 'Nova3D could not load editable source code for this model.'
        : message;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: _loadError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: kTextMuted,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Model unavailable',
                    style: TextStyle(color: kTextMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _resolveAndLoad(widget.src),
                    child: const Text(
                      'Retry',
                      style: TextStyle(color: kAccentBlue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          : HtmlElementView(viewType: _viewType),
    );
  }
}

class _EditRequest {
  const _EditRequest({
    this.requestId = '',
    this.operation = '',
    this.description = '',
    this.partType = '',
    this.modelOptionId = '',
    this.sourceWorkflowId = '',
    this.sourceModelUrl = '',
    this.instructionPrompt = '',
    this.codeArtifact,
    this.modelArtifact,
    this.selectedMeshes = const [],
    this.screenshots = const [],
  });

  final String requestId;
  final String operation;
  final String description;
  final String partType;
  final String modelOptionId;
  final String sourceWorkflowId;
  final String sourceModelUrl;
  final String instructionPrompt;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? modelArtifact;
  final List<String> selectedMeshes;
  final List<String> screenshots;
}
