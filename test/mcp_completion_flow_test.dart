import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';
import 'package:nova3d_frontend/features/mcp/presentation/mcp_completion_flow.dart';

void main() {
  group('McpCompletionFlow.bootstrapAction', () {
    test('routes unauthenticated users back to connect', () {
      final status = _status(authenticated: false, needsPurchase: false);

      expect(
        McpCompletionFlow.bootstrapAction(
          status: status,
          hasValidContext: true,
        ),
        McpBootstrapAction.goToConnect,
      );
    });

    test('prepares handoff before credits when MCP context is present', () {
      final status = _status(authenticated: true, needsPurchase: true);

      expect(
        McpCompletionFlow.bootstrapAction(
          status: status,
          hasValidContext: true,
        ),
        McpBootstrapAction.prepareHandoff,
      );
    });

    test(
      'routes to credits when purchase is needed and no MCP context exists',
      () {
        final status = _status(authenticated: true, needsPurchase: true);

        expect(
          McpCompletionFlow.bootstrapAction(
            status: status,
            hasValidContext: false,
          ),
          McpBootstrapAction.goToNoCredits,
        );
      },
    );

    test('stays idle when setup is ready but context is unavailable', () {
      final status = _status(authenticated: true, needsPurchase: false);

      expect(
        McpCompletionFlow.bootstrapAction(
          status: status,
          hasValidContext: false,
        ),
        McpBootstrapAction.idle,
      );
    });
  });

  group('McpCompletionFlow.pollAction', () {
    test('keeps polling while zero-credit handoff is still pending', () {
      final status = _status(
        authenticated: true,
        needsPurchase: true,
        sessionEstablished: false,
      );

      expect(
        McpCompletionFlow.pollAction(
          status: status,
          routeToCreditsAfterHandoff: true,
        ),
        McpPollAction.continuePolling,
      );
    });

    test('routes to credits after zero-credit handoff succeeds', () {
      final status = _status(
        authenticated: true,
        needsPurchase: true,
        sessionEstablished: true,
      );

      expect(
        McpCompletionFlow.pollAction(
          status: status,
          routeToCreditsAfterHandoff: true,
        ),
        McpPollAction.goToNoCredits,
      );
    });

    test('stops polling after funded handoff succeeds', () {
      final status = _status(
        authenticated: true,
        needsPurchase: false,
        sessionEstablished: true,
      );

      expect(
        McpCompletionFlow.pollAction(
          status: status,
          routeToCreditsAfterHandoff: false,
        ),
        McpPollAction.stopPolling,
      );
    });

    test('routes to credits immediately when no handoff is pending', () {
      final status = _status(
        authenticated: true,
        needsPurchase: true,
        sessionEstablished: false,
      );

      expect(
        McpCompletionFlow.pollAction(
          status: status,
          routeToCreditsAfterHandoff: false,
        ),
        McpPollAction.goToNoCredits,
      );
    });

    test('routes expired sessions back to connect', () {
      final status = _status(
        authenticated: true,
        needsPurchase: false,
        nextAction: 'session_expired',
      );

      expect(
        McpCompletionFlow.pollAction(
          status: status,
          routeToCreditsAfterHandoff: true,
        ),
        McpPollAction.goToConnect,
      );
    });
  });
}

McpStatus _status({
  required bool authenticated,
  required bool needsPurchase,
  bool sessionEstablished = false,
  String? nextAction,
}) {
  return McpStatus(
    authenticated: authenticated,
    identity: null,
    mcpSession: McpSessionInfo(established: sessionEstablished),
    credits: McpCredits(
      balance: needsPurchase ? 0 : 100,
      reserved: 0,
      available: needsPurchase ? 0 : 100,
      funded: !needsPurchase,
    ),
    generationReady: sessionEstablished && !needsPurchase,
    nextAction: nextAction ?? (needsPurchase ? 'purchase_credits' : null),
    nextActionUrl: null,
  );
}
