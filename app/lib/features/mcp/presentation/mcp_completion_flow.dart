import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';

enum McpBootstrapAction { goToConnect, goToNoCredits, prepareHandoff, idle }

enum McpPollAction { goToConnect, goToNoCredits, stopPolling, continuePolling }

class McpCompletionFlow {
  const McpCompletionFlow._();

  static McpBootstrapAction bootstrapAction({
    required McpStatus status,
    required bool hasValidContext,
  }) {
    if (!status.authenticated ||
        status.nextAction == 'sign_in' ||
        status.nextAction == 'session_expired') {
      return McpBootstrapAction.goToConnect;
    }
    if (hasValidContext) return McpBootstrapAction.prepareHandoff;
    if (status.needsPurchase) return McpBootstrapAction.goToNoCredits;
    return McpBootstrapAction.idle;
  }

  static McpPollAction pollAction({
    required McpStatus status,
    required bool routeToCreditsAfterHandoff,
  }) {
    if (!status.authenticated ||
        status.nextAction == 'sign_in' ||
        status.nextAction == 'session_expired') {
      return McpPollAction.goToConnect;
    }

    final handoffEstablished =
        status.mcpSession?.established == true || status.generationReady;
    if (handoffEstablished) {
      if (routeToCreditsAfterHandoff && status.needsPurchase) {
        return McpPollAction.goToNoCredits;
      }
      return McpPollAction.stopPolling;
    }

    if (!routeToCreditsAfterHandoff && status.needsPurchase) {
      return McpPollAction.goToNoCredits;
    }

    return McpPollAction.continuePolling;
  }
}
