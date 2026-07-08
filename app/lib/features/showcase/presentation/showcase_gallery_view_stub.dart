import 'package:flutter/widgets.dart';

/// Non-web fallback. The app ships on web; this only exists so the package
/// compiles for other targets.
class ShowcaseGalleryView extends StatelessWidget {
  const ShowcaseGalleryView({super.key, required this.manifestUrl});

  final String manifestUrl;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
