class BillingTier {
  const BillingTier({
    required this.tierId,
    required this.name,
    required this.type,
    required this.credits,
  });

  final String tierId;
  final String name;
  final String type;
  final int credits;

  factory BillingTier.fromJson(Map<String, dynamic> json) {
    final tierId = (json['tier_id'] ?? '').toString();
    final name = (json['name'] ?? 'Nova3D Credits').toString();
    final type = (json['type'] ?? 'one_time').toString();
    final creditsValue = json['credits'];
    final credits = creditsValue is num
        ? creditsValue.toInt()
        : int.tryParse((creditsValue ?? '').toString()) ?? 0;

    return BillingTier(
      tierId: tierId,
      name: name,
      type: type,
      credits: credits,
    );
  }

  String get title => credits > 0 ? '$credits credits' : name;

  String get purchaseModeLabel =>
      type == 'recurring' ? 'Recurring credit pack' : 'One-time credit pack';

  int? get priceUsd => _priceUsdByCredits[credits];

  String get displayPrice => priceUsd == null ? 'Checkout' : '\$$priceUsd';

  bool get isPopular => credits == 500;

  static const Map<int, int> _priceUsdByCredits = {100: 9, 500: 39, 1500: 99};

  static const List<BillingTier> nova3dCreditPacks = [
    BillingTier(
      tierId: 'tier_ae5dbd17',
      name: 'Nova3D Credits',
      type: 'one_time',
      credits: 100,
    ),
    BillingTier(
      tierId: 'tier_fa4afd8c',
      name: 'Nova3D Credits',
      type: 'one_time',
      credits: 500,
    ),
    BillingTier(
      tierId: 'tier_89789a49',
      name: 'Nova3D Credits',
      type: 'one_time',
      credits: 1500,
    ),
  ];
}

class BillingWallet {
  const BillingWallet({
    required this.internalUserId,
    required this.externalUserId,
    required this.tenantId,
    required this.balance,
    required this.reserved,
    required this.available,
  });

  final String internalUserId;
  final String externalUserId;
  final String tenantId;
  final int balance;
  final int reserved;
  final int available;

  factory BillingWallet.fromJson(Map<String, dynamic> json) => BillingWallet(
    internalUserId: (json['internal_user_id'] ?? '').toString(),
    externalUserId: (json['external_user_id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    balance: _intFromJson(json['balance']),
    reserved: _intFromJson(json['reserved']),
    available: _intFromJson(json['available']),
  );
}

class CheckoutVerification {
  const CheckoutVerification({
    required this.status,
    required this.creditsAdded,
  });

  final String status;
  final int creditsAdded;

  bool get fulfilled => status == 'fulfilled';

  factory CheckoutVerification.fromJson(Map<String, dynamic> json) =>
      CheckoutVerification(
        status: (json['status'] ?? '').toString(),
        creditsAdded: _intFromJson(json['credits_added']),
      );
}

int _intFromJson(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}
