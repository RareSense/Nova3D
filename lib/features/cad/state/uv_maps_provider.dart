import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';

/// Lifecycle of a UV-map generation for one model version.
enum UvPhase { idle, running, done, failed }

class UvMapsState {
  const UvMapsState(this.phase, {this.progress, this.result, this.error});

  final UvPhase phase;
  final String? progress;
  final UvMapsResult? result;
  final String? error;

  static const idle = UvMapsState(UvPhase.idle);

  bool get isBusy => phase == UvPhase.running;
}

/// Stable key for a version's UV maps: the source CODE identity. Two versions
/// with the same code share a result; an edited version (new code) gets its own.
/// Falls back to the source workflow id when no code uri is present.
String uvMapsKey(Map<String, dynamic>? codeArtifact, {String? sourceWorkflowId}) {
  final uri = codeArtifact?['uri'];
  if (uri is String && uri.isNotEmpty) return 'code:$uri';
  final url = codeArtifact?['url'];
  if (url is String && url.isNotEmpty) return 'code:$url';
  final wf = (sourceWorkflowId ?? '').trim();
  return wf.isEmpty ? 'unknown' : 'wf:$wf';
}

/// Session cache of UV-map state per version key. Not auto-disposed, so results
/// survive tab switches and version switches within a session. The backend is
/// deterministic (input-hash cached), so a re-run after reload is a cheap hit.
class UvMapsNotifier extends Notifier<Map<String, UvMapsState>> {
  @override
  Map<String, UvMapsState> build() => const {};

  UvMapsState stateFor(String key) => state[key] ?? UvMapsState.idle;

  Future<void> generate({
    required String key,
    required Map<String, dynamic> codeArtifact,
    String atlasMode = 'budget',
    String? conversationId,
  }) async {
    final current = stateFor(key);
    // Dedupe: never double-run, and keep a completed result.
    if (current.phase == UvPhase.running || current.phase == UvPhase.done) {
      return;
    }
    _set(key, const UvMapsState(UvPhase.running, progress: 'Starting UV unwrap…'));

    final cad = ref.read(cadServiceProvider);
    try {
      final workflowId = await cad.startUvMaps(
        codeArtifact: codeArtifact,
        atlasMode: atlasMode,
        conversationId: conversationId,
      );
      final result = await cad.runUvMapsWorkflow(
        workflowId,
        onProgress: (status) {
          // Stay in `running` even if the user navigated away and back.
          if (stateFor(key).phase == UvPhase.running) {
            _set(key, UvMapsState(UvPhase.running, progress: status.progressLabel));
          }
        },
      );
      if (result.failed || !result.hasMaps) {
        _set(
          key,
          UvMapsState(
            UvPhase.failed,
            error: result.errorMessage ?? 'UV maps could not be generated.',
          ),
        );
      } else {
        _set(key, UvMapsState(UvPhase.done, result: result));
      }
    } on CadException catch (e) {
      _set(key, UvMapsState(UvPhase.failed, error: e.message));
    } catch (_) {
      _set(
        key,
        const UvMapsState(
          UvPhase.failed,
          error: 'UV map generation failed. Please try again.',
        ),
      );
    }
  }

  void reset(String key) {
    final next = Map<String, UvMapsState>.from(state)..remove(key);
    state = next;
  }

  void _set(String key, UvMapsState value) {
    state = {...state, key: value};
  }
}

final uvMapsProvider =
    NotifierProvider<UvMapsNotifier, Map<String, UvMapsState>>(
      UvMapsNotifier.new,
    );
