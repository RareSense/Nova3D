// Property scrubbing for analytics events — the privacy boundary.
//
// Deliberately PURE DART with no `dart:js_interop` import, for two reasons:
//   1. It is the security-critical part of the analytics path, so it must be
//      unit-testable on the VM. Anything importing js_interop cannot run under
//      `flutter test`.
//   2. It has no business knowing about PostHog at all.
//
// What it guarantees about every event leaving the app:
//   * No property whose NAME looks like a credential.
//   * No VALUE matching a known provider-key shape, even nested in a prompt.
//   * No unbounded strings or lists.
//   * No nulls (PostHog stores them as real values and they pollute filters).

/// Property values longer than this are truncated. Guards against a pasted
/// document blowing up an event payload — PostHog drops oversized events, so an
/// unbounded string means losing the whole event, not just the property.
const int kMaxStringLength = 2000;

/// Stack traces earn a longer cap; a truncated stack is a useless stack.
const int kMaxStackLength = 8000;

/// At most this many elements survive from a list property (e.g. mesh names on
/// a 500-part model).
const int kMaxListLength = 50;

/// Bounds untrusted maps forwarded by the viewer iframe.
const int kMaxMapEntries = 50;

/// Prevents cyclic or attacker-crafted nested values from exhausting the UI
/// thread while an analytics event is being sanitized.
const int kMaxNestingDepth = 5;

const String kRedacted = '[redacted]';

/// Property names containing any of these are dropped outright.
const List<String> kDeniedNameFragments = <String>[
  'api_key',
  'apikey',
  'access_token',
  'account_key',
  'auth_token',
  'authorization',
  'bearer',
  'cookie',
  'credential',
  'id_token',
  'password',
  'private_key',
  'refresh_token',
  'sas_token',
  'secret',
  'session_token',
  'signed_url',
];

/// Shapes that identify provider credentials in free text.
///
/// This exists because Nova3D captures full prompt text: a user pasting a key
/// into a prompt box is a realistic accident, and the name-based denylist above
/// cannot catch it. Matching text is replaced rather than dropped so the event
/// still records that something was present.
final RegExp kSecretValuePattern = RegExp(
  r'(sk-ant-[A-Za-z0-9\-_]{8,})' // Anthropic
  r'|(sk-[A-Za-z0-9\-_]{16,})' // OpenAI / OpenRouter, incl. proj/or-v1
  r'|([sr]k_live_[A-Za-z0-9]{16,})' // Stripe secret/restricted keys
  r'|(AIza[A-Za-z0-9\-_]{16,})' // Google / Gemini
  r'|(n3d_[A-Za-z0-9\-_]{8,})' // Nova3D MCP key
  r'|(ph[ctx]_[A-Za-z0-9\-_]{16,})' // PostHog project/personal keys
  r'|(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})' // GitHub
  r'|(AKIA[0-9A-Z]{16})' // AWS access key id
  r'|(1//[A-Za-z0-9\-_]{16,})' // Google refresh token
  r'|(Bearer\s+[A-Za-z0-9._~+\-/=]{12,})' // Authorization value in text
  r'|((?:[?&]|\b)sig=[^&\s]+)' // Azure SAS signature in a URL
  r'|(-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*)'
  r'|(eyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,})', // JWT
  caseSensitive: false,
);

bool isDeniedPropertyName(String name) {
  final lower = name.toLowerCase();
  return kDeniedNameFragments.any(lower.contains);
}

String redactSecrets(String value) =>
    value.replaceAll(kSecretValuePattern, kRedacted);

/// Bounds work before applying the credential regex, then bounds the emitted
/// value again. The look-ahead catches a token that starts close to the output
/// boundary without running regexes over a multi-megabyte untrusted string.
String scrubText(String value, {int maxLength = kMaxStringLength}) {
  const lookAhead = 1024;
  final scanLength = maxLength + lookAhead;
  final scanInput = value.length <= scanLength
      ? value
      : value.substring(0, scanLength);
  final redacted = redactSecrets(scanInput);
  if (value.length <= maxLength && redacted.length <= maxLength) {
    return redacted;
  }
  final prefix = redacted.length <= maxLength
      ? redacted
      : redacted.substring(0, maxLength);
  return '$prefix…[truncated ${value.length} chars]';
}

String truncate(String value, {int maxLength = kMaxStringLength}) =>
    value.length <= maxLength
    ? value
    : '${value.substring(0, maxLength)}…[truncated ${value.length} chars]';

/// Applies every rule above to a property map, returning a map that is safe to
/// hand to PostHog.
Map<String, Object?> scrubProperties(Map<String, Object?> properties) {
  final clean = <String, Object?>{};
  for (final entry in properties.entries.take(kMaxMapEntries)) {
    final key = entry.key;
    final value = entry.value;
    if (value == null) continue;
    if (isDeniedPropertyName(key)) continue;
    final scrubbed = scrubValue(value);
    if (scrubbed != null) clean[key] = scrubbed;
  }
  return clean;
}

Object? scrubValue(Object? value, {int depth = 0}) {
  if (value == null) return null;
  if (value is String) return scrubText(value);
  if (value is num || value is bool) return value;
  if (depth >= kMaxNestingDepth) return '[nested value omitted]';
  if (value is Iterable) {
    return value
        .take(kMaxListLength)
        .map((item) => scrubValue(item, depth: depth + 1))
        .where((e) => e != null)
        .toList();
  }
  if (value is Map) {
    final nested = <String, Object?>{};
    for (final entry in value.entries.take(kMaxMapEntries)) {
      final k = entry.key;
      final v = entry.value;
      final name = k.toString();
      if (isDeniedPropertyName(name)) continue;
      final scrubbed = scrubValue(v, depth: depth + 1);
      if (scrubbed != null) nested[name] = scrubbed;
    }
    return nested;
  }
  return scrubText(value.toString());
}
