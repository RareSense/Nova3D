class AccountApiKey {
  const AccountApiKey({
    required this.id,
    required this.name,
    required this.displayPrefix,
    required this.createdAt,
    required this.isActive,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String name;
  final String displayPrefix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool isActive;
  final DateTime? revokedAt;

  String get maskedKey => 'n3d_$displayPrefix************************';

  factory AccountApiKey.fromJson(Map<String, dynamic> json) => AccountApiKey(
    id: json['id'] as String,
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : 'Unnamed key',
    displayPrefix: json['display_prefix'] as String? ?? '',
    createdAt: _parseRequiredDate(json['created_at']),
    lastUsedAt: _parseOptionalDate(json['last_used_at']),
    isActive: json['is_active'] as bool? ?? false,
    revokedAt: _parseOptionalDate(json['revoked_at']),
  );
}

class CreatedAccountApiKey extends AccountApiKey {
  const CreatedAccountApiKey({
    required super.id,
    required super.name,
    required super.displayPrefix,
    required super.createdAt,
    required super.isActive,
    required this.key,
    super.lastUsedAt,
    super.revokedAt,
  });

  final String key;

  factory CreatedAccountApiKey.fromJson(Map<String, dynamic> json) =>
      CreatedAccountApiKey(
        id: json['id'] as String,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : 'Unnamed key',
        key: json['key'] as String,
        displayPrefix: json['display_prefix'] as String? ?? '',
        createdAt: _parseRequiredDate(json['created_at']),
        lastUsedAt: _parseOptionalDate(json['last_used_at']),
        isActive: json['is_active'] as bool? ?? true,
        revokedAt: _parseOptionalDate(json['revoked_at']),
      );
}

class AccountApiKeysResponse {
  const AccountApiKeysResponse({required this.keys});

  final List<AccountApiKey> keys;

  factory AccountApiKeysResponse.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['keys'] as List<dynamic>? ?? const [];
    return AccountApiKeysResponse(
      keys: rawKeys
          .map((key) => AccountApiKey.fromJson(key as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AccountMe {
  const AccountMe({
    required this.userId,
    required this.email,
    required this.availableCredits,
    this.tenantId,
  });

  final String userId;
  final String email;
  final int availableCredits;
  final String? tenantId;

  factory AccountMe.fromJson(Map<String, dynamic> json) => AccountMe(
    userId: json['user_id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    availableCredits: (json['available_credits'] as num?)?.toInt() ?? 0,
    tenantId: json['tenant_id'] as String?,
  );
}

DateTime _parseRequiredDate(Object? value) {
  final parsed = _parseOptionalDate(value);
  if (parsed == null) {
    throw const FormatException('Expected ISO-8601 date string');
  }
  return parsed;
}

DateTime? _parseOptionalDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.parse(value).toLocal();
}
