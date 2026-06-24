import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';

void main() {
  test('extracts GLB URL from successful sketch_to_3d output', () {
    final result = CadResult.fromJson({
      'sketch_to_3d_generator': [
        {
          'model_url': 'https://example.test/model.glb',
          'provider': 'openrouter',
        },
      ],
    });

    expect(result.failed, isFalse);
    expect(result.glbUrl, 'https://example.test/model.glb');
    expect(result.errorMessage, isNull);
  });

  test('extracts code artifact from generation result', () {
    final result = CadResult.fromJson({
      'sketch_to_3d_generator': [
        {
          'model_url': 'https://example.test/model.glb',
          'code_artifact': {
            'url': 'https://example.test/model.py',
            'content_type': 'text/x-python; charset=utf-8',
          },
        },
      ],
    });

    expect(result.failed, isFalse);
    expect(result.codeArtifact?['url'], 'https://example.test/model.py');
  });

  test('extracts edit workflow output', () {
    final result = CadResult.fromJson({
      'regenerate_3d_part': [
        {
          'result': {
            'model_url': 'https://example.test/edited.glb',
            'code_artifact': {'url': 'https://example.test/edited.py'},
          },
        },
      ],
    });

    expect(result.failed, isFalse);
    expect(result.glbUrl, 'https://example.test/edited.glb');
    expect(result.codeArtifact?['url'], 'https://example.test/edited.py');
  });

  test('extracts paid v2 final output', () {
    final result = CadResult.fromJson({
      'final_latest_valid': [
        {
          'status': 'completed',
          'ok': true,
          'glb_artifact': {'url': 'https://example.test/paid.glb'},
          'code_artifact': {'url': 'https://example.test/paid.py'},
        },
      ],
    });

    expect(result.failed, isFalse);
    expect(result.glbUrl, 'https://example.test/paid.glb');
    expect(result.modelArtifact?['url'], 'https://example.test/paid.glb');
    expect(result.codeArtifact?['url'], 'https://example.test/paid.py');
  });

  test('extracts byok v2 key-gate failure', () {
    final result = CadResult.fromJson({
      'require_byok_api_key': [
        {
          'user_message':
              'code_llm_api_key is required for sketch_to_3d_byok_v2.',
          'error_category': 'missing_api_key',
          'failure_origin': 'api_key_or_provider_account',
        },
      ],
    });

    expect(result.failed, isTrue);
    expect(
      result.errorMessage,
      'code_llm_api_key is required for sketch_to_3d_byok_v2.',
    );
    expect(result.errorCategory, 'missing_api_key');
  });

  test('extracts structured soft failure from nested tool result', () {
    final result = CadResult.fromJson({
      'sketch_to_3d_generator': [
        {
          'result': {
            'status': 'failed',
            'ok': false,
            'failure': {
              'category': 'model_access_denied',
              'user_message':
                  'OpenRouter does not allow this key to use the selected model.',
              'provider': 'openrouter',
              'retryable': false,
            },
          },
        },
      ],
    });

    expect(result.failed, isTrue);
    expect(result.glbUrl, isNull);
    expect(
      result.errorMessage,
      'OpenRouter does not allow this key to use the selected model.',
    );
    expect(result.errorCategory, 'model_access_denied');
    expect(result.provider, 'openrouter');
    expect(result.retryable, isFalse);
  });

  test('builds user message from failure category when message is absent', () {
    final result = CadResult.fromJson({
      'sketch_to_3d_generator': [
        {
          'status': 'failed',
          'failure': {'category': 'insufficient_credits', 'provider': 'gemini'},
        },
      ],
    });

    expect(result.failed, isTrue);
    expect(result.errorMessage, contains('gemini'));
    expect(result.errorMessage, contains('credits'));
  });
}
