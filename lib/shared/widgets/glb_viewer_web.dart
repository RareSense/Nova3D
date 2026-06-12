import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
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

  /// Called when articulation completes. Provides the articulated model's
  /// persistent URL, workflow ID, and joint data so the caller can persist them.
  final void Function(
    String glbUrl,
    String workflowId,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>> joints,
  )?
  onArticulationCompleted;
  final void Function(AiEditCompletion completion)? onEditCompleted;

  /// Stable key for IndexedDB state persistence. Defaults to a hash of [src].
  final String? viewerStateKey;

  @override
  ConsumerState<GlbViewerPlatform> createState() => _GlbViewerPlatformState();
}

class _GlbViewerPlatformState extends ConsumerState<GlbViewerPlatform> {
  static int _counter = 0;

  // These are reassigned by [_provisionViewer] when the host (web/index.html)
  // tears the iframe down on fullscreen exit and we rebuild it in place.
  late String _viewType;
  late String _viewerId;
  late web.HTMLIFrameElement _iframe;
  int _instanceGen = 0;

  String? _resolvedSrc;
  String? _loadedSourceModelUrl;
  bool _loadError = false;

  StreamSubscription<web.MessageEvent>? _windowMessageSub;

  @override
  void initState() {
    super.initState();
    _provisionViewer();
    // Listen for the disposal message dispatched by web/index.html when the
    // fullscreen overlay is torn down (either via the viewer's minimize
    // button or the ESC key). When the disposed viewer is ours, we rebuild
    // the iframe so the chat-preview slot gets a fresh viewer — matching the
    // remount semantics of toggling between the MODEL and CODE tabs.
    _windowMessageSub = web.window.onMessage.listen(_onWindowMessage);
  }

  // Builds a fresh iframe, viewType, and viewerId, and re-registers both the
  // platform-view factory and the AI edit handler. Called once from initState
  // and again from [_rebuildAfterDisposal] when the host has torn the iframe
  // out from under us.
  void _provisionViewer() {
    _viewerId = 'nova3d-viewer-${++_counter}';
    _viewType = '$_viewerId-g$_instanceGen';
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

  void _onWindowMessage(web.MessageEvent event) {
    final raw = event.data?.dartify();
    if (raw is! Map) return;
    if (raw['type'] != 'nova3d-viewer-disposed') return;
    if (raw['viewerId'] != _viewerId) return;
    _rebuildAfterDisposal();
  }

  // The host has already removed our iframe from the DOM. Release any blob
  // URL we held, tear down the now-stale edit-handler registration, then
  // provision a fresh viewer and trigger a rebuild so HtmlElementView mounts
  // the new viewType.
  void _rebuildAfterDisposal() {
    if (!mounted) return;
    _unregisterEditHandler(_viewerId.toJS);
    GlbAssetCache.revoke(_resolvedSrc ?? '');
    _resolvedSrc = null;
    _loadedSourceModelUrl = null;
    _loadError = false;
    _instanceGen++;
    setState(_provisionViewer);
  }

  @override
  void didUpdateWidget(covariant GlbViewerPlatform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.autoRotate != widget.autoRotate) {
      GlbAssetCache.revoke(_resolvedSrc ?? '');
      _resolvedSrc = null;
      _loadedSourceModelUrl = null;
      _resolveAndLoad(widget.src);
      return;
    }

    if (oldWidget.modelArtifact != widget.modelArtifact ||
        oldWidget.codeArtifact != widget.codeArtifact ||
        oldWidget.jointsArtifact != widget.jointsArtifact ||
        oldWidget.joints != widget.joints ||
        oldWidget.instructionPrompt != widget.instructionPrompt ||
        oldWidget.sourceWorkflowId != widget.sourceWorkflowId ||
        !_sameAssetVersions(oldWidget.assetVersions, widget.assetVersions) ||
        oldWidget.defaultEditModelOptionId != widget.defaultEditModelOptionId ||
        !_sameModelOptions(
          oldWidget.editModelOptions,
          widget.editModelOptions,
        )) {
      if (_loadError && widget.assetVersions.isNotEmpty) {
        _resolveAndLoad(widget.src);
      }
      _postEditConfig();
    }
  }

