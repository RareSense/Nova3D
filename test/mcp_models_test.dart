import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_browser_context.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';

void main() {
  test('parses MCP status and detects purchase requirement', () {
    final status = McpStatus.fromJson({
      'authenticated': true,
      'identity': {
        'user_id': 'user_123',
        'email': 'user@example.com',
        'tenant_id': 'ten_123',
      },
      'mcp_session': {
        'established': false,
        'expires_at': '2026-09-10T14:32:00Z',
      },
      'credits': {'balance': 0, 'reserved': 0, 'available': 0, 'funded': false},
      'generation_ready': false,
      'next_action': 'purchase_credits',
      'next_action_url': '/subscription',
    });

    expect(status.authenticated, isTrue);
    expect(status.identity?.email, 'user@example.com');
    expect(status.mcpSession?.established, isFalse);
    expect(status.credits?.available, 0);
    expect(status.needsPurchase, isTrue);
    expect(status.nextActionUrl, '/subscription');
  });

  test('treats funded ready status as not needing purchase', () {
    final status = McpStatus.fromJson({
      'authenticated': true,
      'identity': {'user_id': 'user_123', 'email': 'user@example.com'},
      'mcp_session': {'established': true},
      'credits': {
        'balance': 400,
        'reserved': 50,
        'available': 350,
        'funded': true,
      },
      'generation_ready': true,
      'next_action': null,
      'next_action_url': null,
    });

    expect(status.generationReady, isTrue);
    expect(status.needsPurchase, isFalse);
  });

  test('parses MCP browser context and builds loopback URL', () {
    final context = McpBrowserContext.fromUri(
      Uri.parse(
        'https://nova3d.xyz/mcp/connect?state=nonce_123&port=5556&client_name=Cursor',
      ),
    );

    expect(context, isNotNull);
    expect(context!.state, 'nonce_123');
    expect(context.port, 5556);
    expect(context.clientName, 'Cursor');
    expect(
      context.loopbackUrlForCode('code_abc'),
      'http://127.0.0.1:5556/?code=code_abc&state=nonce_123',
    );
  });
}
