import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/features/api_keys/state/api_key_provider.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/models/texture_draft.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/magic_texture_dialog.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:nova3d_frontend/features/showcase/state/showcase_texture_intent.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/shared/services/viewer_pointer_guard.dart';

/// Runs the shared "texture a showcase model" flow: collect inputs via the
/// Magic Texture dialog, create a fresh conversation, hand the run off as a
/// [TextureDraft], and navigate into it. Callers MUST ensure the user is signed
/// in first (the dialog + a real conversation require an authenticated user).
///
/// Everything that outlives an `await` is captured up front so the flow stays
/// correct even if the calling widget unmounts mid-dialog (it navigates away on
/// success): the router instance and provider notifiers are read before any
/// await, and [BuildContext] is only used for `showDialog` while still mounted.
Future<void> launchShowcaseTexture(
  WidgetRef ref,
  BuildContext context,
  ShowcaseTextureIntent intent,
) async {
  if (!intent.isComplete) return;

  final router = GoRouter.of(context);
  final apiKeyService = ref.read(apiKeyServiceProvider);
  final conversations = ref.read(conversationsProvider.notifier);
  final textureDrafts = ref.read(textureDraftsProvider.notifier);

  final savedKeys = await apiKeyService.loadValidKeys();
  if (!context.mounted) return;

  // The showcase (and any model viewer) is an iframe that swallows pointer
  // events over its region on web; disable that capture while the modal is up.
  setViewerIframesInteractive(false);
  final TextureRequest? request;
  try {
    request = await showDialog<TextureRequest>(
      context: context,
      builder: (_) =>
          MagicTextureDialog(initialGeminiKey: savedKeys['gemini'] ?? ''),
    );
  } finally {
    setViewerIframesInteractive(true);
  }
  if (request == null) return;

  final conversation = await conversations.create(intent.title);
  textureDrafts.put(
    conversation.id,
    TextureDraft(
      request: request,
      glbArtifact: {'url': intent.glbUrl},
      codeArtifact: {'url': intent.codeUrl},
      sourceId: 'showcase-${intent.id}',
    ),
  );
  router.go('/chat/${conversation.id}');
}

/// Invisible shell wrapper that resumes a showcase texture request which was
/// stashed while the user was signed OUT. It lives in the authenticated shell
/// (mounted on every authed route), so it catches the moment sign-in completes
/// and the user lands back inside the app, then continues the flow exactly where
/// the sign-in gate paused it.
class ShowcaseTextureResumer extends ConsumerStatefulWidget {
  const ShowcaseTextureResumer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShowcaseTextureResumer> createState() =>
      _ShowcaseTextureResumerState();
}

class _ShowcaseTextureResumerState
    extends ConsumerState<ShowcaseTextureResumer> {
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    // The authenticated shell usually mounts AFTER auth flips to signed-in (the
    // router redirects an authed user off /signin to '/'), so the transition is
    // already in the past by the time any listener could fire. Check once on
    // mount to catch that common case.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeResume());
  }

  void _maybeResume() {
    if (_inFlight || !mounted) return;
    if (ref.read(authProvider).valueOrNull == null) return;
    if (ref.read(pendingShowcaseTextureProvider) == null) return;

    final intent =
        ref.read(pendingShowcaseTextureProvider.notifier).consumeFresh();
    if (intent == null || !intent.isComplete) return;

    _inFlight = true;
    launchShowcaseTexture(ref, context, intent).whenComplete(() {
      if (mounted) setState(() => _inFlight = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rare case: the shell is already mounted when auth flips (e.g. a silent
    // token refresh resolving to a user). The post-frame keeps us out of the
    // build phase before opening a dialog.
    ref.listen<AsyncValue<UserModel?>>(authProvider, (previous, next) {
      final becameSignedIn =
          previous?.valueOrNull == null && next.valueOrNull != null;
      if (becameSignedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeResume());
      }
    });
    return widget.child;
  }
}
