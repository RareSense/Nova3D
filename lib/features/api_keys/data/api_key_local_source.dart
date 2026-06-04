import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefix = 'nova3d_api_key_';
const _kValidPrefix = 'nova3d_api_key_valid_';

class ApiKeyLocalSource {
  String _keyName(AiProvider p) => '$_kPrefix${p.id}';
  String _validName(AiProvider p) => '$_kValidPrefix${p.id}';

  Future<Map<AiProvider, ProviderKeyState>> loadStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
      return {for (final p in AiProvider.values) p: ProviderKeyState(provider: p)};
    }
  }

  Future<Map<String, String>> loadValidKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  Future<void> save(
    AiProvider provider,
    String apiKey, {
    required bool isValid,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyName(provider), apiKey);
      await prefs.setBool(_validName(provider), isValid);
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] save($provider) failed: $e\n$st');
    }
  }

  Future<void> clear(AiProvider provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyName(provider));
      await prefs.remove(_validName(provider));
    } catch (e, st) {
      debugPrint('[ApiKeyLocalSource] clear($provider) failed: $e\n$st');
    }
  }
}
