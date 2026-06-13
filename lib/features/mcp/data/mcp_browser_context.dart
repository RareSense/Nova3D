import 'dart:convert';

import 'package:web/web.dart' as web;

const String _mcpContextStorageKey = '_nova3d_mcp_context';

class McpBrowserContext {
  const McpBrowserContext({
    required this.state,
    required this.port,
    this.clientName,
  });

  final String state;
  final int port;
  final String? clientName;

  bool get isValid => state.trim().isNotEmpty && port > 0;

  Uri get loopbackUri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: '/',
    queryParameters: {'code': '{code}', 'state': state},
  );

  String loopbackUrlForCode(String code) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: '/',
    queryParameters: {'code': code, 'state': state},
  ).toString();

  Map<String, dynamic> toJson() => {
    'state': state,
    'port': port,
    'client_name': clientName,
  };

  static McpBrowserContext? fromUri(Uri uri) {
    final state = (uri.queryParameters['state'] ?? '').trim();
    final port =
        int.tryParse(uri.queryParameters['port'] ?? '') ??
        int.tryParse(uri.queryParameters['callback_port'] ?? '');
    final clientName = _cleanClientName(
      uri.queryParameters['client_name'] ??
          uri.queryParameters['editor_name'] ??
          uri.queryParameters['editor'] ??
          uri.queryParameters['client'],
    );

    if (state.isEmpty || port == null || port <= 0) return null;
    return McpBrowserContext(state: state, port: port, clientName: clientName);
  }

  static McpBrowserContext? read() {
    final raw = web.window.sessionStorage.getItem(_mcpContextStorageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final state = (map['state'] ?? '').toString().trim();
      final port = map['port'] is num
          ? (map['port'] as num).toInt()
          : int.tryParse((map['port'] ?? '').toString());
      if (state.isEmpty || port == null || port <= 0) return null;
      return McpBrowserContext(
        state: state,
        port: port,
        clientName: _cleanClientName(map['client_name']?.toString()),
      );
    } catch (_) {
      return null;
    }
  }

  static McpBrowserContext? readOrCapture(Uri uri) {
    final fromUri = McpBrowserContext.fromUri(uri);
    if (fromUri != null) {
      persist(fromUri);
      return fromUri;
    }
    return read();
  }

  static void persist(McpBrowserContext context) {
    web.window.sessionStorage.setItem(
      _mcpContextStorageKey,
      json.encode(context.toJson()),
    );
  }

  static void clear() {
    web.window.sessionStorage.removeItem(_mcpContextStorageKey);
  }

  static String? _cleanClientName(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
