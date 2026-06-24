import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/shared/widgets/glb_viewer.dart';

class ModelPreviewPage extends StatelessWidget {
  const ModelPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_in_ar, color: kAccentBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  '3D Model Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  'model.glb',
                  style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Expanded(
              child: GlbViewer(src: 'assets/models/model.glb'),
            ),
          ],
        ),
      ),
    );
  }
}
