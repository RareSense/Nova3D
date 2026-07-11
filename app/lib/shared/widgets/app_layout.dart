import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/showcase/presentation/showcase_texture_controller.dart';
import 'package:nova3d_frontend/shared/widgets/app_sidebar.dart';
import 'package:nova3d_frontend/shared/widgets/credit_balance_pill.dart';
import 'package:nova3d_frontend/shared/widgets/grid_background.dart';

class AppLayout extends StatelessWidget {
  const AppLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Wraps the shell so a showcase texture request stashed before sign-in
    // resumes automatically once the user lands back inside the app.
    return ShowcaseTextureResumer(child: _buildLayout(context));
  }

  Widget _buildLayout(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showSidebar = width >= kSidebarBreakpoint;

    if (showSidebar) {
      return Scaffold(
        backgroundColor: kCream,
        body: GridBackground(
          child: Row(
            children: [
              const AppSidebar(),
              Container(width: 1, color: kInk),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: child),
                    const Positioned(
                      top: 16,
                      right: 20,
                      child: CreditBalancePill(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _MobileLayout(child: child);
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kCream,
    drawer: const Drawer(backgroundColor: kSurface, child: AppSidebar()),
    appBar: AppBar(
      backgroundColor: kSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: kInk),
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: kInk),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Text(
        'nova3d',
        style: GoogleFonts.vt323(
          color: kInk,
          fontSize: 22,
          letterSpacing: 1,
          height: 1,
        ),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 12),
          child: CreditBalancePill(compact: true),
        ),
      ],
    ),
    body: GridBackground(child: child),
  );
}
