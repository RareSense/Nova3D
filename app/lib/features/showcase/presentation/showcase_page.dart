import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/showcase/presentation/showcase_gallery_view.dart';
import 'package:nova3d_frontend/features/showcase/presentation/showcase_texture_controller.dart';
import 'package:nova3d_frontend/features/showcase/state/showcase_texture_intent.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';

/// The showcase catalog tabs, each with its own app URL:
///   /showcase (or /showcase/generations), /showcase/textures, /showcase/rings.
const Set<String> kShowcaseTabs = {'generations', 'textures', 'rings'};

/// Canonical app path for a tab. `generations` is the clean base `/showcase`.
String showcaseTabPath(String tab) =>
    tab == 'generations' ? '/showcase' : '/showcase/$tab';

/// Public, no-login gallery of hand-picked models. Read-only: it embeds the
/// standalone Three.js gallery pointed at the public manifest URL. Curation
/// happens entirely off-app (a private publish script writes the manifest +
/// assets to a public bucket), so there is no write path in the client.
///
/// [tab] comes from the route (`/showcase/:tab`); it seeds which catalog opens
/// and is kept in sync with the embedded gallery both ways (see below).
class ShowcasePage extends ConsumerWidget {
  const ShowcasePage({super.key, this.tab});

  final String? tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final activeTab = kShowcaseTabs.contains(tab) ? tab! : 'generations';

    // URL → gallery: keep the already-mounted iframe on the tab the URL names
    // (deep link, back/forward, or any programmatic nav). Idempotent — the
    // gallery ignores a set-tab for the tab it already shows. Post-frame so the
    // platform view has mounted before we message it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShowcaseGalleryView.setTab(kShowcaseManifestUrl, activeTab);
    });

    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Column(
          children: [
            const _ShowcaseTextureBridge(),
            _Header(signedIn: signedIn),
            Expanded(
              child: kShowcaseManifestUrl.trim().isEmpty
                  ? const _Empty()
                  : ShowcaseGalleryView(
                      manifestUrl: kShowcaseManifestUrl,
                      tab: activeTab,
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

/// Invisible listener that receives the showcase iframe's `postMessage` when a
/// visitor presses "Texture" on a model, and turns it into either an immediate
/// texture flow (signed in) or a stash-then-sign-in (signed out). Mounted only
/// while the showcase is on screen — exactly when such a message can arrive —
/// and torn down (subscription cancelled) as soon as the flow navigates away.
class _ShowcaseTextureBridge extends ConsumerStatefulWidget {
  const _ShowcaseTextureBridge();

  @override
  ConsumerState<_ShowcaseTextureBridge> createState() =>
      _ShowcaseTextureBridgeState();
}

class _ShowcaseTextureBridgeState
    extends ConsumerState<_ShowcaseTextureBridge> {
  StreamSubscription<web.MessageEvent>? _sub;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    _sub = web.window.onMessage.listen(_onMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data?.dartify();
    if (data is! Map) return;

    // gallery → URL: a tab click inside the iframe updates the address bar so
    // each tab is a shareable link and back/forward walk the tabs.
    if (data['type'] == 'nova3d-showcase-tab') {
      final tab = (data['tab'] ?? '').toString();
      if (kShowcaseTabs.contains(tab) && mounted) {
        analytics.capture(Ev.showcaseTabChanged, <String, Object?>{
          Pr.showcaseTab: tab,
        });
        context.go(showcaseTabPath(tab));
      }
      return;
    }

    if (data['type'] != 'nova3d-showcase-texture') return;
    final entry = data['entry'];
    if (entry is! Map) return;

    final glbUrl = (entry['glb_url'] ?? '').toString().trim();
    final codeUrl = (entry['code_url'] ?? '').toString().trim();
    // Texturing fetches both server-side, so only absolute http(s) URLs work
    // (the prod showcase serves absolute blob URLs; relative dev URLs cannot be
    // resolved by the backend). Silently ignore anything else.
    if (!_isAbsoluteHttp(glbUrl) || !_isAbsoluteHttp(codeUrl)) return;

    _handleIntent(
      ShowcaseTextureIntent(
        id: (entry['id'] ?? '').toString(),
        title: _cleanTitle((entry['title'] ?? '').toString()),
        glbUrl: glbUrl,
        codeUrl: codeUrl,
      ),
    );
  }

  Future<void> _handleIntent(ShowcaseTextureIntent intent) async {
    if (_handling || !mounted) return;
    // The Texture button lives INSIDE the showcase iframe, so the browser's
    // keyboard focus is trapped there. Return it to the host document before we
    // open anything, or the texture dialog (signed in) or the sign-in form
    // (signed out) can be clicked but not typed into on web.
    _returnFocusToHost();
    final signedIn = ref.read(authProvider).valueOrNull != null;
    if (!signedIn) {
      // Remember the request across the sign-in round trip, then gate.
      ref.read(pendingShowcaseTextureProvider.notifier).set(intent);
      context.go('/signin');
      return;
    }
    _handling = true;
    try {
      await launchShowcaseTexture(ref, context, intent);
    } finally {
      if (mounted) _handling = false;
    }
  }

  // Moves keyboard focus out of the (currently focused) showcase iframe back to
  // the host window, so Flutter text fields opened on top can receive input.
  void _returnFocusToHost() {
    final active = web.document.activeElement;
    if (active != null && active.isA<web.HTMLElement>()) {
      (active as web.HTMLElement).blur();
    }
    web.window.focus();
    // Blurring alone parks DOM focus on <body>, which is OUTSIDE the Flutter
    // view. The engine's anti-focus-stealing guard then refuses to move DOM
    // focus into its hidden text input, so dialog text fields show a caret but
    // ignore every keystroke. Hand DOM focus to the Flutter view host element
    // so the engine owns the focus again before the dialog opens.
    final host =
        web.document.querySelector('flutter-view') ??
        web.document.querySelector('flt-glass-pane');
    if (host != null && host.isA<web.HTMLElement>()) {
      final el = host as web.HTMLElement;
      if (el.getAttribute('tabindex') == null) el.tabIndex = -1;
      el.focus();
    }
  }

  static bool _isAbsoluteHttp(String url) =>
      url.startsWith('https://') || url.startsWith('http://');

  static String _cleanTitle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Showcase model';
    return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
