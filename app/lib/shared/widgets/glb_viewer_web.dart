import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/shared/services/glb_asset_cache.dart';
import 'package:nova3d_frontend/shared/services/uv_maps_downloader.dart';
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
  static const Duration _resolutionBudget = Duration(seconds: 42);
  static const Duration _historicalResultTimeout = Duration(seconds: 6);
  static const Duration _freshUrlResolveSlice = Duration(seconds: 20);
  static const Duration _originalUrlResolveSlice = Duration(seconds: 18);
  static const int _maxVersionFallbacks = 2;

  // These are reassigned by [_provisionViewer] when the host (web/index.html)
  // tears the iframe down on fullscreen exit and we rebuild it in place.
  late String _viewType;
  late String _viewerId;
  late web.HTMLIFrameElement _iframe;
  int _instanceGen = 0;
  int _resolveAttempt = 0;

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
    analytics.capture(Ev.viewerOpened, <String, Object?>{
      Pr.workflowId: widget.sourceWorkflowId,
      Pr.versionCount: widget.assetVersions.length,
      Pr.jointCount: widget.joints.length,
      // Whether the editor has the source script — AI edits are impossible
      // without it, so this separates "chose not to edit" from "could not".
      'has_code_artifact': widget.codeArtifact != null,
    });
  }

  // Builds a fresh iframe, viewType, and viewerId, and re-registers both the
  // platform-view factory and the AI edit handler. Called once from initState
  // and again from [_rebuildAfterDisposal] when the host has torn the iframe
  // out from under us.
  void _provisionViewer({
    String? reusableResolvedSrc,
    String? reusableSourceUrl,
  }) {
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

    if (reusableResolvedSrc != null && reusableResolvedSrc.isNotEmpty) {
      final attempt = ++_resolveAttempt;
      _resolvedSrc = reusableResolvedSrc;
      _loadedSourceModelUrl = reusableSourceUrl;
      _loadError = false;
      _iframe.src = _buildViewerUrl(reusableResolvedSrc);
      _postEditConfigSoon(widget.src, attempt);
    } else {
      _resolveAndLoad(widget.src);
    }
    _registerEditHandler(_viewerId.toJS, _handleEditRequest.toJS);
  }

  void _onWindowMessage(web.MessageEvent event) {
    if (event.origin != web.window.location.origin) return;
    final raw = event.data?.dartify();
    if (raw is! Map) return;
    // Both branches filter on viewerId: several viewers can be mounted at once
    // (chat preview + fullscreen), and every one of them receives every
    // window message. Without the filter each editor event would be captured
    // once per mounted viewer.
    if (raw['viewerId'] != _viewerId) return;

    final type = raw['type'];
    // The disposal notification is deliberately relayed by the top window;
    // every other viewer message must come from this exact iframe.
    if (type != 'nova3d-viewer-disposed' &&
        event.source != _iframe.contentWindow) {
      return;
    }

    switch (type) {
      case 'nova3d-viewer-disposed':
        _rebuildAfterDisposal();
      case 'nova3d-viewer-ready':
        _postEditConfig();
      case 'nova3d-analytics':
        _forwardViewerAnalytics(raw);
    }
  }

  /// Forwards a structured event from the Three.js editor to PostHog.
  ///
  /// The iframe has no PostHog client of its own — see web/nova3d/analytics.js
  /// for why. Everything arriving here is untrusted input from a postMessage,
  /// so the event name is validated against the taxonomy allowlist and the
  /// properties go through the same scrubbing as any other capture.
  void _forwardViewerAnalytics(Map<Object?, Object?> raw) {
    final event = raw['event'];
    if (event is! String || !kViewerEvents.contains(event)) return;

    final properties = <String, Object?>{Pr.surface: Surface.viewer};
    final incoming = raw['properties'];
    if (incoming is Map) {
      for (final entry in incoming.entries) {
        final key = entry.key;
        if (key is String) properties[key] = entry.value;
      }
    }
    // Stamp the run this editor session belongs to, so editor activity joins
    // back to the generation that produced the model.
    if (widget.sourceWorkflowId != null) {
      properties.putIfAbsent(Pr.workflowId, () => widget.sourceWorkflowId);
    }
    analytics.capture(event, properties);
  }

  // The host has already removed our iframe from the DOM. Keep the resolved
  // parent-owned blob URL alive, tear down the stale edit-handler registration,
  // then provision a fresh iframe around those same bytes. This avoids another
  // cache/backend resolution when returning from fullscreen.
  void _rebuildAfterDisposal() {
    if (!mounted) return;
    final reusableResolvedSrc = _resolvedSrc;
    final reusableSourceUrl = _loadedSourceModelUrl;
    _invalidateResolution();
    _unregisterEditHandler(_viewerId.toJS);
    _loadError = false;
    _instanceGen++;
    setState(() {
      _provisionViewer(
        reusableResolvedSrc: reusableResolvedSrc,
        reusableSourceUrl: reusableSourceUrl,
      );
    });
  }

  @override
  void didUpdateWidget(covariant GlbViewerPlatform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.autoRotate != widget.autoRotate) {
      _invalidateResolution();
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
    _invalidateResolution();
    _windowMessageSub?.cancel();
    _windowMessageSub = null;
    _unregisterEditHandler(_viewerId.toJS);
    GlbAssetCache.revoke(_resolvedSrc ?? '');
    super.dispose();
  }

  Future<void> _resolveAndLoad(String src) async {
    final attempt = ++_resolveAttempt;
    if (_loadError) setState(() => _loadError = false);
    final timer = Stopwatch()..start();
    analytics.capture(Ev.modelResolutionStarted, <String, Object?>{
      Pr.versionCount: widget.assetVersions.length,
      'has_workflow_id': (widget.sourceWorkflowId ?? '').isNotEmpty,
    });

    final resolved = await _resolveModelCandidate(
      modelUrl: src,
      workflowId: widget.sourceWorkflowId,
      timer: timer,
      attempt: attempt,
    );
    if (!_isResolutionCurrent(attempt, src)) {
      if (resolved != null) GlbAssetCache.revoke(resolved.objectUrl);
      return;
    }

    if (resolved != null) {
      analytics.capture(Ev.modelResolutionSucceeded, <String, Object?>{
        Pr.durationMs: timer.elapsedMilliseconds,
        Pr.source: 'requested_model',
      });
      _loadResolvedModel(resolved, expectedSrc: src, attempt: attempt);
      return;
    }

    final triedCandidates = <String>{
      _candidateKey(src, widget.sourceWorkflowId),
    };
    var fallbackCount = 0;
    for (final version in widget.assetVersions.reversed) {
      if (_resolutionRemaining(timer) <= Duration.zero) break;
      final candidateKey = _candidateKey(version.modelUrl, version.workflowId);
      if (!triedCandidates.add(candidateKey)) continue;
      if (++fallbackCount > _maxVersionFallbacks) break;
      final versionResolved = await _resolveModelCandidate(
        modelUrl: version.modelUrl,
        workflowId: version.workflowId,
        timer: timer,
        attempt: attempt,
      );
      if (!_isResolutionCurrent(attempt, src)) {
        if (versionResolved != null) {
          GlbAssetCache.revoke(versionResolved.objectUrl);
        }
        return;
      }
      if (versionResolved == null) continue;
      analytics.capture(Ev.modelResolutionSucceeded, <String, Object?>{
        Pr.durationMs: timer.elapsedMilliseconds,
        Pr.source: 'version_fallback',
      });
      _loadResolvedModel(versionResolved, expectedSrc: src, attempt: attempt);
      return;
    }

    if (_isResolutionCurrent(attempt, src)) {
      analytics.capture(Ev.modelResolutionFailed, <String, Object?>{
        Pr.durationMs: timer.elapsedMilliseconds,
        Pr.versionCount: widget.assetVersions.length,
      });
      setState(() => _loadError = true);
    }
  }

  Future<_ResolvedGlb?> _resolveModelCandidate({
    required String modelUrl,
    String? workflowId,
    required Stopwatch timer,
    required int attempt,
  }) async {
    final originalUrl = modelUrl.trim();
    // Start the original URL immediately so a CacheStorage hit can complete
    // while the backend is refreshing an expired signed URL. We still prefer a
    // fresh backend URL when one is returned within the short refresh window.
    Future<String?>? originalResolution = originalUrl.isEmpty
        ? null
        : GlbAssetCache.resolve(originalUrl);

    final workflow = workflowId?.trim() ?? '';
    String freshUrl = '';
    if (workflow.isNotEmpty && _resolutionRemaining(timer) > Duration.zero) {
      final wait = _boundedWait(
        _historicalResultTimeout,
        _resolutionRemaining(timer),
      );
      if (wait > Duration.zero) {
        try {
          final result = await ref
              .read(cadServiceProvider)
              .getResult(workflow, receiveTimeout: wait)
              .timeout(wait);
          freshUrl = result.glbUrl?.trim() ?? '';
        } catch (_) {
          // Historical refresh is opportunistic. The original URL/cache and
          // bounded version fallbacks remain available below.
        }
      }
    }

    if (!_isResolutionCurrent(attempt, widget.src)) {
      _discardResolution(originalResolution);
      return null;
    }

    if (freshUrl.isNotEmpty) {
      if (freshUrl == originalUrl && originalResolution != null) {
        final resolved = await _claimResolution(
          originalResolution,
          sourceUrl: freshUrl,
          timer: timer,
          maxWait: _freshUrlResolveSlice,
          attempt: attempt,
        );
        originalResolution = null;
        if (resolved != null) return resolved;
      } else {
        final resolved = await _claimResolution(
          GlbAssetCache.resolve(freshUrl),
          sourceUrl: freshUrl,
          timer: timer,
          maxWait: _freshUrlResolveSlice,
          attempt: attempt,
        );
        if (resolved != null) {
          _discardResolution(originalResolution);
          return resolved;
        }
      }
    }

    if (originalResolution != null) {
      final resolved = await _claimResolution(
        originalResolution,
        sourceUrl: originalUrl,
        timer: timer,
        maxWait: _originalUrlResolveSlice,
        attempt: attempt,
      );
      originalResolution = null;
      if (resolved != null) return resolved;
    }
    return null;
  }

  Future<_ResolvedGlb?> _claimResolution(
    Future<String?> resolution, {
    required String sourceUrl,
    required Stopwatch timer,
    required Duration maxWait,
    required int attempt,
  }) async {
    final wait = _boundedWait(maxWait, _resolutionRemaining(timer));
    if (wait <= Duration.zero) {
      _discardResolution(resolution);
      return null;
    }
    try {
      final objectUrl = await resolution.timeout(wait);
      if (objectUrl == null) return null;
      if (!_isResolutionCurrent(attempt, widget.src)) {
        GlbAssetCache.revoke(objectUrl);
        return null;
      }
      return _ResolvedGlb(objectUrl: objectUrl, sourceUrl: sourceUrl);
    } on TimeoutException {
      // Future.timeout cannot cancel the JS fetch. Revoke its object URL if it
      // completes after this attempt has moved on.
      _discardResolution(resolution);
      return null;
    } catch (_) {
      return null;
    }
  }

  void _discardResolution(Future<String?>? resolution) {
    if (resolution == null) return;
    unawaited(
      resolution.then<void>((objectUrl) {
        if (objectUrl != null) GlbAssetCache.revoke(objectUrl);
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  Duration _resolutionRemaining(Stopwatch timer) {
    final remaining = _resolutionBudget - timer.elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _boundedWait(Duration requested, Duration remaining) =>
      requested < remaining ? requested : remaining;

  String _candidateKey(String modelUrl, String? workflowId) =>
      '${modelUrl.trim()}\n${workflowId?.trim() ?? ''}';

  bool _isResolutionCurrent(int attempt, String src) =>
      mounted && attempt == _resolveAttempt && src == widget.src;

  void _invalidateResolution() {
    _resolveAttempt++;
  }

  void _loadResolvedModel(
    _ResolvedGlb resolved, {
    required String expectedSrc,
    required int attempt,
  }) {
    if (!_isResolutionCurrent(attempt, expectedSrc)) {
      GlbAssetCache.revoke(resolved.objectUrl);
      return;
    }
    if (_resolvedSrc != null && _resolvedSrc != resolved.objectUrl) {
      GlbAssetCache.revoke(_resolvedSrc!);
    }
    setState(() {
      _resolvedSrc = resolved.objectUrl;
      _loadedSourceModelUrl = resolved.sourceUrl;
      _loadError = false;
    });
    _iframe.src = _buildViewerUrl(resolved.objectUrl);
    _postEditConfigSoon(expectedSrc, attempt);
  }

  void _postEditConfigSoon(String expectedSrc, int attempt) {
    for (final delay in const [
      Duration(milliseconds: 250),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 2500),
    ]) {
      Future<void>.delayed(delay, () {
        if (!_isResolutionCurrent(attempt, expectedSrc)) return;
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
      'autoRotate': widget.autoRotate.toString(),
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
        // Null/empty values are intentional clears. Omitting them would let
        // metadata restored from IndexedDB leak into a different model.
        'modelArtifact': widget.modelArtifact,
        'codeArtifact': widget.codeArtifact,
        'jointsArtifact': widget.jointsArtifact,
        'joints': widget.joints,
        'sourceModelUrl': _loadedSourceModelUrl ?? widget.src,
        'instructionPrompt': widget.instructionPrompt ?? '',
        'sourceWorkflowId': widget.sourceWorkflowId ?? '',
        'assetVersions': widget.assetVersions
            .map((version) => version.toJson())
            .toList(),
        'editModelOptions': _editModelOptionsPayload(),
        'editDefaultModelId': widget.defaultEditModelOptionId ?? '',
      }.jsify(),
      web.window.location.origin.toJS,
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
    if (request.requestType == 'uv_maps') {
      _runUvMaps(
        requestId: request.requestId,
        codeArtifact: request.codeArtifact ?? widget.codeArtifact,
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

  // UV maps: derive atlases from the CURRENT version's code, package the
  // checker GLB + atlas SVGs into a zip, and trigger a browser download. Never
  // produces an asset version. Self-contained (mirrors _runEditWorkflow) so the
  // editor path has no coupling to the Flutter tab's provider.
  Future<void> _runUvMaps({
    required String requestId,
    required Map<String, dynamic>? codeArtifact,
  }) async {
    final hasCode =
        codeArtifact != null &&
        ((codeArtifact['uri'] is String &&
                (codeArtifact['uri'] as String).isNotEmpty) ||
            (codeArtifact['url'] is String &&
                (codeArtifact['url'] as String).isNotEmpty));
    if (!hasCode) {
      _postUvResult({
        'requestId': requestId,
        'status': 'failed',
        'message':
            'This model has no editable code yet. Generate it again first.',
      });
      return;
    }
    final cad = ref.read(cadServiceProvider);
    try {
      _postUvResult({
        'requestId': requestId,
        'status': 'running',
        'message': 'Starting UV unwrap...',
      });
      final sets = await cad.runUvMapsBundle(
        codeArtifact: codeArtifact,
        conversationId: widget.conversationId,
        onProgress: (message) => _postUvResult({
          'requestId': requestId,
          'status': 'running',
          'message': message,
        }),
      );
      final good = sets.where((s) => s.result.hasMaps).toList();
      if (good.isEmpty) {
        final err = sets
            .map((s) => s.result.errorMessage)
            .firstWhere((e) => e != null, orElse: () => null);
        _postUvResult({
          'requestId': requestId,
          'status': 'failed',
          'message': err ?? 'UV maps could not be generated.',
        });
        return;
      }
      if (!mounted) return;
      _postUvResult({
        'requestId': requestId,
        'status': 'running',
        'message': 'Packaging UV maps...',
      });
      await downloadUvMapsZip(good, fileName: 'nova3d_uv_maps.zip');
      _postUvResult({
        'requestId': requestId,
        'status': 'completed',
        'message': 'UV maps downloaded.',
      });
    } on CadException catch (e) {
      _postUvResult({
        'requestId': requestId,
        'status': 'failed',
        'message': e.message,
      });
    } catch (_) {
      _postUvResult({
        'requestId': requestId,
        'status': 'failed',
        'message': 'UV map generation failed. Try again.',
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
        atlasMode: (request['atlasMode'] as String?) ?? '',
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
      web.window.location.origin.toJS,
    );
  }

  void _postVersionResolveResult(Map<String, dynamic> payload) {
    _iframe.contentWindow?.postMessage(
      {'type': 'nova3d-version-resolve-result', ...payload}.jsify(),
      web.window.location.origin.toJS,
    );
  }

  void _postUvResult(Map<String, dynamic> payload) {
    _iframe.contentWindow?.postMessage(
      {'type': 'nova3d-uv-result', ...payload}.jsify(),
      web.window.location.origin.toJS,
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
    this.atlasMode = '',
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
  final String atlasMode;
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
