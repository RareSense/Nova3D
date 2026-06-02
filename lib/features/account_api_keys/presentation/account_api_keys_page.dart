import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/account_api_keys/presentation/account_api_keys_section.dart';

class AccountApiKeysPage extends StatelessWidget {
  const AccountApiKeysPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kPink,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: kInk,
                        offset: Offset(2, 2),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.vpn_key_outlined, color: kInk),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('get API key', style: kVt323(44, color: kInk)),
                      const SizedBox(height: 2),
                      Text(
                        'Create long-lived Nova3D tokens for nova3d-mcp, CLIs, and direct API access.',
                        style: GoogleFonts.inter(fontSize: 14, color: kInkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: kChunkyCard(),
              child: const AccountApiKeysSection(),
            ),
          ],
        ),
      ),
    ),
  );
}