  @override
  void dispose() {
    _windowMessageSub?.cancel();
    _windowMessageSub = null;
    _unregisterEditHandler(_viewerId.toJS);
    GlbAssetCache.revoke(_resolvedSrc ?? '');
    super.dispose();
  }

  Future<void> _resolveAndLoad(String src) async {
    if (_loadError) setState(() => _loadError = false);

    final resolved = await _resolveModelCandidate(
      modelUrl: src,
      workflowId: widget.sourceWorkflowId,
    );
    if (!mounted || src != widget.src) {
      if (resolved != null) GlbAssetCache.revoke(resolved.objectUrl);
      return;
    }

    if (resolved != null) {
      _loadResolvedModel(resolved, expectedSrc: src);
      return;
    }

    for (final version in widget.assetVersions.reversed) {
      final versionResolved = await _resolveModelCandidate(
        modelUrl: version.modelUrl,
        workflowId: version.workflowId,
      );
      if (!mounted || src != widget.src) {
        if (versionResolved != null) {
          GlbAssetCache.revoke(versionResolved.objectUrl);
        }
        return;
      }
      if (versionResolved == null) continue;
      _loadResolvedModel(versionResolved, expectedSrc: src);
      return;
    }

    if (mounted && src == widget.src) setState(() => _loadError = true);
  }

  Future<_ResolvedGlb?> _resolveModelCandidate({
    required String modelUrl,
    String? workflowId,
  }) async {
    if (modelUrl.trim().isNotEmpty) {
      final resolved = await GlbAssetCache.resolve(modelUrl);
      if (resolved != null) {
        return _ResolvedGlb(objectUrl: resolved, sourceUrl: modelUrl);
      }
    }

    if (workflowId == null || workflowId.isEmpty) return null;

    try {
      final freshUrl =
          (await ref.read(cadServiceProvider).getResult(workflowId)).glbUrl;
      if (freshUrl == null || freshUrl.isEmpty) return null;
      final freshResolved = await GlbAssetCache.resolve(freshUrl);
      if (freshResolved == null) return null;
      return _ResolvedGlb(objectUrl: freshResolved, sourceUrl: freshUrl);
    } catch (_) {
      return null;
    }
  }

  void _loadResolvedModel(
    _ResolvedGlb resolved, {
    required String expectedSrc,
  }) {
    setState(() {
      _resolvedSrc = resolved.objectUrl;
      _loadedSourceModelUrl = resolved.sourceUrl;
      _loadError = false;
    });
    _iframe.src = _buildViewerUrl(
      resolved.objectUrl,
      sourceModelUrl: resolved.sourceUrl,
    );
    _postEditConfigSoon(expectedSrc);
  }

