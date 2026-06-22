import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifecycle of a UV-map generation for one model version.
enum UvPhase { idle, running, done, failed }

class UvMapsState {
  const UvMapsState(this.phase, {this.progress, this.sets, this.error});

  final UvPhase phase;
  final String? progress;
  final List<UvMapsSet>? sets;
  final String? error;

  static const idle = UvMapsState(UvPhase.idle);

  bool get isBusy => phase == UvPhase.running;

  /// Any set's checker GLB (all sets share the same geometry).
  String? get checkerGlbUrl {
    for (final s in sets ?? const <UvMapsSet>[]) {
      if (s.result.checkerGlbUrl != null) return s.result.checkerGlbUrl;
    }
    return null;
  }
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

  static String _storeKey(String key) => 'uvmaps_v1:$key';

  /// Load persisted maps for [key] if present and nothing is in memory yet.
  /// This is what makes already-generated maps reappear after a page refresh
  /// instead of forcing (and re-billing) a fresh run.
  Future<void> restore(String key) async {
    if (state.containsKey(key)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey(key));
      if (raw == null) return;
      if (state.containsKey(key)) return; // a run started while we awaited
      final decoded = json.decode(raw);
      if (decoded is! List) return;
      final sets = decoded
          .whereType<Map>()
          .map((e) => UvMapsSet.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.result.hasMaps)
          .toList();
      if (sets.isNotEmpty) {
        _set(key, UvMapsState(UvPhase.done, sets: sets));
      }
    } catch (_) {
      // Corrupt/absent cache is non-fatal — the user can regenerate.
    }
  }

  Future<void> _persist(String key, List<UvMapsSet> sets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storeKey(key),
        json.encode(sets.map((s) => s.toJson()).toList()),
      );
    } catch (_) {
      // Persistence is best-effort; failure just means a refresh re-generates.
    }
  }

  Future<void> generate({
    required String key,
    required Map<String, dynamic> codeArtifact,
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
      final sets = await cad.runUvMapsBundle(
        codeArtifact: codeArtifact,
        conversationId: conversationId,
        onProgress: (message) {
          // Stay in `running` even if the user navigated away and back.
          if (stateFor(key).phase == UvPhase.running) {
            _set(key, UvMapsState(UvPhase.running, progress: message));
          }
        },
      );
      final good = sets.where((s) => s.result.hasMaps).toList();
      if (good.isEmpty) {
        final err = sets
            .map((s) => s.result.errorMessage)
            .firstWhere((e) => e != null, orElse: () => null);
        _set(
          key,
          UvMapsState(
            UvPhase.failed,
            error: err ?? 'UV maps could not be generated.',
          ),
        );
      } else {
        _set(key, UvMapsState(UvPhase.done, sets: good));
        unawaited(_persist(key, good));
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
