class McpCompletionCopy {
  const McpCompletionCopy._();

  static String continueLabel(String? clientName) =>
      'Continue in ${targetName(clientName)}';

  static String targetName(String? clientName) {
    final normalized = normalizedClientName(clientName);
    return normalized ?? 'your MCP client';
  }

  static String handoffPendingMessage(String? clientName) =>
      'Finishing the local MCP connection with ${targetName(clientName)} first. '
      'Nova3D will open credits once the handoff completes.';

  static String checkingStatusMessage(String? clientName) =>
      'Checking whether ${targetName(clientName)} received the local callback...';

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
