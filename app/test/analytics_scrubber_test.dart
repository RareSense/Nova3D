// Tests for the analytics privacy boundary.
//
// These are the tests that matter most in the analytics stack: everything else
// is plumbing, but a regression here leaks a user's provider key into an
// third-party analytics store where it cannot be recalled. Nova3D captures full
// prompt text, so "a key pasted into a prompt" is a realistic accident rather
// than a hypothetical.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/core/analytics/analytics_scrubber.dart';

void main() {
  group('property name denylist', () {
    test('drops credential-shaped property names', () {
      final result = scrubProperties(<String, Object?>{
        'model_option_id': 'openrouter_gpt55',
        'api_key': 'sk-should-never-appear',
        'code_llm_api_key': 'sk-ant-should-never-appear',
        'authorization': 'Bearer abc',
        'user_password': 'hunter2',
        'client_secret': 'shhh',
        'access_token': 'abc123',
      });

      expect(result.keys, <String>['model_option_id']);
    });

    test('keeps ordinary properties untouched', () {
      final result = scrubProperties(<String, Object?>{
        'prompt': 'a wooden chair',
        'prompt_length': 14,
        'is_byok': true,
        'duration_ms': 1234,
      });

      expect(result['prompt'], 'a wooden chair');
      expect(result['prompt_length'], 14);
      expect(result['is_byok'], true);
      expect(result['duration_ms'], 1234);
    });

    test('drops nulls so PostHog filters stay clean', () {
      final result = scrubProperties(<String, Object?>{
        'kept': 'yes',
        'dropped': null,
      });

      expect(result.containsKey('dropped'), isFalse);
      expect(result['kept'], 'yes');
    });
  });

  group('secret value redaction', () {
    test('redacts every supported provider key shape', () {
      const samples = <String, String>{
        'openai': 'sk-abcdefghijklmnopqrstuvwxyz012345',
        'anthropic': 'sk-ant-api03-AbCdEfGhIjKlMnOpQrSt',
        'gemini': 'AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStU',
        'nova3d_mcp': 'n3d_live_abcdefghijklmnop',
        'posthog': 'phc_abcdefghijklmnopqrstuvwxyz0123',
        'jwt': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27u',
      };

      for (final entry in samples.entries) {
        final scrubbed = redactSecrets('my key is ${entry.value} ok');
        expect(
          scrubbed.contains(entry.value),
          isFalse,
          reason: '${entry.key} key survived redaction',
        );
        expect(scrubbed, contains(kRedacted));
      }
    });

    test('redacts a key pasted into prompt text', () {
      final result = scrubProperties(<String, Object?>{
        'prompt': 'build a chair, my key is sk-abcdefghijklmnopqrstuvwxyz012345',
      });

      expect(result['prompt'], isNot(contains('sk-abcdefghij')));
      expect(result['prompt'], contains('build a chair'));
      expect(result['prompt'], contains(kRedacted));
    });

    test('redacts secrets nested inside lists and maps', () {
      final result = scrubProperties(<String, Object?>{
        'selected_mesh_names': <String>[
          'Body_Shell',
          'sk-ant-api03-AbCdEfGhIjKlMnOpQrSt',
        ],
        'nested': <String, Object?>{
          'inner_prompt': 'AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStU',
          'api_key': 'sk-abcdefghijklmnopqrstuvwxyz012345',
        },
      });

      final names = result['selected_mesh_names'] as List<Object?>;
      expect(names.first, 'Body_Shell');
      expect(names.last, kRedacted);

      final nested = result['nested'] as Map<String, Object?>;
      expect(nested['inner_prompt'], kRedacted);
      // Denied names are dropped at every depth, not just the top level.
      expect(nested.containsKey('api_key'), isFalse);
    });

    test('leaves innocuous short strings that merely start with sk-', () {
      // The length floor exists so ordinary words are not mangled.
      expect(redactSecrets('sk-short'), 'sk-short');
    });
  });

  group('bounds', () {
    test('truncates oversized strings and reports the original length', () {
      final long = 'x' * (kMaxStringLength + 500);
      final result = truncate(long);

      expect(result.length, lessThan(long.length));
      expect(result, contains('truncated ${long.length} chars'));
    });

    test('does not truncate strings at the limit', () {
      final exact = 'x' * kMaxStringLength;
      expect(truncate(exact), exact);
    });

    test('caps list properties', () {
      final result = scrubProperties(<String, Object?>{
        'selected_mesh_names': List<String>.generate(
          kMaxListLength + 25,
          (i) => 'Part_$i',
        ),
      });

      expect((result['selected_mesh_names'] as List<Object?>).length,
          kMaxListLength);
    });

    test('stack traces get the larger cap', () {
      final stack = 'y' * (kMaxStringLength + 100);
      expect(truncate(stack, maxLength: kMaxStackLength), stack);
    });
  });
}
