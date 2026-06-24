import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';

class GenerationModelLabel extends StatelessWidget {
  const GenerationModelLabel({
    super.key,
    required this.option,
    this.compact = false,
  });

  final GenerationModelOption option;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badge = option.badgeLabel;
    final nameStyle = GoogleFonts.inter(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w800,
      color: kInk,
      height: 1.1,
    );
    final detailStyle = GoogleFonts.inter(
      fontSize: compact ? 10 : 11,
      fontWeight: FontWeight.w700,
      color: kInkSoft,
      height: 1.1,
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              option.compactLabel,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              option.detailLabel,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                option.compactLabel,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
              const SizedBox(height: 3),
              Text(
                option.detailLabel,
                overflow: TextOverflow.ellipsis,
                style: detailStyle,
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          _ModelBadge(label: badge),
        ],
      ],
    );
  }
}

class _ModelBadge extends StatelessWidget {
  const _ModelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: label == 'Recommended'
          ? const Color(0xFFFFF2B8)
          : const Color(0xFFFFDDEB),
      border: Border.all(color: kInk, width: 1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: kInk,
          height: 1,
        ),
      ),
    ),
  );
}
