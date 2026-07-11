import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request to texture a specific showcase model, captured from the showcase
/// iframe's `postMessage`. It carries only public URLs, so it is safe to hold
/// in memory across a sign-in redirect.
class ShowcaseTextureIntent {
  ShowcaseTextureIntent({
    required this.id,
    required this.title,
    required this.glbUrl,
    required this.codeUrl,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  final String id;
  final String title;
  final String glbUrl;
  final String codeUrl;

  /// When this intent was captured. A stashed intent is only auto-resumed after
  /// sign-in while it is still fresh (see [isFresh]), so an old, abandoned
  /// intent never surprises the user by opening a dialog on a later login.
  final DateTime capturedAt;

  /// Both a model and its source program are required to texture.
  bool get isComplete => glbUrl.trim().isNotEmpty && codeUrl.trim().isNotEmpty;

  bool get isFresh =>
      DateTime.now().difference(capturedAt) < const Duration(minutes: 10);
}

/// Holds a texture intent captured while the user was signed OUT, so it can be
/// resumed once sign-in completes. Deliberately does NOT reset on auth change
/// (unlike the chat drafts): it must survive the exact null → user transition
/// that a post-sign-in resume depends on. It is cleared explicitly the moment
/// it is consumed.
class PendingShowcaseTextureNotifier extends Notifier<ShowcaseTextureIntent?> {
  @override
  ShowcaseTextureIntent? build() => null;

  void set(ShowcaseTextureIntent intent) => state = intent;

  void clear() => state = null;

  /// Returns the pending intent and clears it, but only if it is still fresh.
  /// A stale intent is dropped so it can never fire on an unrelated later login.
  ShowcaseTextureIntent? consumeFresh() {
    final intent = state;
    state = null;
    if (intent == null || !intent.isFresh) return null;
    return intent;
  }
}

final pendingShowcaseTextureProvider =
    NotifierProvider<PendingShowcaseTextureNotifier, ShowcaseTextureIntent?>(
      PendingShowcaseTextureNotifier.new,
    );
