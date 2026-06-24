class McpIdentity {
  const McpIdentity({
    required this.userId,
    required this.email,
    required this.tenantId,
  });

  final String userId;
  final String email;
  final String tenantId;

  factory McpIdentity.fromJson(Map<String, dynamic> json) => McpIdentity(
    userId: (json['user_id'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
  );
}

class McpSessionInfo {
  const McpSessionInfo({required this.established, this.expiresAt});

  final bool established;
  final DateTime? expiresAt;

  factory McpSessionInfo.fromJson(Map<String, dynamic> json) => McpSessionInfo(
    established: json['established'] == true,
    expiresAt: _dateTimeFromJson(json['expires_at']),
  );
}

class McpCredits {
  const McpCredits({
    required this.balance,
    required this.reserved,
    required this.available,
    required this.funded,
  });

  final int balance;
  final int reserved;
  final int available;
  final bool funded;

  factory McpCredits.fromJson(Map<String, dynamic> json) => McpCredits(
    balance: _intFromJson(json['balance']),
    reserved: _intFromJson(json['reserved']),
    available: _intFromJson(json['available']),
    funded: json['funded'] == true,
  );
}

class McpStatus {
  const McpStatus({
    required this.authenticated,
    required this.identity,
    required this.mcpSession,
    required this.credits,
    required this.generationReady,
    required this.nextAction,
    required this.nextActionUrl,
  });

  final bool authenticated;
  final McpIdentity? identity;
  final McpSessionInfo? mcpSession;
  final McpCredits? credits;
  final bool generationReady;
  final String? nextAction;
  final String? nextActionUrl;

  bool get needsPurchase =>
      nextAction == 'purchase_credits' ||
      (credits != null && !credits!.funded && credits!.available <= 0);

  factory McpStatus.fromJson(Map<String, dynamic> json) => McpStatus(
    authenticated: json['authenticated'] == true,
    identity: json['identity'] is Map<String, dynamic>
        ? McpIdentity.fromJson(json['identity'] as Map<String, dynamic>)
        : json['identity'] is Map
        ? McpIdentity.fromJson(
            Map<String, dynamic>.from(json['identity'] as Map),
          )
        : null,
    mcpSession: json['mcp_session'] is Map<String, dynamic>
        ? McpSessionInfo.fromJson(json['mcp_session'] as Map<String, dynamic>)
        : json['mcp_session'] is Map
        ? McpSessionInfo.fromJson(
            Map<String, dynamic>.from(json['mcp_session'] as Map),
          )
        : null,
    credits: json['credits'] is Map<String, dynamic>
        ? McpCredits.fromJson(json['credits'] as Map<String, dynamic>)
        : json['credits'] is Map
        ? McpCredits.fromJson(Map<String, dynamic>.from(json['credits'] as Map))
        : null,
    generationReady: json['generation_ready'] == true,
    nextAction: _stringOrNull(json['next_action']),
    nextActionUrl: _stringOrNull(json['next_action_url']),
  );
}

int _intFromJson(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}

String? _stringOrNull(Object? value) {
  final parsed = (value ?? '').toString().trim();
  return parsed.isEmpty || parsed == 'null' ? null : parsed;
}
