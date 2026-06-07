import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/subscription/data/billing_service.dart';
import 'package:nova3d_frontend/features/subscription/models/billing_models.dart';

final billingServiceProvider = Provider<BillingService>((ref) {
  return BillingService(ref.watch(authServiceProvider));
});

final billingProvider = NotifierProvider<BillingNotifier, BillingState>(
  BillingNotifier.new,
);

class BillingState {
  const BillingState({
    this.tiers = BillingTier.nova3dCreditPacks,
    this.wallet,
    this.loading = false,
    this.refreshingWallet = false,
    this.tiersLoaded = false,
    this.walletLoaded = false,
    this.verifyingCheckout = false,
    this.checkoutTierId,
    this.error,
    this.notice,
  });

  final List<BillingTier> tiers;
  final BillingWallet? wallet;
  final bool loading;
  final bool refreshingWallet;
  final bool tiersLoaded;
  final bool walletLoaded;
  final bool verifyingCheckout;
  final String? checkoutTierId;
  final String? error;
  final String? notice;

  BillingState copyWith({
    List<BillingTier>? tiers,
    BillingWallet? wallet,
    bool? loading,
    bool? refreshingWallet,
    bool? tiersLoaded,
    bool? walletLoaded,
    bool? verifyingCheckout,
    String? checkoutTierId,
    bool clearCheckoutTierId = false,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) => BillingState(
    tiers: tiers ?? this.tiers,
    wallet: wallet ?? this.wallet,
    loading: loading ?? this.loading,
    refreshingWallet: refreshingWallet ?? this.refreshingWallet,
    tiersLoaded: tiersLoaded ?? this.tiersLoaded,
    walletLoaded: walletLoaded ?? this.walletLoaded,
    verifyingCheckout: verifyingCheckout ?? this.verifyingCheckout,
    checkoutTierId: clearCheckoutTierId
        ? null
        : checkoutTierId ?? this.checkoutTierId,
    error: clearError ? null : error ?? this.error,
    notice: clearNotice ? null : notice ?? this.notice,
  );
}

class BillingNotifier extends Notifier<BillingState> {
  @override
  BillingState build() {
    final user = ref.watch(authProvider).valueOrNull;
    if (user != null) Future.microtask(refreshWallet);
    return const BillingState();
  }

  BillingService get _service => ref.read(billingServiceProvider);

  Future<void> load({bool force = false}) async {
    if (!force && state.tiersLoaded) return;
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final tiers = await _service.listTiers().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw BillingException(
          'Credit packages took too long to load. Please try again.',
        ),
      );
      state = state.copyWith(tiers: tiers, loading: false, tiersLoaded: true);
    } on BillingException catch (e) {
      await _handleException(e);
      state = state.copyWith(loading: false, tiersLoaded: true);
    }
  }

  Future<void> refreshWallet() async {
    if (state.refreshingWallet) return;
    state = state.copyWith(refreshingWallet: true, clearError: true);
    try {
      state = state.copyWith(
        wallet: await _service.getWallet(),
        walletLoaded: true,
        refreshingWallet: false,
      );
    } on BillingException catch (e) {
      await _handleException(e);
      state = state.copyWith(refreshingWallet: false);
    }
  }

  Future<void> verifyCheckout(String sessionId) async {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty || state.verifyingCheckout) return;

    state = state.copyWith(
      verifyingCheckout: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      final verification = await _service.verifyCheckout(trimmed);
      final wallet = await _service.getWallet();
      final notice = verification.fulfilled
          ? '${verification.creditsAdded} credits added to your account.'
          : 'Payment is still pending. Refresh shortly to update credits.';
      state = state.copyWith(
        wallet: wallet,
        walletLoaded: true,
        verifyingCheckout: false,
        notice: notice,
      );
    } on BillingException catch (e) {
      await _handleException(e);
      state = state.copyWith(verifyingCheckout: false);
    }
  }

  Future<String?> createCheckout(BillingTier tier) async {
    if (state.checkoutTierId != null) return null;
    state = state.copyWith(checkoutTierId: tier.tierId, clearError: true);
    try {
      final url = await _service.createCheckout(tier.tierId);
      state = state.copyWith(clearCheckoutTierId: true);
      return url;
    } on BillingException catch (e) {
      await _handleException(e);
      state = state.copyWith(clearCheckoutTierId: true);
      return null;
    }
  }

  void setError(String message) {
    state = state.copyWith(error: message, clearNotice: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearNotice() {
    state = state.copyWith(clearNotice: true);
  }

  Future<void> _handleException(BillingException e) async {
    state = state.copyWith(error: e.message, clearNotice: true);
    if (e.isAuthError) {
      await ref.read(authProvider.notifier).signOut();
    }
  }
}
