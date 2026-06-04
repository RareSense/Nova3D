import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/api_keys/presentation/api_keys_section.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    // No inner Scaffold — AppLayout provides it with the grid background
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading
              Row(
                children: [
                  Text('settings', style: kVt323(44, color: kInk)),
                  const SizedBox(width: 12),
                  Text('✦', style: TextStyle(color: kPink, fontSize: 20)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your account and bring-your-own provider keys.',
                style: GoogleFonts.inter(fontSize: 14, color: kInkSoft),
              ),
              const SizedBox(height: 24),

              // Account
              _SectionCard(
                title: 'Account',
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: kPink,
                          shape: BoxShape.circle,
                          border: Border.all(color: kInk, width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                              color: kInk,
                              offset: Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            user != null && user.email.isNotEmpty
                                ? user.email.substring(0, 1).toUpperCase()
                                : '?',
                            style: kSilkscreen(16, color: kInk),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.email ?? '—',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: kInk,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F5EC),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: const Color(0xFFA6D9B7),
                                ),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: kSilkscreen(
                                  9,
                                  color: const Color(0xFF1F7A3E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Subscription teaser
              _SectionCard(
                title: 'Subscription',
                bg: kButterBg,
                children: [
                  Row(
                    children: [
                      const NovaCube(size: 48),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Subscription',
                                  style: kSilkscreen(
                                    11,
                                    color: kInk,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kLilacBg,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: kLilac),
                                  ),
                                  child: Text(
                                    'COMING SOON',
                                    style: kSilkscreen(9, color: kInk),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You\'re on Free · BYOK — use your own provider keys.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: kInkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SmallChunkyButton(
                        label: 'View plans →',
                        onTap: () => context.go('/subscription'),
                        color: kSurface,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Provider keys
              const _SectionCard(
                title: 'BYOK Provider Keys',
                children: [ApiKeysSection()],
              ),
              const SizedBox(height: 16),

              // Danger zone
              _SectionCard(
                title: 'Danger Zone',
                titleColor: kErrorRed,
                borderColor: kErrorRed,
                shadowColor: kErrorRed,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sign out of Nova 3D on this device.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: kInkSoft,
                          ),
                        ),
                      ),
                      _SmallChunkyButton(
                        label: 'Sign out',
                        onTap: () => _confirmSignOut(context, ref),
                        color: kSurface,
                        textColor: kErrorRed,
                        borderColor: kErrorRed,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kInk, width: 1.5),
        ),
        title: Text('Sign out?', style: kVt323(28, color: kInk)),
        content: Text(
          'You will be returned to the sign-in screen.',
          style: GoogleFonts.inter(color: kInkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go('/signin');
            },
            child: Text(
              'Sign out',
              style: GoogleFonts.inter(
                color: kErrorRed,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.bg = kSurface,
    this.titleColor,
    this.borderColor,
    this.shadowColor,
  });

  final String title;
  final List<Widget> children;
  final Color bg;
  final Color? titleColor;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: kChunkyCard(
      bg: bg,
      borderColor: borderColor,
      shadowColor: shadowColor,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: kSilkscreen(
                11,
                color: titleColor ?? kInk,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1.5, color: kLineSoft)),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

// ── Small chunky button ────────────────────────────────────────────────────────

class _SmallChunkyButton extends StatefulWidget {
  const _SmallChunkyButton({
    required this.label,
    required this.onTap,
    this.color = kSurface,
    this.textColor = kInk,
    this.borderColor = kInk,
  });
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;
  final Color borderColor;

  @override
  State<_SmallChunkyButton> createState() => _SmallChunkyButtonState();
}

class _SmallChunkyButtonState extends State<_SmallChunkyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.borderColor, width: 1.5),
        boxShadow: _pressed
            ? []
            : [
                BoxShadow(
                  color: widget.borderColor,
                  offset: const Offset(2, 2),
                  blurRadius: 0,
                ),
              ],
      ),
      child: Text(
        widget.label,
        style: kSilkscreen(10, color: widget.textColor),
      ),
    ),
  );
}
