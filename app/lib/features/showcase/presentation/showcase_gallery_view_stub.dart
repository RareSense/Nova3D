import 'package:flutter/widgets.dart';

/// Non-web fallback. The app ships on web; this only exists so the package
/// compiles for other targets.
class ShowcaseGalleryView extends StatelessWidget {
  const ShowcaseGalleryView({super.key, required this.manifestUrl, this.tab});

  final String manifestUrl;
  final String? tab;

  /// Web-only in practice; no-op on other targets.
  static void setTab(String manifestUrl, String tab) {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
