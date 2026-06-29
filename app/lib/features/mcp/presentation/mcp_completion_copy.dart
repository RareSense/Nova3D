class McpCompletionCopy {
  const McpCompletionCopy._();

  static String continueLabel(String? clientName) =>
      'Continue in ${targetName(clientName)}';

  static String completionTitle({required bool ready}) =>
      ready ? 'Nova3D is ready' : 'Complete your Nova3D connection';

  static String completionSubtitle(String? clientName) =>
      'Nova3D sign-in is complete. Finish the secure local handoff to continue in ${targetName(clientName)}.';

  static String completionInstruction(String? clientName) =>
      'Next, Nova3D may briefly open a local confirmation page on this device. '
      'After it confirms connection, return to ${targetName(clientName)}.';

  static String targetName(String? clientName) {
    final normalized = normalizedClientName(clientName);
    return normalized ?? 'your MCP client';
  }

  static String handoffPendingMessage(String? clientName) =>
      'Finishing the local connection with ${targetName(clientName)} first. '
      'Nova3D will open credits once the handoff completes.';

  static String checkingStatusMessage(String? clientName) =>
      'Checking whether ${targetName(clientName)} received the local callback...';

  static String handoffExpectationMessage(String? clientName) =>
      'Nova3D may briefly open a local confirmation page on this device to '
      'finish connecting to ${targetName(clientName)}.';

  static String handoffReturnMessage(String? clientName) =>
      'After the local page confirms connection, return to ${targetName(clientName)}.';

  static String connectSubtitle(String? clientName) =>
      'Sign in to link Nova3D with ${targetName(clientName)}. Nova3D will use '
      'your normal account wallet, and paid generation will only start once credits are ready.';

  static String missingContextMessage(String? clientName) =>
      'This browser page is missing the handoff details for ${targetName(clientName)}. '
      'Restart setup from ${targetName(clientName)}.';

  static bool showBlockingSpinner({
    required bool loadingStatus,
    required bool preparingLoopback,
    required bool hasHandoffUrl,
  }) => preparingLoopback || (loadingStatus && !hasHandoffUrl);

  static String? normalizedClientName(String? clientName) {
    final trimmed = (clientName ?? '').trim();
    if (trimmed.isEmpty) return null;

    final collapsed = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return switch (collapsed) {
      'claude code' => 'Claude Code',
      'codex' => 'Codex',
      'cursor' => 'Cursor',
      'vscode' || 'vs code' || 'visual studio code' => 'VS Code',
      'visual studio' => 'Visual Studio',
      _ => trimmed,
    };
  }
}
