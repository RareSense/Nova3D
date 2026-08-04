// Domain-side analytics for GraphFlow runs.
//
// Lives under features/cad (not core/analytics) so the core layer stays pure
// infrastructure with no knowledge of Nova3D's workflow models.
//
// The point of the tracker is STAGE TIMING. A generation is a multi-minute
// multi-node graph, and "it was slow" is useless without knowing which node
// ate the time. `onStatus` turns each poll into a per-node duration.

import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';

/// Nodes that indicate the build stage was re-run.
const Set<String> _kRetryNodes = <String>{'build_repair_prompt', 'repair_llm'};

/// Node that runs only when the review stage produced an amended build.
const String _kAmendNode = 'validation_correction_blender';

/// Stable properties describing what the user asked for.
///
/// Prompt text is included only when `kCaptureUserContent` is on; the length
/// and word count are always sent so volume analysis survives a metadata-only
/// deployment.
Map<String, Object?> generationRequestProperties(GenerationRequest request) {
  final prompt = request.prompt.trim();
  return <String, Object?>{
    if (kCaptureUserContent && prompt.isNotEmpty) Pr.prompt: prompt,
    Pr.promptLength: prompt.length,
    Pr.promptWordCount: prompt.isEmpty
        ? 0
        : prompt.split(RegExp(r'\s+')).length,
    Pr.hasReferenceImages: request.hasImage,
    Pr.imageCount: request.images.length,
    ...modelOptionProperties(request.modelOption),
  };
}

/// Stable properties describing how the run is routed and billed.
Map<String, Object?> modelOptionProperties(GenerationModelOption option) {
  return <String, Object?>{
    Pr.modelOptionId: option.id,
    Pr.modelLabel: option.persistedLabel,
    Pr.codeLlmProfile: option.codeLlmProfile,
    Pr.codeLlmTier: option.codeLlmTier,
    Pr.provider: option.payloadProvider,
    Pr.billingMode: option.isPaidCredit ? 'credits' : 'byok',
    Pr.isByok: !option.isPaidCredit,
    Pr.workflowName: option.workflowName,
    Pr.credits: option.creditCost,
  };
}

/// Accumulates one workflow run and emits its lifecycle events.
///
/// One instance per run. Not reusable — construct a new tracker per attempt so
/// a retry is measured independently of the attempt it replaced.
class WorkflowRunTracker {
  WorkflowRunTracker({
    required this.nodeEvent,
    required this.succeededEvent,
    required this.failedEvent,
    required Map<String, Object?> baseProperties,
    this.isResume = false,
  }) : _base = Map<String, Object?>.unmodifiable(baseProperties);

  final String nodeEvent;
  final String succeededEvent;
  final String failedEvent;
  final bool isResume;
  final Map<String, Object?> _base;

  final Stopwatch _total = Stopwatch();
  final Stopwatch _sinceNode = Stopwatch();
  final Set<String> _nodesSeen = <String>{};

  String? _workflowId;
  String? _currentNode;
  int _stageRetries = 0;
  bool _sawAmendNode = false;

  /// Marks the run as accepted by GraphFlow. Emits [Ev.generationStarted]-style
  /// events at the call site; this only starts the clocks.
  void start(String workflowId) {
    _workflowId = workflowId;
    _total.start();
    _sinceNode.start();
  }

  /// Feeds one status poll in. Emits a node event only on an actual transition,
  /// so a 3-second poll loop does not produce one event per poll.
  void onStatus(WorkflowStatus status) {
    final node = status.currentNode ?? status.lastExitNode;
    if (node == null || node.isEmpty || node == _currentNode) return;

    final previous = _currentNode;
    final elapsedInPrevious = _sinceNode.elapsedMilliseconds;
    _sinceNode
      ..reset()
      ..start();
    _currentNode = node;
    _nodesSeen.add(node);

    if (_kRetryNodes.contains(node)) {
      // Both retry nodes fire per round; count only the first so one round
      // counts as one retry.
      if (node == 'build_repair_prompt') {
        _stageRetries++;
        analytics.capture(Ev.generationStageRetried, <String, Object?>{
          ..._base,
          Pr.workflowId: _workflowId,
          Pr.stageRetryCount: _stageRetries,
          Pr.totalElapsedMs: _total.elapsedMilliseconds,
        });
      }
    }
    if (node == _kAmendNode) _sawAmendNode = true;

    analytics.capture(nodeEvent, <String, Object?>{
      ..._base,
      Pr.workflowId: _workflowId,
      Pr.node: node,
      Pr.nodeLabel: status.progressLabel,
      Pr.previousNode: previous,
      // Duration of the node we just LEFT, which is the number worth charting.
      if (previous != null) Pr.nodeElapsedMs: elapsedInPrevious,
      Pr.totalElapsedMs: _total.elapsedMilliseconds,
      Pr.retryCount: status.retryCount,
    });
  }

