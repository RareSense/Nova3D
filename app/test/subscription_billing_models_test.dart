import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/subscription/models/billing_models.dart';

void main() {
  test('parses billing tiers and displays configured credit prices', () {
    final tiers = [
      {
        'tier_id': 'tier_100',
        'name': 'Nova3D Credits',
        'type': 'one_time',
        'credits': 100,
      },
      {
        'tier_id': 'tier_500',
        'name': 'Nova3D Credits',
        'type': 'one_time',
        'credits': 500,
      },
      {
        'tier_id': 'tier_1500',
        'name': 'Nova3D Credits',
        'type': 'one_time',
        'credits': 1500,
      },
    ].map(BillingTier.fromJson).toList();

    expect(tiers.map((tier) => tier.displayPrice), ['\$9', '\$39', '\$99']);
    expect(tiers[1].isPopular, isTrue);
    expect(tiers[0].purchaseModeLabel, 'One-time credit pack');
  });

  test('keeps known Nova3D packs available while dynamic tiers load', () {
    expect(BillingTier.nova3dCreditPacks.map((tier) => tier.credits), [
      100,
      500,
      1500,
    ]);
    expect(BillingTier.nova3dCreditPacks.map((tier) => tier.displayPrice), [
      '\$9',
      '\$39',
      '\$99',
    ]);
  });

  test('parses GraphFlow wallet balance', () {
    final wallet = BillingWallet.fromJson({
      'internal_user_id': 'user-1',
      'external_user_id': 'auth-sub-1',
      'tenant_id': 'ten_1',
      'balance': 100,
      'reserved': 15,
      'available': 85,
    });

    expect(wallet.balance, 100);
    expect(wallet.reserved, 15);
    expect(wallet.available, 85);
  });
}
