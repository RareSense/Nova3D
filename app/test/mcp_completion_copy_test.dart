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

  group('McpCompletionCopy.completion copy', () {
    test('uses neutral fallback in completion messaging', () {
      expect(
        McpCompletionCopy.completionTitle(ready: false),
        'Complete your Nova3D connection',
      );
      expect(
        McpCompletionCopy.completionSubtitle(null),
        'Nova3D sign-in is complete. Finish the secure local handoff to continue in your MCP client.',
      );
      expect(
        McpCompletionCopy.completionInstruction(null),
        'Next, Nova3D may briefly open a local confirmation page on this device. After it confirms connection, return to your MCP client.',
      );
    });

    test('uses detected client in completion messaging', () {
      expect(McpCompletionCopy.completionTitle(ready: true), 'Nova3D is ready');
      expect(
        McpCompletionCopy.completionSubtitle('codex'),
        'Nova3D sign-in is complete. Finish the secure local handoff to continue in Codex.',
      );
      expect(
        McpCompletionCopy.completionInstruction('claude code'),
        'Next, Nova3D may briefly open a local confirmation page on this device. After it confirms connection, return to Claude Code.',
      );
    });
  });

  group('McpCompletionCopy.handoff copy', () {
    test('uses neutral fallback in handoff messaging', () {
      expect(
        McpCompletionCopy.handoffExpectationMessage(null),
        'Nova3D may briefly open a local confirmation page on this device to finish connecting to your MCP client.',
      );
      expect(
        McpCompletionCopy.handoffReturnMessage(null),
        'After the local page confirms connection, return to your MCP client.',
      );
    });

    test('uses detected client in handoff messaging', () {
      expect(
        McpCompletionCopy.handoffExpectationMessage('codex'),
        'Nova3D may briefly open a local confirmation page on this device to finish connecting to Codex.',
      );
      expect(
        McpCompletionCopy.handoffReturnMessage('claude code'),
        'After the local page confirms connection, return to Claude Code.',
      );
    });

    test('uses client-aware missing-context message', () {
      expect(
        McpCompletionCopy.missingContextMessage('cursor'),
        'This browser page is missing the MCP handoff details for Cursor. Restart setup from the Nova3D MCP command in Cursor.',
      );
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
