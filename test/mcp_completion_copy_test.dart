import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_completion_copy.dart';

void main() {
  group('McpCompletionCopy.targetName', () {
    test('uses neutral fallback when client name is missing', () {
      expect(McpCompletionCopy.targetName(null), 'your MCP client');
      expect(McpCompletionCopy.targetName('  '), 'your MCP client');
    });

    test('normalizes common client names for display', () {
      expect(McpCompletionCopy.targetName('claude code'), 'Claude Code');
      expect(McpCompletionCopy.targetName('codex'), 'Codex');
      expect(McpCompletionCopy.targetName('cursor'), 'Cursor');
      expect(McpCompletionCopy.targetName('vscode'), 'VS Code');
      expect(McpCompletionCopy.targetName('visual studio code'), 'VS Code');
      expect(McpCompletionCopy.targetName('visual studio'), 'Visual Studio');
    });

    test('preserves unknown client labels', () {
      expect(McpCompletionCopy.targetName('Warp'), 'Warp');
    });
  });

  group('McpCompletionCopy.continueLabel', () {
    test('uses neutral fallback in CTA copy', () {
      expect(
        McpCompletionCopy.continueLabel(null),
        'Continue in your MCP client',
      );
    });

    test('uses detected client in CTA copy', () {
      expect(McpCompletionCopy.continueLabel('cursor'), 'Continue in Cursor');
    });
  });

  group('McpCompletionCopy.showBlockingSpinner', () {
    test('blocks only during setup before handoff URL is ready', () {
      expect(
        McpCompletionCopy.showBlockingSpinner(
          loadingStatus: true,
          preparingLoopback: false,
          hasHandoffUrl: false,
        ),
        isTrue,
      );
    });

    test('keeps CTA visible during status polling after handoff is ready', () {
      expect(
        McpCompletionCopy.showBlockingSpinner(
          loadingStatus: true,
          preparingLoopback: false,
          hasHandoffUrl: true,
        ),
        isFalse,
      );
    });

    test('always blocks while preparing loopback', () {
      expect(
        McpCompletionCopy.showBlockingSpinner(
          loadingStatus: false,
          preparingLoopback: true,
          hasHandoffUrl: true,
        ),
        isTrue,
      );
    });
  });
}
