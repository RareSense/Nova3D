import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/mcp/data/mcp_service.dart';
import 'package:nova3d_frontend/features/mcp/models/mcp_models.dart';

final mcpServiceProvider = Provider<McpService>((ref) {
  return McpService(ref.watch(authServiceProvider));
});

final mcpProvider = NotifierProvider<McpNotifier, McpState>(McpNotifier.new);

class McpState {
  const McpState({
    this.status,
    this.loadingStatus = false,
    this.creatingSession = false,
    this.sessionCode,
    this.error,
  });

  final McpStatus? status;
  final bool loadingStatus;
  final bool creatingSession;
  final String? sessionCode;
  final String? error;

  McpState copyWith({
    McpStatus? status,
    bool keepStatus = true,
    bool? loadingStatus,
    bool? creatingSession,
    String? sessionCode,
    bool clearSessionCode = false,
    String? error,
    bool clearError = false,
  }) => McpState(
    status: keepStatus ? (status ?? this.status) : status,
    loadingStatus: loadingStatus ?? this.loadingStatus,
    creatingSession: creatingSession ?? this.creatingSession,
    sessionCode: clearSessionCode ? null : sessionCode ?? this.sessionCode,
    error: clearError ? null : error ?? this.error,
  );
}

class McpNotifier extends Notifier<McpState> {
  @override
  McpState build() => const McpState();

  McpService get _service => ref.read(mcpServiceProvider);

  Future<McpStatus?> refreshStatus() async {
    if (state.loadingStatus) return state.status;
    state = state.copyWith(loadingStatus: true, clearError: true);
    try {
      final status = await _service.getStatus();
      state = state.copyWith(status: status, loadingStatus: false);
      return status;
    } on McpException catch (e) {
      await _handleException(e);
      state = state.copyWith(loadingStatus: false);
      return null;
    }
  }

  Future<String?> createSessionCode() async {
    if (state.creatingSession) return state.sessionCode;
    state = state.copyWith(
      creatingSession: true,
      clearError: true,
      clearSessionCode: true,
    );
    try {
      final code = await _service.createSessionCode();
      state = state.copyWith(creatingSession: false, sessionCode: code);
      return code;
    } on McpException catch (e) {
      await _handleException(e);
      state = state.copyWith(creatingSession: false, clearSessionCode: true);
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearSessionCode() {
    state = state.copyWith(clearSessionCode: true);
  }

  Future<void> _handleException(McpException e) async {
    state = state.copyWith(error: e.message);
    if (e.isAuthError) {
      await ref.read(authProvider.notifier).signOut();
    }
  }
}