  /// Which of the three review endings this run reached.
  ///
  /// CAVEAT: the client cannot distinguish a clean pass from "an amend was
  /// wanted but nothing shippable came out" — both terminate on the same node
  /// without visiting the amend node, so both collapse into
  /// [ReviewOutcome.pass]. Only a run that actually entered the amend node is
  /// classified confidently.
  String _reviewOutcome(String? terminalNode) {
    if (terminalNode == 'final_validated_correction') {
      return ReviewOutcome.amended;
    }
    if (_sawAmendNode) return ReviewOutcome.originalKept;
    return ReviewOutcome.pass;
  }

  /// Result-shape agnostic on purpose: generation returns `CadResult` and
  /// texturing returns `TextureResult`, and the tracker should not have to
  /// know either. Callers pass whatever result properties matter via [extra].
  void succeeded({Map<String, Object?> extra = const {}}) {
    _total.stop();
    _sinceNode.stop();
    analytics.capture(succeededEvent, <String, Object?>{
      ..._base,
      Pr.workflowId: _workflowId,
      Pr.succeeded: true,
      Pr.durationMs: _total.elapsedMilliseconds,
      Pr.terminalNode: _currentNode,
      Pr.reviewOutcome: _reviewOutcome(_currentNode),
      Pr.stageRetryCount: _stageRetries,
      Pr.hadStageRetry: _stageRetries > 0,
      Pr.nodesVisited: _nodesSeen.length,
      Pr.isResume: isResume,
      ...extra,
    });
  }

  void failed({
    String? message,
    String? category,
    bool? retryable,
    Map<String, Object?> extra = const {},
  }) {
    _total.stop();
    _sinceNode.stop();
    analytics.capture(failedEvent, <String, Object?>{
      ..._base,
      Pr.workflowId: _workflowId,
      Pr.succeeded: false,
      Pr.durationMs: _total.elapsedMilliseconds,
      Pr.terminalNode: _currentNode,
      Pr.stageRetryCount: _stageRetries,
      Pr.hadStageRetry: _stageRetries > 0,
      Pr.errorMessage: ?message,
      Pr.errorCategory: ?category,
      Pr.retryable: ?retryable,
      Pr.nodesVisited: _nodesSeen.length,
      Pr.isResume: isResume,
      ...extra,
    });
  }

  /// Factory for an initial sketch_to_3d run.
  static WorkflowRunTracker forGeneration(
    GenerationRequest request, {
    bool isResume = false,
  }) {
    final stageProperties = generationRequestProperties(request)
      // Raw content is attached once to generation_started. Repeating it on
      // every node/retry/terminal event increases exposure and event volume
      // without adding joinability; workflow_id links those events instead.
      ..remove(Pr.prompt);
    return WorkflowRunTracker(
      nodeEvent: Ev.generationNodeChanged,
      succeededEvent: Ev.generationSucceeded,
      failedEvent: Ev.generationFailed,
      isResume: isResume,
      baseProperties: stageProperties,
    );
  }

  /// Factory for a texture_3d_v2 run.
  static WorkflowRunTracker forTexture(Map<String, Object?> baseProperties) =>
      WorkflowRunTracker(
        nodeEvent: Ev.textureNodeChanged,
        succeededEvent: Ev.textureSucceeded,
        failedEvent: Ev.textureFailed,
        baseProperties: baseProperties,
      );
}
