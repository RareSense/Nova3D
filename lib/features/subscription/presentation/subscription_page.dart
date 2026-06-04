import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/api_keys/presentation/api_keys_section.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: [
            const NovaCube(size: 72),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: kLilacBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kInk, width: 1.5),
              ),
              child: Text('✦ coming soon', style: kSilkscreen(10, color: kInk)),
            ),
            const SizedBox(height: 16),
            Text('subscriptions', style: kVt323(54)),
            const SizedBox(height: 8),
            Text(
              'For now, Nova3D uses provider keys you already own.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            const _PlanGrid(),
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: kChunkyCard(),
              child: const ApiKeysSection(),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Plan {
  const _Plan({
    required this.name,
    required this.label,
    required this.description,
    required this.features,
    this.highlighted = false,
    this.accentColor,
    this.buttonBg,
  });

  final String name;
  final String label;
  final String description;
  final List<String> features;
  final bool highlighted;
  final Color? accentColor;
  final Color? buttonBg;
}

const _plans = [
  _Plan(
    name: 'Free',
    label: 'Included for now',
    description: 'Use Nova3D with your own provider key while billing is offline.',
    features: [
      'Bring your own provider key',
      'Text and image inputs',
      'GLB model preview',
      'Local browser key storage',
    ],
  ),
  _Plan(
    name: 'Standard',
    label: 'Coming soon',
    description: 'Higher generation limits and richer export options.',
    highlighted: true,
    accentColor: kLilac,
    buttonBg: kPinkBg,
    features: [
      'Higher monthly limits',
      'Priority generation',
      'GLB + OBJ + STL export',
      'Parametric editing tools',
      'Email support',
    ],
  ),
  _Plan(
    name: 'Pro',
    label: 'Coming soon',
    description: 'A workspace for professional and studio workflows.',
    accentColor: kMint,
    buttonBg: kMintBg,
    features: [
      'Team collaboration',
      'Expanded export formats',
      'API access',
      'Advanced model controls',
      'Dedicated support',
    ],
  ),
];

// ── Grid ──────────────────────────────────────────────────────────────────────

class _PlanGrid extends StatelessWidget {
  const _PlanGrid();

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    if (isMobile) {
      return Column(
        children: _plans
            .map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PlanCard(plan: plan),
              ),
            )
            .toList(),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _plans
            .map(
              (plan) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _PlanCard(plan: plan),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.plan});
  final _Plan plan;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final accent = plan.accentColor ?? kInk;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: _pressed
            ? Matrix4.translationValues(2, 2, 0)
            : Matrix4.identity(),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _pressed ? Colors.transparent : kInk,
              offset: _pressed ? Offset.zero : const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top group (all content) ──────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: const TextStyle(
                          color: kInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (plan.highlighted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Popular',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  plan.label,
                  style: kVt323(30, color: accent == kInk ? kInk : accent),
                ),
                const SizedBox(height: 8),
                Text(
                  plan.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Divider(color: kInk.withValues(alpha: 0.15), thickness: 1),
                const SizedBox(height: 16),
                ...plan.features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: plan.accentColor ?? kSuccessGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: kInkSoft,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // ── Bottom group (button always at bottom) ───────────
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                child: _CardButton(plan: plan, accent: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatefulWidget {
  const _CardButton({required this.plan, required this.accent});
  final _Plan plan;
  final Color accent;

  @override
  State<_CardButton> createState() => _CardButtonState();
}

class _CardButtonState extends State<_CardButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isFree = widget.plan.name == 'Free';

    return GestureDetector(
      onTapDown: isFree ? null : (_) => setState(() => _pressed = true),
      onTapUp: isFree ? null : (_) => setState(() => _pressed = false),
      onTapCancel: isFree ? null : () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed
            ? Matrix4.translationValues(2, 2, 0)
            : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: isFree ? kLineSoft : (widget.plan.buttonBg ?? kLilacBg),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isFree ? kInkMuted : kInk, width: 1.5),
          boxShadow: isFree || _pressed
              ? []
              : [
                  const BoxShadow(
                    color: kInk,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Center(
          child: Text(
            isFree ? 'Active' : 'Coming soon',
            style: kSilkscreen(9, color: isFree ? kInkMuted : kInk),
          ),
        ),
      ),
    );
  }
}