  void _postEditConfigSoon(String expectedSrc) {
    for (final delay in const [
      Duration(milliseconds: 250),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 2500),
    ]) {
      Future<void>.delayed(delay, () {
        if (!mounted || expectedSrc != widget.src) return;
        _postEditConfig();
      });
    }
  }

  String _buildViewerUrl(String modelUrl, {String? sourceModelUrl}) {
    final params = {
      'viewerId': _viewerId,
      'stateKey':
          widget.viewerStateKey ?? widget.src.hashCode.toRadixString(16),
      'glb': modelUrl,
      'sourceModelUrl': sourceModelUrl ?? widget.src,
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
      if (widget.assetVersions.isNotEmpty)
        'assetVersions': json.encode(
          widget.assetVersions.map((version) => version.toJson()).toList(),
        ),
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
          'label': option.displayLabel,
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
        'sourceModelUrl': _loadedSourceModelUrl ?? widget.src,
        'instructionPrompt': widget.instructionPrompt ?? '',
        'sourceWorkflowId': widget.sourceWorkflowId ?? '',
        'assetVersions': widget.assetVersions
            .map((version) => version.toJson())
            .toList(),
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

  bool _sameAssetVersions(List<AssetVersion> a, List<AssetVersion> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].messageId != b[i].messageId ||
          a[i].workflowId != b[i].workflowId ||
          a[i].modelUrl != b[i].modelUrl ||
          a[i].operation != b[i].operation) {
        return false;
      }
    }
    return true;
  }

  void _handleEditRequest(JSString requestJson) {
    final request = _decodeEditRequest(requestJson.toDart);
    if (request.requestType == 'version_resolve') {
      _resolveAssetVersion(
        requestId: request.requestId,
        workflowId: request.sourceWorkflowId,
        fallbackModelUrl: request.sourceModelUrl,
      );
      return;
    }
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

  Future<void> _resolveAssetVersion({
    required String requestId,
    required String workflowId,
    required String fallbackModelUrl,
  }) async {
    try {
      final result = workflowId.isEmpty
          ? null
          : await ref.read(cadServiceProvider).getResult(workflowId);
      final modelUrl = result?.glbUrl ?? fallbackModelUrl;
      final resolved = modelUrl.isEmpty
          ? null
          : await GlbAssetCache.resolve(modelUrl);
      _postVersionResolveResult({
        'requestId': requestId,
        'modelUrl': resolved ?? modelUrl,
        if (result?.modelArtifact != null)
          'modelArtifact': result!.modelArtifact,
        if (result?.codeArtifact != null) 'codeArtifact': result!.codeArtifact,
        if (result?.jointsArtifact != null)
          'jointsArtifact': result!.jointsArtifact,
        if (result != null && result.joints.isNotEmpty) 'joints': result.joints,
      });
    } catch (_) {
      _postVersionResolveResult({
        'requestId': requestId,
        'modelUrl': fallbackModelUrl,
      });
    }
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
        'message':
            'Add an OpenRouter, OpenAI, Anthropic, or Gemini key in Settings.',
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
      widget.onEditCompleted?.call(
        AiEditCompletion(
          operation: operation,
          description: description,
          modelUrl: result.glbUrl!,
          workflowId: workflowId,
          sourceModelUrl: result.glbUrl,
          modelArtifact: result.modelArtifact,
          codeArtifact: result.codeArtifact,
          jointsArtifact: result.jointsArtifact,
          joints: result.joints,
          modelOptionId: modelOption.id,
          instructionPrompt: instructionPrompt,
        ),
      );
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
        requestType: (request['type'] as String?) ?? '',
        operation: (request['operation'] as String?) ?? '',
        description: (request['description'] as String?) ?? '',
        partType: (request['partType'] as String?) ?? '',
        modelOptionId: (request['modelOptionId'] as String?) ?? '',
        sourceWorkflowId:
            (request['sourceWorkflowId'] as String?) ??
            (request['workflowId'] as String?) ??
            '',
        sourceModelUrl:
            (request['sourceModelUrl'] as String?) ??
            (request['modelUrl'] as String?) ??
            '',
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

  void _postVersionResolveResult(Map<String, dynamic> payload) {
    _iframe.contentWindow?.postMessage(
      {'type': 'nova3d-version-resolve-result', ...payload}.jsify(),
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
          // Key is bound to _viewType so that after _rebuildAfterDisposal
          // bumps _instanceGen, Flutter unmounts the stale platform view
          // (whose iframe was already removed by the host) and remounts a
          // fresh one rather than reusing the existing element in place.
          : HtmlElementView(key: ValueKey(_viewType), viewType: _viewType),
    );
  }
}

class _EditRequest {
  const _EditRequest({
    this.requestId = '',
    this.requestType = '',
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
  final String requestType;
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

class _ResolvedGlb {
  const _ResolvedGlb({required this.objectUrl, required this.sourceUrl});

  final String objectUrl;
  final String sourceUrl;
}
