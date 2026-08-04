/// One-time handoff for sensitive values removed from the startup URL before
/// analytics initializes.
///
/// Values live only in this Dart process until their owning feature consumes
/// them. MCP context is subsequently copied into its existing session-scoped
/// store because it must survive the external OAuth redirect.
abstract final class StartupUrlBootstrap {
  static const Set<String> _checkoutKeys = <String>{
    'session_id',
    'checkout_session_id',
  };

  static const Set<String> _mcpKeys = <String>{
    'state',
    'port',
    'callback_port',
    'client_name',
    'editor_name',
    'editor',
    'client',
  };

  static Map<String, String> _capturedQuery = <String, String>{};
  static String? _oauthFragment;

  /// Captures sensitive startup values and returns the safe relative URL that
  /// should replace the address bar, or null when no sanitization is required.
  static Uri? capture(Uri uri) {
    _capturedQuery = <String, String>{};
    _oauthFragment = null;

    final sensitiveQueryKeys = <String>{
      if (_isCheckoutReturnPath(uri.path)) ..._checkoutKeys,
      if (_isMcpPath(uri.path)) ..._mcpKeys,
    };
    var queryChanged = false;
    final retainedQuery = <String, Object>{};
    for (final entry in uri.queryParametersAll.entries) {
      if (sensitiveQueryKeys.contains(entry.key)) {
        queryChanged = true;
        if (entry.value.isNotEmpty) {
          _capturedQuery[entry.key] = entry.value.first;
        }
        continue;
      }
      if (entry.value.isNotEmpty) {
        retainedQuery[entry.key] = entry.value.length == 1
            ? entry.value.first
            : entry.value;
      }
    }

    final fragment = uri.fragment;
    final capturesOAuthFragment =
        fragment.isNotEmpty &&
        (_matchesRoute(uri.path, '/oauth-callback') ||
            fragment.contains('access_token='));
    if (capturesOAuthFragment) _oauthFragment = fragment;

    if (!queryChanged && !capturesOAuthFragment) return null;
    return Uri(
      path: uri.path.isEmpty ? '/' : uri.path,
      queryParameters: retainedQuery.isEmpty ? null : retainedQuery,
      fragment: capturesOAuthFragment || fragment.isEmpty ? null : fragment,
    );
  }

  /// Returns a checkout identifier once, preferring Stripe's primary key name.
  static String? takeCheckoutSessionId() {
    final sessionId = _capturedQuery.remove('session_id');
    final checkoutSessionId = _capturedQuery.remove('checkout_session_id');
    return _nonEmpty(sessionId) ?? _nonEmpty(checkoutSessionId);
  }

  /// Returns and clears the MCP launch parameters captured at startup.
  static Map<String, String> takeMcpQueryParameters() {
    final result = <String, String>{};
    for (final key in _mcpKeys) {
      final value = _capturedQuery.remove(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  /// Returns the OAuth callback fragment once.
  static String? takeOAuthFragment() {
    final value = _oauthFragment;
    _oauthFragment = null;
    return value;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isCheckoutReturnPath(String path) =>
      _matchesRoute(path, '/success') ||
      _matchesRoute(path, '/subscription') ||
      _matchesRoute(path, '/mcp/purchase-success');

  static bool _isMcpPath(String path) =>
      _matchesRoute(path, '/mcp') || path.contains('/mcp/');

  /// Flutter may be hosted below a base path (for example `/nova/`). Match
  /// route suffixes on segment boundaries while preserving that base path.
  static bool _matchesRoute(String path, String route) =>
      path == route || path.endsWith(route);
}
