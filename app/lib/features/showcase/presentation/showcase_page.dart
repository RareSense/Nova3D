import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/showcase/presentation/showcase_gallery_view.dart';

/// Public, no-login gallery of hand-picked models. Read-only: it embeds the
/// standalone Three.js gallery pointed at the public manifest URL. Curation
/// happens entirely off-app (a private publish script writes the manifest +
/// assets to a public bucket), so there is no write path in the client.
class ShowcasePage extends ConsumerWidget {
  const ShowcasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Column(
          children: [
            _Header(signedIn: signedIn),
            Expanded(
              child: kShowcaseManifestUrl.trim().isEmpty
                  ? const _Empty()
                  : const ShowcaseGalleryView(
                      manifestUrl: kShowcaseManifestUrl,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kInk, width: 1.5)),
      ),
      child: Row(
        children: [
          const Text('✦', style: TextStyle(color: kLilac, fontSize: 18)),
          const SizedBox(width: 10),
          Text('SHOWCASE', style: kSilkscreen(13, color: kInk, letterSpacing: 1)),
          const Spacer(),
          _NavButton(
            label: signedIn ? 'Home' : 'Sign in',
            onTap: () => context.go(signedIn ? '/' : '/signin'),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kLilac,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Text(label, style: kSilkscreen(10, color: kInk)),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('✦', style: TextStyle(color: kLilac, fontSize: 30)),
        const SizedBox(height: 12),
        Text(
          'Showcase coming soon',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: kInk),
        ),
      ],
    ),
  );
}
