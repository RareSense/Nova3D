import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';

class ImageAttachmentChip extends StatelessWidget {
  const ImageAttachmentChip({
    super.key,
    required this.name,
    required this.onClear,
  });

  final String name;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: 10, right: 2),
    decoration: BoxDecoration(
      color: kBgTertiary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kBorderColor),
    ),
    child: Row(
      children: [
        const Icon(Icons.image_outlined, size: 16, color: kAccentBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Remove image',
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 16),
          color: kTextMuted,
        ),
      ],
    ),
  );
}
