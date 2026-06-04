import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/account_api_keys/data/account_api_key_service.dart';
import 'package:nova3d_frontend/features/account_api_keys/models/account_api_key_models.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';

final accountApiKeyServiceProvider = Provider<AccountApiKeyService>((ref) {
  return AccountApiKeyService(ref.watch(authServiceProvider));
});

final accountApiKeysProvider =
    NotifierProvider<AccountApiKeysNotifier, AccountApiKeysState>(
      AccountApiKeysNotifier.new,
    );

class AccountApiKeysState {
  const AccountApiKeysState({
    this.keys = const [],
    this.me,
    this.loading = false,
    this.creating = false,
    this.revokingIds = const {},
    this.error,
    this.notice,
  });

  final List<AccountApiKey> keys;
  final AccountMe? me;
  final bool loading;
  final bool creating;
  final Set<String> revokingIds;
  final String? error;
  final String? notice;

  bool get isBusy => loading || creating || revokingIds.isNotEmpty;

  AccountApiKeysState copyWith({
    List<AccountApiKey>? keys,
    AccountMe? me,
    bool? loading,
    bool? creating,
    Set<String>? revokingIds,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) => AccountApiKeysState(
    keys: keys ?? this.keys,
    me: me ?? this.me,
    loading: loading ?? this.loading,
    creating: creating ?? this.creating,
    revokingIds: revokingIds ?? this.revokingIds,
    error: clearError ? null : error ?? this.error,
    notice: clearNotice ? null : notice ?? this.notice,
  );
}

class AccountApiKeysNotifier extends Notifier<AccountApiKeysState> {
  @override
  AccountApiKeysState build() {
    // Only load when authenticated; reset to empty state on logout so that
    // a subsequent user never sees another user's account keys.
    final user = ref.watch(authProvider).valueOrNull;
    if (user != null) Future.microtask(load);
    return const AccountApiKeysState();
  }

  AccountApiKeyService get _service => ref.read(accountApiKeyServiceProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final results = await Future.wait<Object>([
        _service.getMe(),
        _service.listKeys(),
      ]);
      state = state.copyWith(
        me: results[0] as AccountMe,
        keys: results[1] as List<AccountApiKey>,
        loading: false,
      );
    } on AccountApiKeyException catch (e) {
      await _handleException(e);
      state = state.copyWith(loading: false);
    }
  }

  Future<CreatedAccountApiKey?> createKey(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Name is required.', clearNotice: true);
      return null;
    }
    if (trimmed.length > 64) {
      state = state.copyWith(
        error: 'Name must be 64 characters or fewer.',
        clearNotice: true,
      );
      return null;
    }

    state = state.copyWith(creating: true, clearError: true, clearNotice: true);
    try {
      final created = await _service.createKey(trimmed);
      state = state.copyWith(
        creating: false,
        keys: [created, ...state.keys.where((key) => key.id != created.id)],
        notice: 'API key created.',
      );
      return created;
    } on AccountApiKeyException catch (e) {
      await _handleException(e);
      state = state.copyWith(creating: false);
      return null;
    }
  }

  Future<bool> revokeKey(AccountApiKey key) async {
    state = state.copyWith(
      revokingIds: {...state.revokingIds, key.id},
      clearError: true,
      clearNotice: true,
    );
    try {
      await _service.revokeKey(key.id);
      state = state.copyWith(
        keys: state.keys.where((item) => item.id != key.id).toList(),
        revokingIds: {...state.revokingIds}..remove(key.id),
        notice: 'API key revoked.',
      );
      return true;
    } on AccountApiKeyException catch (e) {
      await _handleException(e);
      state = state.copyWith(
        revokingIds: {...state.revokingIds}..remove(key.id),
      );
      return false;
    }
  }

  void clearMessages() {
    state = state.copyWith(clearError: true, clearNotice: true);
  }

  Future<void> _handleException(AccountApiKeyException e) async {
    state = state.copyWith(error: e.message, clearNotice: true);
    if (e.isAuthError) {
      await ref.read(authProvider.notifier).signOut();
    }
  }
}
