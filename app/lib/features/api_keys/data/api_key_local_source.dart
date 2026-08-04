import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefix = 'nova3d_api_key_';
const _kValidPrefix = 'nova3d_api_key_valid_';
const _storageTimeout = Duration(seconds: 2);
const _pendingWriteTimeout = Duration(seconds: 5);

class ApiKeyLocalSource {
  static int _credentialEpoch = 0;
  static final Set<Future<void>> _pendingWrites = <Future<void>>{};
  static final Map<AiProvider, Future<void>> _lateWriteCleanups =
      <AiProvider, Future<void>>{};

  static int get credentialEpoch => _credentialEpoch;

  /// Synchronously makes every validation/save started before this call stale.
  static void invalidatePendingSaves() {
    _credentialEpoch++;
  }

  String _keyName(AiProvider p) => '$_kPrefix${p.id}';
  String _validName(AiProvider p) => '$_kValidPrefix${p.id}';

  Future<Map<AiProvider, ProviderKeyState>> loadStates() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      return {
        for (final p in AiProvider.values)
          p: ProviderKeyState(
            provider: p,
            hasKey: (prefs.getString(_keyName(p)) ?? '').isNotEmpty,
            isValid: prefs.getBool(_validName(p)) ?? false,
          ),
      };
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] loadStates failed: $e\n$st');
      return {
        for (final p in AiProvider.values) p: ProviderKeyState(provider: p),
      };
    }
  }

  Future<Map<String, String>> loadValidKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      final keys = <String, String>{};
      for (final p in AiProvider.values) {
        final key = prefs.getString(_keyName(p));
        final valid = prefs.getBool(_validName(p)) ?? false;
        if (valid && key != null && key.isNotEmpty) keys[p.id] = key;
      }
      return keys;
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] loadValidKeys failed: $e\n$st');
      return {};
    }
  }

  Future<bool> save(
    AiProvider provider,
    String apiKey, {
    required bool isValid,
    required int expectedEpoch,
  }) {
    final operation = _save(
      provider,
      apiKey,
      isValid: isValid,
      expectedEpoch: expectedEpoch,
    );
    _trackBoundaryOperation(operation.then<void>((_) {}));
    return operation;
  }

  Future<bool> _save(
    AiProvider provider,
    String apiKey, {
    required bool isValid,
    required int expectedEpoch,
  }) async {
    SharedPreferences? prefs;
    Future<List<bool>>? pendingWrites;
    try {
      if (expectedEpoch != _credentialEpoch) return false;
      final lateCleanup = _lateWriteCleanups[provider];
      if (lateCleanup != null) {
        try {
          await lateCleanup.timeout(_pendingWriteTimeout);
        } catch (_) {
          return false;
        }
      }
      prefs = await SharedPreferences.getInstance().timeout(_storageTimeout);
      if (expectedEpoch != _credentialEpoch) return false;
      pendingWrites = Future.wait<bool>(<Future<bool>>[
        prefs.setString(_keyName(provider), apiKey),
        prefs.setBool(_validName(provider), isValid),
      ]);
      final writes = await pendingWrites.timeout(_storageTimeout);
      if (expectedEpoch != _credentialEpoch) {
        await _removeProvider(prefs, provider);
        return false;
      }
      return writes.every((result) => result) &&
          prefs.getString(_keyName(provider)) == apiKey &&
          prefs.getBool(_validName(provider)) == isValid;
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] save($provider) failed: $e\n$st');
      if (prefs != null) {
        try {
          await _removeProvider(prefs, provider);
        } catch (_) {
          // The deferred cleanup below gets another chance after a platform
          // write that outlived its Dart timeout finally completes.
        }
        if (pendingWrites != null) {
          _trackLateWriteCleanup(
            provider,
            _removeProviderAfter(pendingWrites, prefs, provider),
          );
        }
      }
      return false;
    }
  }

  Future<bool> clear(AiProvider provider, {required int expectedEpoch}) {
    final operation = _clear(provider, expectedEpoch: expectedEpoch);
    _trackBoundaryOperation(operation.then<void>((_) {}));
    return operation;
  }

  Future<bool> _clear(AiProvider provider, {required int expectedEpoch}) async {
    try {
      if (expectedEpoch != _credentialEpoch) return false;
      final lateCleanup = _lateWriteCleanups[provider];
      if (lateCleanup != null) {
        try {
          await lateCleanup.timeout(_pendingWriteTimeout);
        } catch (_) {
          return false;
        }
      }
      final prefs = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      if (expectedEpoch != _credentialEpoch) return false;
      final removed = await _removeProvider(prefs, provider);
      return expectedEpoch == _credentialEpoch && removed;
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] clear($provider) failed: $e\n$st');
      return false;
    }
  }

  /// Removes all browser-stored provider credentials at an authentication
  /// boundary so a later account cannot inherit another user's BYOK keys.
  Future<bool> clearAll() async {
    invalidatePendingSaves();
    var pendingSettled = true;
    try {
      // Invalidate validations that have not reached persistence, then wait
      // for writes already inside storage and any cleanup they spawn.
      await _settlePendingWrites();
    } catch (e, st) {
      pendingSettled = false;
      debugPrint('[ApiKeyLocalSource] pending writes did not settle: $e\n$st');
    }

    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      final removed = await _removeAll(prefs);

      // A platform storage call can outlive its Dart timeout. If that ever
      // happens, repeat deletion after the outstanding calls finally settle.
      if (!pendingSettled) {
        unawaited(_removeAgainAfterPendingWrites());
      }
      return pendingSettled && removed;
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] clearAll failed: $e\n$st');
      return false;
    }
  }

  Future<bool> _removeProvider(
    SharedPreferences prefs,
    AiProvider provider,
  ) async {
    final names = <String>[_keyName(provider), _validName(provider)];
    final removals = <Future<bool>>[
      for (final name in names)
        if (prefs.containsKey(name)) prefs.remove(name),
    ];
    final results = await Future.wait<bool>(removals).timeout(_storageTimeout);
    return results.every((result) => result) &&
        names.every((name) => !prefs.containsKey(name));
  }

  Future<bool> _removeAll(SharedPreferences prefs) async {
    final results = await Future.wait<bool>(<Future<bool>>[
      for (final provider in AiProvider.values) ...<Future<bool>>[
        if (prefs.containsKey(_keyName(provider)))
          prefs.remove(_keyName(provider)),
        if (prefs.containsKey(_validName(provider)))
          prefs.remove(_validName(provider)),
      ],
    ]).timeout(_storageTimeout);
    return results.every((result) => result) &&
        AiProvider.values.every(
          (provider) =>
              !prefs.containsKey(_keyName(provider)) &&
              !prefs.containsKey(_validName(provider)),
        );
  }

  Future<void> _settlePendingWrites() async {
    final stopwatch = Stopwatch()..start();
    while (_pendingWrites.isNotEmpty) {
      final remaining = _pendingWriteTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Credential writes did not settle.');
      }
      final batch = List<Future<void>>.from(_pendingWrites);
      await Future.wait<void>(batch).timeout(remaining);
    }
  }

  Future<void> _removeAgainAfterPendingWrites() async {
    try {
      while (_pendingWrites.isNotEmpty) {
        await Future.wait<void>(List<Future<void>>.from(_pendingWrites));
      }
      final prefs = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      await _removeAll(prefs);
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] deferred clearAll failed: $e\n$st');
    }
  }

  Future<void> _removeProviderAfter(
    Future<List<bool>> pending,
    SharedPreferences prefs,
    AiProvider provider,
  ) async {
    try {
      await pending;
      final removed = await _removeProvider(prefs, provider);
      if (!removed) {
        throw StateError('Provider key removal could not be verified.');
      }
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] deferred save cleanup failed: $e\n$st');
      rethrow;
    }
  }

  static void _trackBoundaryOperation(Future<void> operation) {
    late final Future<void> tracked;
    tracked = operation
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _pendingWrites.remove(tracked));
    _pendingWrites.add(tracked);
  }

  static void _trackLateWriteCleanup(
    AiProvider provider,
    Future<void> cleanup,
  ) {
    late final Future<void> lifecycle;
    lifecycle = cleanup.whenComplete(() {
      if (identical(_lateWriteCleanups[provider], lifecycle)) {
        _lateWriteCleanups.remove(provider);
      }
    });
    _lateWriteCleanups[provider] = lifecycle;
    _trackBoundaryOperation(lifecycle);
  }
}
