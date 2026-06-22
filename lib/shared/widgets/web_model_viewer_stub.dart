import 'package:flutter/widgets.dart';

/// Non-web fallback (the app ships on web).
class WebModelViewer extends StatelessWidget {
  const WebModelViewer({super.key, required this.src});

  final String src;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
