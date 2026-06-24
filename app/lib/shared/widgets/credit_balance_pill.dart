import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';

class CreditBalancePill extends ConsumerWidget {
  const CreditBalancePill({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(billingProvider);
    final available = billing.wallet?.available;
    final loading =
        (billing.refreshingWallet || billing.verifyingCheckout) &&
        available == null;
    final label = available == null ? '--' : '$available';

    return Tooltip(
      message: 'Credits',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => context.go('/subscription'),
          child: Container(
            height: compact ? 34 : 38,
            constraints: BoxConstraints(minWidth: compact ? 74 : 104),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kInk, width: 1.5),
              boxShadow: const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.toll_outlined, size: 17, color: kInk),
                const SizedBox(width: 7),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kInk,
                    ),
                  )
                else
                  Text(label, style: kSilkscreen(12, color: kInk)),
                if (!compact) ...[
                  const SizedBox(width: 7),
                  Text('credits', style: kSilkscreen(9, color: kInkMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
