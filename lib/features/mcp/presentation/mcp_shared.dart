import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/shared/widgets/grid_background.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class McpScaffold extends StatelessWidget {
  const McpScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kCream,
    body: GridBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: kChunkyCard(radius: 8),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class McpHeader extends StatelessWidget {
  const McpHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String? badge;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const NovaCube(size: 56),
      const SizedBox(height: 18),
      if (badge != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: kMintBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kInk, width: 1.3),
          ),
          child: Text(badge!, style: kSilkscreen(10, color: kInk)),
        ),
        const SizedBox(height: 14),
      ],
      Text(title, textAlign: TextAlign.center, style: kVt323(46)),
      const SizedBox(height: 10),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(height: 1.45, color: kInkSoft),
      ),
    ],
  );
}

class McpInfoPanel extends StatelessWidget {
  const McpInfoPanel({super.key, required this.children, this.tint = kMintBg});

  final List<Widget> children;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kInk, width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class McpMessageBanner extends StatelessWidget {
  const McpMessageBanner({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError ? kPinkBg : kMintBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: isError ? kErrorRed : kMint, width: 1.2),
    ),
    child: Text(
      message,
      style: GoogleFonts.inter(color: kInk, fontSize: 13, height: 1.4),
    ),
  );
}

class McpPrimaryButton extends StatelessWidget {
  const McpPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: loading ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: kPink,
        foregroundColor: kInk,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: kSilkscreen(11, color: kInk),
        side: const BorderSide(color: kInk, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
            )
          : Text(label),
    ),
  );
}

class McpSecondaryButton extends StatelessWidget {
  const McpSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: const BorderSide(color: kInk, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: kSilkscreen(11, color: kInk),
      ),
      child: Text(label),
    ),
  );
}

class McpStatusRow extends StatelessWidget {
  const McpStatusRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 138,
          child: Text(
            label,
            style: const TextStyle(
              color: kInkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: kInk,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}
