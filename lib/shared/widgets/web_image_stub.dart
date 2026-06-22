import 'package:flutter/widgets.dart';

/// Non-web fallback (the app ships on web).
class WebImage extends StatelessWidget {
  const WebImage({super.key, required this.src});

  final String src;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
