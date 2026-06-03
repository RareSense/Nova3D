import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:nova3d_frontend/shared/widgets/nova_logo.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final conversations = ref.watch(conversationsProvider);
    final currentLocation = GoRouterState.of(context).uri.toString();

    return Container(
      width: kSidebarWidth,
      color: kSurface,
      child: Column(
        children: [
          // Header / logo
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(
              children: [
                const NovaLogo(size: 26),
                const Spacer(),
                _IconBtn(
                  icon: Icons.add,
                  tooltip: 'New conversation',
                  onTap: () => context.go('/'),
                ),
              ],
            ),
          ),
          Container(height: 1, color: kInk),

          // New chat button
          Padding(
            padding: const EdgeInsets.all(12),
            child: _AccentButton(
              label: 'New creation',
              icon: Icons.add,
              onTap: () => context.go('/'),
            ),
          ),

          // Conversations label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RECENT',
                style: kSilkscreen(9, color: kInkMuted, letterSpacing: 0.8),
              ),
            ),
          ),

          // Conversation list
          Expanded(
            child: conversations.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: kLilac,
                    strokeWidth: 2,
                  ),
                ),
              ),
              error: (_, _) => Center(
                child: Text(
                  'Failed to load',
                  style: GoogleFonts.inter(color: kInkMuted, fontSize: 12),
                ),
              ),
              data: (convs) => convs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No conversations yet',
                          style: GoogleFonts.inter(
                            color: kInkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      itemCount: convs.length,
                      itemBuilder: (_, i) {
                        final conv = convs[i];
                        final isActive = currentLocation == '/chat/${conv.id}';
                        return _ConversationTile(
                          title: conv.title,
                          isActive: isActive,
                          onTap: () => context.go('/chat/${conv.id}'),
                          onDelete: () {
                            ref
                                .read(conversationsProvider.notifier)
                                .remove(conv.id);
                            if (isActive) context.go('/');
                          },
                        );
                      },
                    ),
            ),
          ),

          Container(height: 1, color: kLineSoft),

          // Bottom nav
          _SidebarNavItem(
            icon: Icons.workspace_premium_outlined,
            label: 'Subscription',
            isActive: currentLocation == '/subscription',
            onTap: () => context.go('/subscription'),
          ),
          _SidebarNavItem(
            icon: Icons.vpn_key_outlined,
            label: 'Get API Key',
            isActive: currentLocation == '/api-key',
            onTap: () => context.go('/api-key'),
          ),
          _SidebarNavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isActive: currentLocation == '/settings',
            onTap: () => context.go('/settings'),
          ),
          const SizedBox(height: 4),

          // User row
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: kLilacBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kLineSoft),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: kPink,
                        shape: BoxShape.circle,
                        border: Border.all(color: kInk, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          user.email.isNotEmpty
                              ? user.email.substring(0, 1).toUpperCase()
                              : '?',
                          style: kSilkscreen(11, color: kInk),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        user.email,
                        style: GoogleFonts.inter(color: kInkSoft, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.logout,
                        size: 15,
                        color: kInkMuted,
                      ),
                      tooltip: 'Sign out',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        await ref.read(authProvider.notifier).signOut();
                        if (context.mounted) context.go('/signin');
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Accent button ──────────────────────────────────────────────────────────────
class _AccentButton extends StatefulWidget {
  const _AccentButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: kPink,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: _pressed
            ? []
            : const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
      ),
      child: Row(
        children: [
          Icon(widget.icon, size: 16, color: kInk),
          const SizedBox(width: 8),
          Text(widget.label.toUpperCase(), style: kSilkscreen(11, color: kInk)),
        ],
      ),
    ),
  );
}

// ── Icon button ────────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: kInkSoft, size: 20),
      ),
    ),
  );
}

// ── Conversation tile ──────────────────────────────────────────────────────────
class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    required this.title,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isActive
              ? kPinkBg
              : _hovering
              ? kLineSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isActive ? kInk : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: widget.isActive
              ? const [
                  BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: kPink,
                shape: BoxShape.circle,
                border: Border.all(color: kInk),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: widget.isActive ? kInk : kInkSoft,
                  fontSize: 13,
                  fontWeight: widget.isActive
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
            if (_hovering)
              InkWell(
                onTap: widget.onDelete,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: kInkMuted),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ── Sidebar nav item ───────────────────────────────────────────────────────────
class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isActive
              ? kLilacBg
              : _hovering
              ? kLineSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isActive ? kInk : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 16,
              color: widget.isActive ? kInk : kInkSoft,
            ),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                color: widget.isActive ? kInk : kInkSoft,
                fontSize: 13,
                fontWeight: widget.isActive
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
