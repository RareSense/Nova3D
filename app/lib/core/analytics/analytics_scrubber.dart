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

const String kRedacted = '[redacted]';

/// Property names containing any of these are dropped outright.
const List<String> kDeniedNameFragments = <String>[
  'api_key',
  'apikey',
  'access_token',
  'auth_token',
  'authorization',
  'bearer',
  'credential',
  'password',
  'secret',
  'session_token',
];

/// Shapes that identify provider credentials in free text.
///
/// This exists because Nova3D captures full prompt text: a user pasting a key
/// into a prompt box is a realistic accident, and the name-based denylist above
/// cannot catch it. Matching text is replaced rather than dropped so the event
/// still records that something was present.
final RegExp kSecretValuePattern = RegExp(
  r'(sk-ant-[A-Za-z0-9\-_]{8,})' // Anthropic
  r'|(sk-[A-Za-z0-9]{16,})' // OpenAI / OpenRouter
  r'|(AIza[A-Za-z0-9\-_]{16,})' // Google / Gemini
  r'|(n3d_[A-Za-z0-9\-_]{8,})' // Nova3D MCP key
  r'|(phc_[A-Za-z0-9]{16,})' // PostHog project key
  r'|(eyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,})', // JWT
);

bool isDeniedPropertyName(String name) {
  final lower = name.toLowerCase();
  return kDeniedNameFragments.any(lower.contains);
}

String redactSecrets(String value) =>
    value.replaceAll(kSecretValuePattern, kRedacted);

String truncate(String value, {int maxLength = kMaxStringLength}) =>
    value.length <= maxLength
    ? value
    : '${value.substring(0, maxLength)}…[truncated ${value.length} chars]';

/// Applies every rule above to a property map, returning a map that is safe to
/// hand to PostHog.
Map<String, Object?> scrubProperties(Map<String, Object?> properties) {
  final clean = <String, Object?>{};
  properties.forEach((key, value) {
    if (value == null) return;
    if (isDeniedPropertyName(key)) return;
    final scrubbed = scrubValue(value);
    if (scrubbed != null) clean[key] = scrubbed;
  });
  return clean;
}

Object? scrubValue(Object? value) {
  if (value == null) return null;
  if (value is String) return truncate(redactSecrets(value));
  if (value is num || value is bool) return value;
  if (value is Iterable) {
    return value
        .take(kMaxListLength)
        .map(scrubValue)
        .where((e) => e != null)
        .toList();
  }
  if (value is Map) {
    final nested = <String, Object?>{};
    value.forEach((k, v) {
      final name = k.toString();
      if (isDeniedPropertyName(name)) return;
      final scrubbed = scrubValue(v);
      if (scrubbed != null) nested[name] = scrubbed;
    });
    return nested;
  }
  return truncate(redactSecrets(value.toString()));
}
