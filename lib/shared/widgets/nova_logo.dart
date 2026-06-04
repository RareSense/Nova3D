import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class NovaLogo extends StatelessWidget {
  const NovaLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      NovaCube(size: size),
      SizedBox(width: size * 0.22),
      RichText(
        text: TextSpan(
          style: GoogleFonts.vt323(
            fontSize: size * 0.72,
            color: kInk,
            letterSpacing: 1,
            height: 1,
          ),
          children: [
            const TextSpan(text: 'nova'),
            TextSpan(text: '3d', style: TextStyle(color: kPink)),
          ],
        ),
      ),
    ],
  );
}
