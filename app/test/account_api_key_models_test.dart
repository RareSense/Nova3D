import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/account_api_keys/models/account_api_key_models.dart';

void main() {
  test('parses account API key metadata without exposing the full key', () {
    final key = AccountApiKey.fromJson({
      'id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      'name': 'Work laptop',
      'display_prefix': 'xK7mABC',
      'created_at': '2026-05-28T10:00:00Z',
      'last_used_at': null,
      'is_active': true,
      'revoked_at': null,
    });

    expect(key.name, 'Work laptop');
    expect(key.displayPrefix, 'xK7mABC');
    expect(key.maskedKey, startsWith('n3d_xK7mABC'));
    expect(key.maskedKey, isNot(contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ')));
    expect(key.lastUsedAt, isNull);
    expect(key.isActive, isTrue);
  });

  test('parses one-time created key response', () {
    final created = CreatedAccountApiKey.fromJson({
      'id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      'name': 'Claude Code',
      'key': 'n3d_xK7mABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abc',
      'display_prefix': 'xK7mABC',
      'created_at': '2026-05-29T12:00:00Z',
      'is_active': true,
      'revoked_at': null,
    });

    expect(created.key, startsWith('n3d_'));
    expect(created.maskedKey, 'n3d_xK7mABC************************');
  });
}
